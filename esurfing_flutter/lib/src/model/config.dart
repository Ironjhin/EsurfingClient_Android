import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Configuration model
class ESurfingConfig {
  final bool enabled;
  final int logLevel;
  final List<AccountConfig> accounts;

  ESurfingConfig({
    required this.enabled,
    required this.logLevel,
    required this.accounts,
  });

  factory ESurfingConfig.fromJson(Map<String, dynamic> json) {
    return ESurfingConfig(
      enabled: json['enabled'] ?? false,
      logLevel: json['log_lv'] ?? 4,
      accounts: (json['accounts'] as List? ?? [])
          .map((e) => AccountConfig.fromJson(e))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'log_lv': logLevel,
      'accounts': accounts.map((e) => e.toJson()).toList(),
    };
  }

  static ESurfingConfig defaultConfig() {
    return ESurfingConfig(
      enabled: false,
      logLevel: 4,
      accounts: [
        AccountConfig(
          username: '',
          password: '',
          channel: 'phone',
          mark: '',
        ),
      ],
    );
  }
}

class AccountConfig {
  final String username;
  final String password;
  final String channel; // 'phone' or 'pc'
  final String mark;

  AccountConfig({
    required this.username,
    required this.password,
    required this.channel,
    required this.mark,
  });

  factory AccountConfig.fromJson(Map<String, dynamic> json) {
    return AccountConfig(
      username: json['username'] ?? '',
      password: json['password'] ?? '',
      channel: json['channel'] ?? 'phone',
      mark: json['mark'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'password': password,
      'channel': channel,
      'mark': mark,
    };
  }

  String get userAgent {
    return channel == 'pc'
        ? 'CCTP/Linux64/1003'
        : 'CCTP/android64_vpn/2093';
  }
}

/// Config manager using SharedPreferences
class ConfigManager {
  static const String _configKey = 'esurfing_config';
  static ConfigManager? _instance;
  late SharedPreferences _prefs;

  ConfigManager._();

  static Future<ConfigManager> getInstance() async {
    _instance ??= ConfigManager._();
    _instance!._prefs = await SharedPreferences.getInstance();
    return _instance!;
  }

  Future<ESurfingConfig> loadConfig() async {
    final jsonString = _prefs.getString(_configKey);
    if (jsonString == null || jsonString.isEmpty) {
      final defaultConfig = ESurfingConfig.defaultConfig();
      await saveConfig(defaultConfig);
      return defaultConfig;
    }
    return ESurfingConfig.fromJson(
      Map<String, dynamic>.from(jsonDecode(jsonString)),
    );
  }

  Future<void> saveConfig(ESurfingConfig config) async {
    final jsonString = jsonEncode(config.toJson());
    await _prefs.setString(_configKey, jsonString);
  }
}