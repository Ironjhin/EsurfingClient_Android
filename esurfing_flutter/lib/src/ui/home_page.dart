import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../model/config.dart';
import '../native/bindings.dart';
import '../native/auth_controller.dart';
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

    // 如果启用了自动启动，立即进入认证流程
    if (_config?.enabled == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _toggleAuth();
      });
    }

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
    }
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
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ESurfing Client'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
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
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Status icon
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: _isRunning
                          ? colorScheme.primaryContainer
                          : colorScheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isRunning ? Icons.wifi : Icons.wifi_off,
                      size: 60,
                      color: _isRunning
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Status text
                  Text(
                    _statusText,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: _isRunning ? colorScheme.primary : colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _statusDetail,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),

                  // Start / Stop button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton.icon(
                      icon: Icon(_isRunning ? Icons.stop : Icons.play_arrow),
                      label: Text(
                        _isRunning ? 'Stop Authentication' : 'Start Authentication',
                        style: theme.textTheme.titleMedium,
                      ),
                      onPressed: _toggleAuth,
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            _isRunning ? colorScheme.error : colorScheme.primary,
                        foregroundColor:
                            _isRunning ? colorScheme.onError : colorScheme.onPrimary,
                      ),
                    ),
                  ),
                  if (_isRunning) ...[
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () => _authCtrl.forceAuthReset(),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('强制重新认证'),
                      style: TextButton.styleFrom(
                        foregroundColor: colorScheme.error,
                        textStyle: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // Account summary
                  if (_config != null && _config!.accounts.isNotEmpty) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Configured Accounts',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ..._config!.accounts.asMap().entries.map((entry) {
                              final i = entry.key;
                              final a = entry.value;
                              return ListTile(
                                dense: true,
                                leading: CircleAvatar(child: Text('${i + 1}')),
                                title: Text(a.username.isEmpty ? '(empty)' : a.username),
                                subtitle: Text(
                                  'Channel: ${a.channel} • ${a.userAgent}',
                                  style: theme.textTheme.bodySmall,
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                  ],

                  const Spacer(),

                  Text(
                    'ESurfing Client v1.0.0\nFlutter + NDK FFI',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
    );
  }
}
