import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../model/config.dart';
import '../native/bindings.dart';
import '../native/auth_controller.dart';
import '../services/log_reader.dart';
import '../widgets/log_viewer.dart';
import '../i18n/app_localizations.dart';
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
  String _statusText = '';
  String _statusDetail = '';
  final AuthController _authCtrl = AuthController.instance;
  final LogReader _logReader = LogReader();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initApp();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _logReader.stop();
    _authCtrl.onStatusChanged = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _logReader.pause();
    } else if (state == AppLifecycleState.resumed) {
      _logReader.resume();
    }
  }

  Future<void> _initApp() async {
    final i18nLocal = AppLocalizations.of(context);
    await _loadConfig();
    await _checkPermissions();
    _logReader.start();

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
      setState(() {
        _isLoading = false;
        _statusText = (_config?.enabled ?? false) ? i18nLocal.ready : i18nLocal.disabledHint;
      });
    }
  }

  Future<void> _loadConfig() async {
    final configManager = await ConfigManager.getInstance();
    final config = await configManager.loadConfig();
    if (mounted) {
      setState(() => _config = config);
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

    final i18n = AppLocalizations.of(context);
    setState(() {
      _isRunning = true;
      _statusText = i18n.initializing;
      _statusDetail = '';
    });

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final configJson = jsonEncode(_config!.toJson());

      _authCtrl.initNativeEnv(appDir.path);
      final ok = await _authCtrl.initialize(appDir.path, configJson);
      if (!ok) {
        if (mounted) setState(() => _statusText = i18n.nativeInitFailed);
        return;
      }

      final started = await _authCtrl.start(accountCount: validAccounts.length);
      if (mounted) {
        if (started) {
          setState(() {
            _statusText = i18n.authenticatedHeartbeat;
            _statusDetail = i18n.runningDetail;
          });
          _logReader.resume();
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
    final i18n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(i18n.appTitle),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: i18n.settingsTitle,
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
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              child: Column(
                children: [
                  // Status icon
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: _isRunning
                          ? colorScheme.primaryContainer
                          : colorScheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isRunning ? Icons.wifi : Icons.wifi_off,
                      size: 50,
                      color: _isRunning
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Status text
                  Text(
                    _statusText,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: _isRunning ? colorScheme.primary : colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _statusDetail,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // Start / Stop button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      icon: Icon(_isRunning ? Icons.stop : Icons.play_arrow),
                      label: Text(
                        _isRunning ? i18n.btnStopAuth : i18n.btnStartAuth,
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
                  const SizedBox(height: 20),

                  // Account summary
                  if (_config != null && _config!.accounts.isNotEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              i18n.configuredAccounts,
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
                                title: Text(
                                  a.username.isEmpty ? i18n.emptyAccount : a.username,
                                ),
                                subtitle: Text(
                                  '${i18n.fieldChannel}: ${a.channel}',
                                  style: theme.textTheme.bodySmall,
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),

                  // ======== Log Viewer Panel ========
                  LogViewer(reader: _logReader),
                  const SizedBox(height: 16),

                  // Version
                  Text(
                    i18n.versionInfo,
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
