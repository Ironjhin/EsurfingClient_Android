import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../model/config.dart';
import '../native/bindings.dart';
import '../native/auth_controller.dart';
import '../native/keep_alive_channel.dart';
import '../i18n/app_localizations.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  ESurfingConfig? _config;
  bool _isLoading = true;
  bool _isRunning = false;
  String _statusText = '';  // 由首帧 i18n 注入
  String _statusDetail = '';
  bool? _accessibilityEnabled; // null = 未查询, true/false = 结果
  final AuthController _authCtrl = AuthController.instance;

  @override
  void initState() {
    super.initState();
    _initApp();
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
      }
    };

    if (mounted) {
      setState(() => _isLoading = false);
    }
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
  void _tryAutoStart() {
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
    final validAccounts =
        _config!.accounts.where((a) => a.username.isNotEmpty && a.password.isNotEmpty).toList();
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
      final started = await _authCtrl.start();
      if (mounted) {
        if (started) {
          setState(() {
            _statusText = i18n.authenticatedHeartbeat;
            _statusDetail = i18n.runningDetail;
          });
        } else {
          setState(() {
            _isRunning = false;
            _statusText = i18n.startFailed;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRunning = false;
          _statusText = '${i18n.errorPrefix}: $e';
        });
      }
    }
  }

  Future<void> _stopAuth() async {
    final i18n = AppLocalizations.of(context);
    setState(() {
      _statusText = i18n.stopRequested;
    });

    await _authCtrl.stop(waitForExit: true);

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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(i18n.configRequiredTitle),
        content: Text(i18n.configRequiredBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(i18n.btnCancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('ESurfing Client'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
              _loadConfig();
              // 从 Settings 返回后也刷一遍 — /settings 可能开启了自动启动之类.
              if (Platform.isAndroid) {
                await _refreshAccessibility();
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              children: [
                // ── 增强保活卡 (Android only) ──
                if (Platform.isAndroid) ...[
                  _buildAccessibilityTile(theme, cs),
                  const SizedBox(height: 12),
                ],

                // ── 状态 Hero 卡 ──
                _buildStatusHero(theme, cs),
                const SizedBox(height: 16),

                // ── 主操作区 ──
                _buildPrimaryButton(theme, cs),
                // ── 强制重新认证 ──
                if (_isRunning) ...[
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton.icon(
                      onPressed: () => _authCtrl.forceAuthReset(),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text(i18n.btnForceReset),
                      style: TextButton.styleFrom(foregroundColor: cs.error),
                    ),
                  ),
                ],
                const SizedBox(height: 24),

                // ── 账号摘要 ──
                if (_config != null && _config!.accounts.isNotEmpty)
                  _buildAccountCard(theme, cs),

                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _buildStatusHero(ThemeData theme, ColorScheme cs) {
    final isUp = _isRunning;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isUp
          ? cs.primaryContainer.withOpacity(0.6)
          : cs.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        child: Column(
          children: [
            Icon(
              isUp ? Icons.wifi : Icons.wifi_off,
              size: 56,
              color: isUp ? cs.primary : cs.onSurfaceVariant,
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
          ],
        ),
      ),
    );
  }

  Widget _buildPrimaryButton(ThemeData theme, ColorScheme cs) {
    final i18n = AppLocalizations.of(context);
    final isUp = _isRunning;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.icon(
        icon: Icon(isUp ? Icons.stop : Icons.play_arrow),
        label: Text(isUp ? i18n.btnStopAuth : i18n.btnStartAuth),
        onPressed: _toggleAuth,
        style: FilledButton.styleFrom(
          backgroundColor: isUp ? cs.error : cs.primary,
          foregroundColor: isUp ? cs.onError : cs.onPrimary,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildAccountCard(ThemeData theme, ColorScheme cs) {
    final i18n = AppLocalizations.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                subtitle: Text('${i18n.fieldChannel}: ${a.channel}'),
              );
            }),
          ],
        ),
      ),
    );
  }

  /// 无障碍保活引导卡片 — Android 专属
  Widget _buildAccessibilityTile(ThemeData theme, ColorScheme cs) {
    final enabled = _accessibilityEnabled;
    // null = 还在查(首次启动) — 显示引导态,和未开启一样的行动按钮.
    final isOn = enabled == true;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isOn
          ? cs.primaryContainer.withOpacity(0.5)
          : cs.tertiaryContainer.withOpacity(0.5),
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                    isOn ? '已开启增强保活' : '开启增强保活',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isOn ? cs.primary : cs.tertiary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isOn
                        ? '系统已放宽电池优化,守护进程不会被回收'
                        : '开启无障碍服务后放宽电池优化限制,熄屏 30 分钟+ 仍保持在线。不会监听或操作你的界面。',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
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
                            const SnackBar(
                              content: Text('无障碍服务仍在运行中 ✓'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      } else {
                        // 未开启:直接跳转到无障碍系统页.
                        await KeepAliveChannel.openAccessibilitySettings();
                        // 从设置页返回后 Flutter 会走到这里,需要刷新状态.
                        // 不立刻刷 — 等用户下一次 onResume 或点击.
                      }
                    },
                    icon: Icon(isOn ? Icons.check : Icons.open_in_new, size: 16),
                    label: Text(isOn ? '检查状态' : '去开启'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isOn ? cs.primary : cs.tertiary,
                      side: BorderSide(
                          color: (isOn ? cs.primary : cs.tertiary)
                              .withOpacity(0.5)),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
