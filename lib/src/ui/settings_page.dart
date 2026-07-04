import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../model/config.dart';
import '../i18n/app_localizations.dart';

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
    for (final c in _usernameControllers) c.dispose();
    for (final c in _passwordControllers) c.dispose();
    for (final c in _markControllers) c.dispose();
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
      _channelValues.add(account.channel);
    }
  }

  Future<void> _saveConfig() async {
    if (_config == null) return;
    final i18n = AppLocalizations.of(context);

    final accounts = <AccountConfig>[];
    for (int i = 0; i < _config!.accounts.length; i++) {
      if (_formKeys[i].currentState?.validate() ?? false) {
        accounts.add(AccountConfig(
          username: _usernameControllers[i].text.trim(),
          password: _passwordControllers[i].text,
          channel: _channelValues[i],
          mark: _markControllers[i].text.trim(),
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
      _channelValues.add('phone');
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

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(i18n.settingsTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(i18n.settingsTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveConfig,
            tooltip: i18n.btnSave,
          ),
        ],
      ),
      body: _config == null
          ? Center(child: Text(i18n.loadConfigFailed))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Global Enabled Switch
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
                const Divider(),

                // Log Level
                ListTile(
                  title: Text(i18n.logLevel),
                  subtitle: Text(i18n.logLevelLabel(_config!.logLevel)),
                  trailing: DropdownButton<int>(
                    value: _config!.logLevel,
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
                const Divider(),

                // Accounts
                Text(i18n.accountsTitle,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ..._formKeys.asMap().entries.map((entry) {
                  final i = entry.key;
                  return _buildAccountCard(i, i18n);
                }),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text(i18n.btnAddAccount),
                  onPressed: _addAccount,
                ),
                const SizedBox(height: 24),

                // Info
                Card(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(i18n.channelOptionsHint,
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text(i18n.channelPhoneDesc),
                        Text(i18n.channelPcDesc),
                        const SizedBox(height: 16),
                        Text(i18n.markHelpTitle,
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text(i18n.markHelp1),
                        Text(i18n.markHelp2),
                        Text(i18n.markHelp3),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildAccountCard(int index, AppLocalizations i18n) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKeys[index],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
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
                decoration: InputDecoration(
                  labelText: i18n.fieldUsername,
                  prefixIcon: const Icon(Icons.person),
                  border: const OutlineInputBorder(),
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
                decoration: InputDecoration(
                  labelText: i18n.fieldPassword,
                  prefixIcon: const Icon(Icons.lock),
                  border: const OutlineInputBorder(),
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
                value: _channelValues[index],
                decoration: InputDecoration(
                  labelText: i18n.fieldChannel,
                  prefixIcon: const Icon(Icons.router),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(value: 'phone', child: Text(i18n.channelPhone)),
                  DropdownMenuItem(value: 'pc', child: Text(i18n.channelPc)),
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
                decoration: InputDecoration(
                  labelText: i18n.fieldMark,
                  prefixIcon: const Icon(Icons.tag),
                  border: const OutlineInputBorder(),
                  hintText: i18n.hintMark,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
