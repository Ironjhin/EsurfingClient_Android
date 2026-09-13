import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../model/config.dart';
import '../i18n/app_localizations.dart';
import '../widgets/liquid_glass_ui.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  ESurfingConfig? _config;
  bool _isLoading = true;
  final List<GlobalKey<FormState>> _formKeys = [];
  final List<TextEditingController> _usernameControllers = [];
  final List<TextEditingController> _passwordControllers = [];
  final List<TextEditingController> _markControllers = [];
  final List<String> _channelValues = [];

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    for (final c in _usernameControllers) {
      c.dispose();
    }
    for (final c in _passwordControllers) {
      c.dispose();
    }
    for (final c in _markControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final configManager = await ConfigManager.getInstance();
    final config = await configManager.loadConfig();
    if (mounted) {
      setState(() {
        _config = config;
        _isLoading = false;
        _initializeControllers(config);
      });
    }
  }

  void _initializeControllers(ESurfingConfig config) {
    _formKeys.clear();
    _usernameControllers.clear();
    _passwordControllers.clear();
    _markControllers.clear();
    _channelValues.clear();

    for (final account in config.accounts) {
      _formKeys.add(GlobalKey<FormState>());
      _usernameControllers.add(TextEditingController(text: account.username));
      _passwordControllers.add(TextEditingController(text: account.password));
      _markControllers.add(TextEditingController(text: account.mark));
      _channelValues.add(AccountConfig.normalizeChannel(account.channel));
    }
  }

  Future<void> _saveConfig() async {
    if (_config == null) return;
    final i18n = AppLocalizations.of(context);

    final accounts = <AccountConfig>[];
    for (int i = 0; i < _usernameControllers.length; i++) {
      if (_formKeys[i].currentState?.validate() ?? false) {
        final existingTw = (i < _config!.accounts.length)
            ? _config!.accounts[i].timeWindows
            : <TimeWindowConfig>[];
        accounts.add(AccountConfig(
          username: _usernameControllers[i].text.trim(),
          password: _passwordControllers[i].text,
          channel: AccountConfig.normalizeChannel(_channelValues[i]),
          mark: _markControllers[i].text.trim(),
          timeWindows: existingTw,
        ));
      }
    }

    final newConfig = ESurfingConfig(
      enabled: _config!.enabled && accounts.isNotEmpty,
      logLevel: _config!.logLevel,
      accounts: accounts,
    );

    final configManager = await ConfigManager.getInstance();
    await configManager.saveConfig(newConfig);

    if (mounted) {
      setState(() => _config = newConfig);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(i18n.configSavedSnack)),
      );
    }
  }

  void _addAccount() {
    setState(() {
      _formKeys.add(GlobalKey<FormState>());
      _usernameControllers.add(TextEditingController());
      _passwordControllers.add(TextEditingController());
      _markControllers.add(TextEditingController());
      _channelValues.add('android');
    });
  }

  void _removeAccount(int index) {
    if (_formKeys.length <= 1) return;
    setState(() {
      _formKeys.removeAt(index);
      _usernameControllers[index].dispose();
      _usernameControllers.removeAt(index);
      _passwordControllers[index].dispose();
      _passwordControllers.removeAt(index);
      _markControllers[index].dispose();
      _markControllers.removeAt(index);
      _channelValues.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlassScene(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: GlassTopBar(
                  title: i18n.settingsTitle,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded),
                    tooltip:
                        MaterialLocalizations.of(context).backButtonTooltip,
                    onPressed: () => Navigator.maybePop(context),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.check_rounded),
                    onPressed: _isLoading ? null : _saveConfig,
                    tooltip: i18n.btnSave,
                  ),
                ),
              ),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _config == null
                        ? Center(child: Text(i18n.loadConfigFailed))
                        : _buildSettingsList(context, i18n, theme),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsList(
    BuildContext context,
    AppLocalizations i18n,
    ThemeData theme,
  ) {
    final glassController = GlassPerformanceController.instance;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
      children: [
        GlassSurface(
          radius: 26,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            children: [
              SwitchListTile(
                title: Text(i18n.enableService),
                subtitle: Text(i18n.enableServiceSub),
                value: _config!.enabled,
                onChanged: (value) {
                  setState(() {
                    _config = ESurfingConfig(
                      enabled: value,
                      logLevel: _config!.logLevel,
                      accounts: _config!.accounts,
                    );
                  });
                },
              ),
              const Divider(indent: 12, endIndent: 12),
              ListTile(
                title: Text(i18n.logLevel),
                subtitle: Text(i18n.logLevelLabel(_config!.logLevel)),
                trailing: DropdownButton<int>(
                  value: _config!.logLevel,
                  underline: const SizedBox.shrink(),
                  borderRadius: BorderRadius.circular(18),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('OFF')),
                    DropdownMenuItem(value: 1, child: Text('FATAL')),
                    DropdownMenuItem(value: 2, child: Text('ERROR')),
                    DropdownMenuItem(value: 3, child: Text('WARN')),
                    DropdownMenuItem(value: 4, child: Text('INFO')),
                    DropdownMenuItem(value: 5, child: Text('DEBUG')),
                    DropdownMenuItem(value: 6, child: Text('VERBOSE')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _config = ESurfingConfig(
                          enabled: _config!.enabled,
                          logLevel: value,
                          accounts: _config!.accounts,
                        );
                      });
                    }
                  },
                ),
              ),
              const Divider(indent: 12, endIndent: 12),
              AnimatedBuilder(
                animation: glassController,
                builder: (context, _) => ListTile(
                  leading: const Icon(Icons.auto_awesome),
                  title: Text(i18n.glassQuality),
                  subtitle: Text(i18n.glassQualityHint),
                  trailing: DropdownButton<GlassQualityMode>(
                    value: glassController.mode,
                    underline: const SizedBox.shrink(),
                    borderRadius: BorderRadius.circular(18),
                    items: [
                      DropdownMenuItem(
                        value: GlassQualityMode.automatic,
                        child: Text(i18n.glassQualityAuto),
                      ),
                      DropdownMenuItem(
                        value: GlassQualityMode.liquid,
                        child: Text(i18n.glassQualityLiquid),
                      ),
                      DropdownMenuItem(
                        value: GlassQualityMode.efficient,
                        child: Text(i18n.glassQualityEfficient),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) glassController.setMode(value);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            i18n.accountsTitle,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 10),
        ..._formKeys.asMap().entries.map(
              (entry) => _buildAccountCard(entry.key, i18n),
            ),
        const SizedBox(height: 2),
        GlassActionButton(
          icon: Icons.add_rounded,
          label: i18n.btnAddAccount,
          onPressed: _addAccount,
        ),
        const SizedBox(height: 24),
        GlassSurface(
          tint: theme.colorScheme.secondary,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                i18n.channelOptionsHint,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(i18n.channelAndroidDesc),
              Text(i18n.channelIosDesc),
              Text(i18n.channelMacosDesc),
              Text(i18n.channelLinuxDesc),
              Text(i18n.channelWindowsDesc),
              const SizedBox(height: 16),
              Text(
                i18n.markHelpTitle,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(i18n.markHelp1),
              Text(i18n.markHelp2),
              Text(i18n.markHelp3),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAccountCard(int index, AppLocalizations i18n) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GlassSurface(
        radius: 26,
        child: Form(
          key: _formKeys[index],
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 220),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Text('${index + 1}'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        i18n.accountLabel.replaceAll('{n}', '${index + 1}'),
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (_formKeys.length > 1)
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _removeAccount(index),
                        tooltip: i18n.btnRemoveAccount,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _usernameControllers[index],
                  decoration: glassInputDecoration(
                    context,
                    label: i18n.fieldUsername,
                    icon: Icons.person_outline_rounded,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return i18n.validateUsername;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordControllers[index],
                  decoration: glassInputDecoration(
                    context,
                    label: i18n.fieldPassword,
                    icon: Icons.lock_outline_rounded,
                  ),
                  obscureText: true,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return i18n.validatePassword;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: AccountConfig.normalizeChannel(_channelValues[index]),
                  decoration: glassInputDecoration(
                    context,
                    label: i18n.fieldChannel,
                    icon: Icons.router_outlined,
                  ),
                  items: [
                    DropdownMenuItem(
                        value: 'android', child: Text(i18n.channelAndroid)),
                    DropdownMenuItem(
                        value: 'ios', child: Text(i18n.channelIos)),
                    DropdownMenuItem(
                        value: 'macos', child: Text(i18n.channelMacos)),
                    DropdownMenuItem(
                        value: 'linux', child: Text(i18n.channelLinux)),
                    DropdownMenuItem(
                        value: 'windows', child: Text(i18n.channelWindows)),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _channelValues[index] = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _markControllers[index],
                  decoration: glassInputDecoration(
                    context,
                    label: i18n.fieldMark,
                    icon: Icons.tag_rounded,
                    hint: i18n.hintMark,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
