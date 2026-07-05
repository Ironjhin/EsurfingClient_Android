import 'package:flutter/material.dart';

/// 应用国际化 — 支持简体中文和英文
class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('zh'),
  ];

  static const Locale fallbackLocale = Locale('en');

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  String get _lang => locale.languageCode;

  // ============================================================
  //  首页 (Home)
  // ============================================================
  String get appTitle => _t('ESurfing Client', '天翼认证客户端');

  String get initializing => _t('Initializing...', '初始化中...');
  String get ready => _t('Ready', '就绪');
  String get disabledHint => _t('Disabled', '已禁用');
  String get accountCount => _t('{n} account(s) configured', '已配置 {n} 个账号');
  String get configInSettings => _t('Please configure accounts in settings', '请在设置中配置账号');

  String get nativeInitFailed => _t('Native init failed', '底层初始化失败');
  String get authenticatedHeartbeat => _t('Authenticated — heartbeat active', '已认证 — 心跳运行中');
  String get runningDetail => _t('Running in background thread', '在后台线程中运行');
  String get startFailed => _t('Failed to start authentication', '启动认证失败');
  String get stopRequested => _t('Stopping...', '正在停止...');
  String get stopped => _t('Stopped', '已停止');
  String get errorPrefix => _t('Error', '错误');

  String get btnStartAuth => _t('Start Authentication', '开始认证');
  String get btnStopAuth => _t('Stop Authentication', '停止认证');

  // 配置缺失对话框
  String get configRequiredTitle => _t('Configuration Required', '需要配置');
  String get configRequiredBody => _t(
    'Please add at least one account with both username and password in Settings.',
    '请至少添加一个包含用户名和密码的账号。',
  );
  String get btnCancel => _t('Cancel', '取消');
  String get btnOpenSettings => _t('Open Settings', '打开设置');

  // 账号摘要
  String get configuredAccounts => _t('Configured Accounts', '已配置账号');
  String get emptyAccount => _t('(empty)', '(空)');

  // 底部版本
  String get versionInfo => _t(
    'ESurfing Client v1.0.0\nFlutter + NDK FFI',
    '天翼认证客户端 v1.0.0\nFlutter + NDK FFI',
  );

  // 日志面板
  String get logPanelTitle => _t('Run Log', '运行日志');
  String get logPanelEmpty => _t('(log file not available yet)', '（日志文件尚未就绪）');
  String get logPanelExpand => _t('Show Log', '显示日志');
  String get logPanelCollapse => _t('Hide Log', '隐藏日志');
  String get logPanelAutoScroll => _t('Auto-scroll', '自动滚动');
  String get logPanelPauseScroll => _t('Pause', '暂停');
  String get logPanelClear => _t('Clear', '清空');
  String get logPanelExport => _t('Export', '导出');
  String get logPanelFontDec => _t('Decrease font size', '调小字体');
  String get logPanelFontInc => _t('Increase font size', '调大字体');
  String get logPanelLinesSuffix => _t('lines', '行');

  // ============================================================
  //  设置页 (Settings)
  // ============================================================
  String get settingsTitle => _t('Settings', '设置');
  String get btnSave => _t('Save', '保存');
  String get configSavedSnack => _t('Configuration saved', '配置已保存');
  String get loadConfigFailed => _t('Failed to load config', '加载配置失败');

  String get enableService => _t('Enable Service', '启用服务');
  String get enableServiceSub => _t('Start authentication on app launch', '应用启动时自动开始认证');

  String get logLevel => _t('Log Level', '日志等级');

  String get accountsTitle => _t('Accounts', '账号');
  String get accountLabel => _t('Account {n}', '账号 {n}');
  String get btnAddAccount => _t('Add Account', '添加账号');
  String get btnRemoveAccount => _t('Remove account', '删除账号');

  // 表单字段
  String get fieldUsername => _t('Username', '用户名');
  String get fieldPassword => _t('Password', '密码');
  String get fieldChannel => _t('Channel', '通道');
  String get fieldMark => _t('Mark (Optional)', '标记值（可选）');
  String get hintMark => _t('Hex without 0x (e.g., 100)', '十六进制，无需 0x 前缀（如 100）');
  String get validateUsername => _t('Username is required', '请输入用户名');
  String get validatePassword => _t('Password is required', '请输入密码');

  // 通道选项
  String get channelPhone => _t('Phone (Mobile)', '手机端');
  String get channelPc => _t('PC (Desktop)', '电脑端');

  // 帮助信息
  String get channelOptionsHint => _t('Channel Options:', '通道选项：');
  String get channelPhoneDesc => _t('• phone - Mobile client (CCTP/android64_vpn/2093)', '• phone - 手机端 (CCTP/android64_vpn/2093)');
  String get channelPcDesc => _t('• pc - PC client (CCTP/Linux64/1003)', '• pc - 电脑端 (CCTP/Linux64/1003)');
  String get markHelpTitle => _t('Mark (SO_MARK):', '标记值 (SO_MARK)：');
  String get markHelp1 => _t('• Optional routing mark for multi-WAN setups', '• 多 WAN 环境下的可选路由标记');
  String get markHelp2 => _t('• Leave empty for auto-assignment (0x100, 0x200, ...)', '• 留空将自动分配 (0x100, 0x200, ...)');
  String get markHelp3 => _t('• Format: hex without 0x prefix (e.g., "100")', '• 格式：不带 0x 前缀的十六进制（如 "100"）');

  // 日志等级选项
  String logLevelLabel(int level) {
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

  String _t(String en, String zh) => _lang == 'zh' ? zh : en;
}

class AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppLocalizations.supportedLocales.any((l) => l.languageCode == locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) => Future.value(AppLocalizations(locale));

  @override
  bool shouldReload(AppLocalizationsDelegate old) => false;
}
