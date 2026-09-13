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
      enabled: json['enabled'] as bool? ?? false,
      logLevel: json['log_lv'] as int? ?? 4,
      accounts: (json['accounts'] as List<dynamic>? ?? [])
          .map((e) => AccountConfig.fromJson(e as Map<String, dynamic>))
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
          channel: 'android',
          mark: '',
        ),
      ],
    );
  }
}

/// Time window config for schedule-based authentication
class TimeWindowConfig {
  final String start;
  final String end;

  TimeWindowConfig({
    required this.start,
    required this.end,
  });

  factory TimeWindowConfig.fromJson(Map<String, dynamic> json) {
    return TimeWindowConfig(
      start: json['start'] as String? ?? '',
      end: json['end'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'start': start,
      'end': end,
    };
  }
}

class AccountConfig {
  final String username;
  final String password;
  final String channel; // 'android', 'ios', 'macos', 'linux', 'windows' (also accepts 'phone'/'pc')
  final String mark;
  final List<TimeWindowConfig> timeWindows;

  AccountConfig({
    required this.username,
    required this.password,
    required this.channel,
    required this.mark,
    this.timeWindows = const [],
  });

  static String normalizeChannel(String? raw) {
    final c = (raw ?? 'android').trim().toLowerCase();
    if (c == 'phone') return 'android';
    if (c == 'pc') return 'linux';
    if (['android', 'ios', 'macos', 'linux', 'windows'].contains(c)) {
      return c;
    }
    return 'android';
  }

  factory AccountConfig.fromJson(Map<String, dynamic> json) {
    final rawChannel = json['channel'] as String? ?? 'android';
    final twList = (json['time_windows'] as List<dynamic>? ?? [])
        .map((e) => TimeWindowConfig.fromJson(e as Map<String, dynamic>))
        .toList();
    return AccountConfig(
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      channel: normalizeChannel(rawChannel),
      mark: json['mark'] as String? ?? '',
      timeWindows: twList,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'username': username,
      'password': password,
      'channel': channel,
      'mark': mark,
    };
    if (timeWindows.isNotEmpty) {
      map['time_windows'] = timeWindows.map((e) => e.toJson()).toList();
    }
    return map;
  }

  String get userAgent {
    switch (normalizeChannel(channel)) {
      case 'windows':
        return 'CCTP/WinSVR5/1068';
      case 'linux':
        return 'CCTP/Linux64/1003';
      case 'ios':
        return 'CCTP/iOSdy/4023';
      case 'macos':
        return 'CCTP/macdy/5019';
      case 'android':
      default:
        return 'CCTP/android11_64/2104';
    }
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
      jsonDecode(jsonString) as Map<String, dynamic>,
    );
  }

  Future<void> saveConfig(ESurfingConfig config) async {
    final jsonString = jsonEncode(config.toJson());
    await _prefs.setString(_configKey, jsonString);
  }
}