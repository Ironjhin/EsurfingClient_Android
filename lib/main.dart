import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'src/model/config.dart';
import 'src/ui/home_page.dart';
import 'src/ui/settings_page.dart';
import 'src/i18n/app_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化配置管理器
  await ConfigManager.getInstance();

  // 锁定竖屏
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // ── 全局异常日志写入：防重入 + 降级兜底 ──
  bool _isLoggingError = false;

  Future<void> _appendErrorToLog(String tag, Object error, StackTrace stack) async {
    if (_isLoggingError) return;
    _isLoggingError = true;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final logFile = File('${dir.path}/run.log');
      final time = DateTime.now().toIso8601String();
      final msg = '[$time] $tag: $error\n$stack\n\n';
      await logFile.writeAsString(msg, mode: FileMode.append);
    } catch (_) {
      // 沙盒路径未就绪或文件写入失败 → 降级到系统控制台
      debugPrint('[$tag] $error\n$stack');
    } finally {
      _isLoggingError = false;
    }
  }

  // 捕获 Flutter 框架层异常并追加写入 run.log
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    _appendErrorToLog('FlutterError', details.exception, details.stack ?? StackTrace.empty);
  };

  // 捕获异步帧级未处理异常
  await runZonedGuarded<Future<void>>(() async {
    runApp(const ESurfingClientApp());
  }, (error, stack) {
    _appendErrorToLog('UnhandledAsyncError', error, stack);
  });
}

class ESurfingClientApp extends StatelessWidget {
  const ESurfingClientApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESurfing Client',
      // i18n
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        AppLocalizationsDelegate(),
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      localeResolutionCallback: (locale, supported) {
        if (locale == null) return supported.first;
        for (final l in supported) {
          if (l.languageCode == locale.languageCode) return l;
        }
        return supported.first;
      },
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF1565C0),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF1565C0),
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      home: const HomePage(),
      routes: {
        '/settings': (context) => const SettingsPage(),
      },
      debugShowCheckedModeBanner: false,
    );
  }
}
