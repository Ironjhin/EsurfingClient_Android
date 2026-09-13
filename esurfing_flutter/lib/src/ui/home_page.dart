import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../model/config.dart';
import '../native/auth_controller.dart';
import '../native/keep_alive_channel.dart';
import '../i18n/app_localizations.dart';
import '../services/log_reader.dart';
import '../widgets/log_viewer.dart';
import '../widgets/liquid_glass_ui.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  ESurfingConfig? _config;
  bool _isLoading = true;
  bool _isRunning = false;
  String _statusText = ''; // 由首帧 i18n 注入
  String _statusDetail = '';
  bool? _accessibilityEnabled; // null = 未查询, true/false = 结果
  final AuthController _authCtrl = AuthController.instance;

  // 运行时间相关
  DateTime? _startTime;
  Timer? _uptimeTimer;
  String _uptimeText = '';

  // 实时日志读取器 — 后台 poll run.log,生命周期跟随页面.
  final LogReader _logReader = LogReader();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initApp();
    _logReader.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _uptimeTimer?.cancel();
    _authCtrl.onStatusChanged = null;
    _logReader.dispose();
    super.dispose();
  }

  // 切回前台时(从系统设置页 / 多任务回来)刷一次无障碍状态 —
  // 系统若清理了后台进程,服务会断开,这里立刻反映到 UI.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && Platform.isAndroid) {
      _refreshAccessibility();
    }
  }

  Future<void> _initApp() async {
    await _loadConfig();
    await _checkPermissions();

    // 注册状态回调
    _authCtrl.onStatusChanged = (running, text) {
      if (mounted) {
        setState(() {
          _isRunning = running;
          _statusText = text;
        });
        if (running && _startTime == null) {
          _startUptimeTimer();
        } else if (!running && _startTime != null) {
          _stopUptimeTimer();
        }
      }
    };

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _startUptimeTimer() {
    _startTime = DateTime.now();
    _uptimeTimer?.cancel();
    _uptimeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _startTime != null) {
        setState(() {
          _uptimeText = _formatUptime(DateTime.now().difference(_startTime!));
        });
      }
    });
  }

  void _stopUptimeTimer() {
    _uptimeTimer?.cancel();
    _uptimeTimer = null;
    _startTime = null;
    if (mounted) {
      setState(() {
        _uptimeText = '';
      });
    }
  }

  String _formatUptime(Duration duration) {
    final days = duration.inDays;
    final hours = duration.inHours % 24;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    final i18n = AppLocalizations.of(context);
    return i18n.uptimeFormatted(
      days: days,
      hours: hours,
      minutes: minutes,
      seconds: seconds,
    );
  }

  Future<void> _loadConfig() async {
    final configManager = await ConfigManager.getInstance();
    final config = await configManager.loadConfig();
    if (mounted) {
      final i18n = AppLocalizations.of(context);
      setState(() {
        _config = config;
        _statusText = config.enabled ? i18n.ready : i18n.disabledHint;
        _statusDetail = config.enabled
            ? i18n.accountCount.replaceAll('{n}', '${config.accounts.length}')
            : i18n.configInSettings;
      });
      // 无论是冷启动还是从 Settings 返回,都尝试自动启动
      _tryAutoStart();
    }
  }

  /// 配置有效且已启用时自动进入认证(共用:冷启动 + Settings 返回)
  /// 只负责"启动":若服务已在运行则直接返回,绝不停掉它 —
  /// 否则从 Settings 返回时 _loadConfig 会触发 _toggleAuth 把运行中的认证停掉。
  void _tryAutoStart() {
    if (_isRunning) return;
    final c = _config;
    if (c == null || !c.enabled) return;
    final hasAccount = c.accounts.any(
      (a) => a.username.isNotEmpty && a.password.isNotEmpty,
    );
    if (!hasAccount) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _toggleAuth());
  }

  /// 查询无障碍服务是否启用的真实状态 — 通过原生 MethodChannel.
  Future<void> _refreshAccessibility() async {
    if (!Platform.isAndroid) return;
    final enabled = await KeepAliveChannel.isAccessibilityEnabled;
    if (!mounted) return;
    setState(() => _accessibilityEnabled = enabled);
  }

  Future<void> _checkPermissions() async {
    await [
      Permission.location,
      Permission.locationWhenInUse,
      Permission.notification,
    ].request();
    // 权限请求完毕后顺便查一次无障碍状态 — 初次查询在这里避免启动阻塞.
    await _refreshAccessibility();
  }

  Future<void> _toggleAuth() async {
    if (_config == null) return;

    if (_isRunning) {
      await _stopAuth();
      return;
    }

    // 检查至少有一个有效账号
    final validAccounts = _config!.accounts
        .where((a) => a.username.isNotEmpty && a.password.isNotEmpty)
        .toList();
    if (validAccounts.isEmpty) {
      _showConfigRequiredDialog();
      return;
    }

    final i18n = AppLocalizations.of(context);
    setState(() {
      _isRunning = true;
      _statusText = i18n.initializing;
      _statusDetail = '';
    });

    try {
      // 获取 Android 沙盒路径
      final appDir = await getApplicationDocumentsDirectory();

      // 构建 JSON 配置
      final configJson = jsonEncode(_config!.toJson());

      // 初始化 C 层(传入沙盒路径和配置)
      final ok = await _authCtrl.initialize(appDir.path, configJson);
      if (!ok) {
        if (mounted) setState(() => _statusText = i18n.nativeInitFailed);
        return;
      }

      // 启动认证(C 层内部创建 pthread 运行 dialer_app)
      // 每个有效账号对应一个拨号线程,必须把数量传给 C 层,否则只会启动第一个账号
      final started = await _authCtrl.start(accountCount: validAccounts.length);
      if (mounted) {
        if (started) {
          setState(() {
            _statusText = i18n.authenticatedHeartbeat;
            _statusDetail = i18n.runningDetail;
          });
          _startUptimeTimer();
        } else {
          setState(() {
            _isRunning = false;
            _statusText = i18n.startFailed;
          });
          _stopUptimeTimer();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRunning = false;
          _statusText = '${i18n.errorPrefix}: $e';
        });
        _stopUptimeTimer();
      }
    }
  }

  Future<void> _stopAuth() async {
    _stopUptimeTimer();
    final i18n = AppLocalizations.of(context);
    setState(() {
      _statusText = i18n.stopRequested;
    });

    await _authCtrl.stop();

    if (mounted) {
      setState(() {
        _isRunning = false;
        _statusText = i18n.stopped;
        _statusDetail = '';
      });
    }
  }

  void _showConfigRequiredDialog() {
    if (!mounted) return;
    final i18n = AppLocalizations.of(context);
    showLiquidGlassDialog<void>(
      context: context,
      builder: (dialogContext) => LiquidGlassDialog(
        title: Text(i18n.configRequiredTitle),
        content: Text(i18n.configRequiredBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(i18n.btnCancel),
          ),
          TextButton(
            onPressed: () {
              // 先关闭对话框,再用"页面的 context"跳转 —
              // dialogContext 在 pop 后即失活,拿它 push 会抛 deactivated 异常。
              Navigator.pop(dialogContext);
              Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
              );
            },
            child: Text(i18n.btnOpenSettings),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final i18n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlassScene(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: GlassTopBar(
                  title: i18n.appTitle,
                  trailing: IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    tooltip: i18n.settingsTitle,
                    onPressed: () async {
                      await Navigator.push<void>(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const SettingsPage(),
                        ),
                      );
                      _loadConfig();
                      // 从 Settings 返回后也刷一遍 — /settings 可能开启了自动启动之类.
                      if (Platform.isAndroid) {
                        await _refreshAccessibility();
                      }
                    },
                  ),
                ),
              ),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                        children: [
                          if (Platform.isAndroid) ...[
                            _buildAccessibilityTile(theme, cs),
                            const SizedBox(height: 14),
                          ],
                          _buildStatusHero(theme, cs),
                          const SizedBox(height: 14),
                          GlassBlendGroup(
                            blend: 10,
                            child: Column(
                              children: [
                                _buildPrimaryButton(cs),
                                if (_isRunning) ...[
                                  const SizedBox(height: 8),
                                  GlassActionButton(
                                    grouped: true,
                                    height: 46,
                                    icon: Icons.refresh,
                                    label: i18n.btnForceReset,
                                    color: cs.error,
                                    onPressed: _authCtrl.forceAuthReset,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 22),
                          if (_config != null && _config!.accounts.isNotEmpty)
                            _buildAccountCard(theme),
                          const SizedBox(height: 14),
                          LogViewer(reader: _logReader),
                          const SizedBox(height: 24),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusHero(ThemeData theme, ColorScheme cs) {
    final isUp = _isRunning;
    final i18n = AppLocalizations.of(context);
    return GlassSurface(
      radius: 30,
      tint: isUp ? cs.primary : cs.surfaceTint,
      glow: true,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      child: Column(
        children: [
          Container(
            width: 82,
            height: 82,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  (isUp ? cs.primary : cs.onSurfaceVariant)
                      .withValues(alpha: 0.22),
                  Colors.transparent,
                ],
              ),
            ),
            child: Icon(
              isUp ? Icons.wifi : Icons.wifi_off,
              size: 54,
              color: isUp ? cs.primary : cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _statusText,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: isUp ? cs.primary : cs.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          if (_statusDetail.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              _statusDetail,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
          if (_isRunning && _uptimeText.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: cs.primary.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Text(
                '${i18n.uptimeLabel}$_uptimeText',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPrimaryButton(ColorScheme cs) {
    final i18n = AppLocalizations.of(context);
    final isUp = _isRunning;
    return GlassActionButton(
      grouped: true,
      icon: isUp ? Icons.stop_rounded : Icons.play_arrow_rounded,
      label: isUp ? i18n.btnStopAuth : i18n.btnStartAuth,
      color: isUp ? cs.error : cs.primary,
      onPressed: _toggleAuth,
    );
  }

  Widget _buildAccountCard(ThemeData theme) {
    final i18n = AppLocalizations.of(context);
    return GlassSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            i18n.configuredAccounts,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ..._config!.accounts.asMap().entries.map((entry) {
            final i = entry.key;
            final a = entry.value;
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(radius: 16, child: Text('${i + 1}')),
              title: Text(a.username.isEmpty ? i18n.emptyAccount : a.username),
              subtitle: Text(
                '${i18n.fieldChannel}: ${i18n.channelDisplayName(a.channel)}',
              ),
            );
          }),
        ],
      ),
    );
  }

  /// 无障碍保活引导卡片 — Android 专属
  Widget _buildAccessibilityTile(ThemeData theme, ColorScheme cs) {
    final i18n = AppLocalizations.of(context);
    final enabled = _accessibilityEnabled;
    // null = 还在查(首次启动) — 显示引导态,和未开启一样的行动按钮.
    final isOn = enabled == true;

    return GlassSurface(
      tint: isOn ? cs.primary : cs.tertiary,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isOn ? Icons.verified_user : Icons.privacy_tip_outlined,
            size: 22,
            color: isOn ? cs.primary : cs.tertiary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isOn
                      ? i18n.keepaliveEnabledTitle
                      : i18n.keepaliveDisabledTitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isOn ? cs.primary : cs.tertiary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isOn
                      ? i18n.keepaliveEnabledBody
                      : i18n.keepaliveDisabledBody,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 2),
                Text(
                  i18n.keepaliveKilledHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 8),
                // 无论是否开启都显示按钮:开启时用于"重新检查/管理",未开启时用于跳转.
                OutlinedButton.icon(
                  onPressed: () async {
                    if (isOn) {
                      // 已开启:刷新状态并告知用户当前真实情况.
                      await _refreshAccessibility();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(i18n.keepaliveStatusRunning),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    } else {
                      // 未开启:直接跳转到无障碍系统页.
                      await KeepAliveChannel.openAccessibilitySettings();
                      // 立刻刷一次:用户可能在系统页开启后返回.
                      // 不依赖 didChangeAppLifecycleState — 原生 Activity 切换
                      // 不一定派发 resumed 事件,这里同步补一次最稳.
                      if (mounted) await _refreshAccessibility();
                    }
                  },
                  icon: Icon(isOn ? Icons.check : Icons.open_in_new, size: 16),
                  label: Text(
                    isOn ? i18n.keepaliveBtnCheck : i18n.keepaliveBtnEnable,
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isOn ? cs.primary : cs.tertiary,
                    side: BorderSide(
                      color: (isOn ? cs.primary : cs.tertiary)
                          .withValues(alpha: 0.5),
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
