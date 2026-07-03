import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../model/config.dart';

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
      setState(() {
        _config = newConfig;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuration saved')),
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
  void dispose() {
    for (final c in _usernameControllers) c.dispose();
    for (final c in _passwordControllers) c.dispose();
    for (final c in _markControllers) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveConfig,
            tooltip: 'Save',
          ),
        ],
      ),
      body: _config == null
          ? const Center(child: Text('Failed to load config'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Global Enabled Switch
                SwitchListTile(
                  title: const Text('Enable Service'),
                  subtitle: const Text('Start authentication on app launch'),
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
                  title: const Text('Log Level'),
                  subtitle: Text(_logLevelLabel(_config!.logLevel)),
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
                const Text('Accounts', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ..._formKeys.asMap().entries.map((entry) {
                  final i = entry.key;
                  return _buildAccountCard(i);
                }),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add Account'),
                  onPressed: _addAccount,
                ),
                const SizedBox(height: 24),

                // Info
                Card(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Channel Options:', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        const Text('• phone - Mobile client (CCTP/android64_vpn/2093)'),
                        const Text('• pc - PC client (CCTP/Linux64/1003)'),
                        const SizedBox(height: 16),
                        const Text('Mark (SO_MARK):', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        const Text('• Optional routing mark for multi-WAN setups'),
                        const Text('• Leave empty for auto-assignment (0x100, 0x200, ...)'),
                        const Text('• Format: hex without 0x prefix (e.g., "100")'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildAccountCard(int index) {
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
                      'Account ${index + 1}',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (_formKeys.length > 1)
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _removeAccount(index),
                      tooltip: 'Remove account',
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _usernameControllers[index],
                decoration: const InputDecoration(
                  labelText: 'Username',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Username is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordControllers[index],
                decoration: const InputDecoration(
                  labelText: 'Password',
                  prefixIcon: Icon(Icons.lock),
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Password is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _channelValues[index],
                decoration: const InputDecoration(
                  labelText: 'Channel',
                  prefixIcon: Icon(Icons.router),
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'phone', child: Text('Phone (Mobile)')),
                  DropdownMenuItem(value: 'pc', child: Text('PC (Desktop)')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _channelValues[index] = value;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _markControllers[index],
                decoration: const InputDecoration(
                  labelText: 'Mark (Optional)',
                  prefixIcon: Icon(Icons.tag),
                  border: OutlineInputBorder(),
                  hintText: 'Hex without 0x (e.g., 100)',
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

  String _logLevelLabel(int level) {
    switch (level) {
      case 0: return 'OFF';
      case 1: return 'FATAL';
      case 2: return 'ERROR';
      case 3: return 'WARN';
      case 4: return 'INFO';
      case 5: return 'DEBUG';
      case 6: return 'VERBOSE';
      default: return 'UNKNOWN';
    }
  }
}