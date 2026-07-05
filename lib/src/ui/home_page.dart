import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../model/config.dart';
import '../native/bindings.dart';
import '../native/auth_controller.dart';
import '../native/keep_alive_channel.dart';
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
  String _statusText = 'Initializing...';
  String _statusDetail = '';
  bool? _accessibilityEnabled; // null = 未查询, true/false = 结果
  final AuthController _authCtrl = AuthController.instance;

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    if (Platform.isAndroid) {
      _accessibilityEnabled = await KeepAliveChannel.isAccessibilityEnabled;
    }
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
      setState(() {
        _config = config;
        _statusText = config.enabled ? 'Ready' : 'Disabled';
        _statusDetail = config.enabled
            ? '${config.accounts.length} account(s) configured'
            : 'Please configure accounts in settings';
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

  Future<void> _checkPermissions() async {
    await [
      Permission.location,
      Permission.locationWhenInUse,
      Permission.notification,
    ].request();
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

    setState(() {
      _isRunning = true;
      _statusText = 'Initializing native layer...';
      _statusDetail = '';
    });

    try {
      // 获取 Android 沙盒路径
      final appDir = await getApplicationDocumentsDirectory();

      // 构建 JSON 配置
      final configJson = jsonEncode(_config!.toJson());

      // 初始化 C 层（传入沙盒路径和配置）
      final ok = await _authCtrl.initialize(appDir.path, configJson);
      if (!ok) {
        if (mounted) setState(() => _statusText = 'Native init failed');
        return;
      }

      // 启动认证（C 层内部创建 pthread 运行 dialer_app）
      final started = await _authCtrl.start();
      if (mounted) {
        if (started) {
          setState(() {
            _statusText = 'Authenticated — heartbeat active';
            _statusDetail = 'Running in background thread';
          });
        } else {
          setState(() {
            _isRunning = false;
            _statusText = 'Failed to start authentication';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRunning = false;
          _statusText = 'Error: $e';
        });
      }
    }
  }

  Future<void> _stopAuth() async {
    setState(() {
      _statusText = 'Stopping...';
    });

    await _authCtrl.stop(waitForExit: true);

    if (mounted) {
      setState(() {
        _isRunning = false;
        _statusText = 'Stopped';
        _statusDetail = '';
      });
    }
  }

  void _showConfigRequiredDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Configuration Required'),
        content: const Text(
          'Please add at least one account with both username and password in Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
            },
            child: const Text('Open Settings'),
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
            tooltip: 'Settings',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
              _loadConfig();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              children: [
                // ── 状态 Hero 卡 ──
                _buildStatusHero(theme, cs),
                const SizedBox(height: 16),

                // ── 黄色警告卡 ──
                _buildWarningCard(theme, cs),
                const SizedBox(height: 12),

                // ── 增强保活卡 (Android only) ──
                if (Platform.isAndroid) ...[
                  _buildAccessibilityTile(theme, cs),
                  const SizedBox(height: 24),
                ],

                // ── 主操作区 ──
                _buildPrimaryButton(theme, cs),
                if (_isRunning) ...[
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton.icon(
                      onPressed: () => _authCtrl.forceAuthReset(),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('强制重新认证'),
                      style: TextButton.styleFrom(foregroundColor: cs.error),
                    ),
                  ),
                ],
                const SizedBox(height: 24),

                // ── 账号摘要 ──
                if (_config != null && _config!.accounts.isNotEmpty)
                  _buildAccountCard(theme, cs),

                const Spacer(),

                Center(
                  child: Text(
                    'ESurfing Client v1.0.0\nFlutter + NDK FFI',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ),
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

  Widget _buildWarningCard(ThemeData theme, ColorScheme cs) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: cs.errorContainer.withOpacity(0.5),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 20, color: cs.error),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Flutter 版注意:熄屏约 30 分钟以上 Android 会回收进程,需重新打开 APP 才能继续守护。Magisk 版无此限制。',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrimaryButton(ThemeData theme, ColorScheme cs) {
    final isUp = _isRunning;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.icon(
        icon: Icon(isUp ? Icons.stop : Icons.play_arrow),
        label: Text(isUp ? 'Stop Authentication' : 'Start Authentication'),
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
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Configured Accounts',
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
                title: Text(a.username.isEmpty ? '(empty)' : a.username),
                subtitle: Text('Channel: ${a.channel}'),
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
                  if (!isOn) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await KeepAliveChannel.openAccessibilitySettings();
                        if (mounted) {
                          final newState =
                              await KeepAliveChannel.isAccessibilityEnabled;
                          setState(() => _accessibilityEnabled = newState);
                        }
                      },
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('去开启'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cs.tertiary,
                        side: BorderSide(
                            color: cs.tertiary.withOpacity(0.5)),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
