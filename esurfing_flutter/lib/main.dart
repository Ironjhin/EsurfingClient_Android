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
import 'src/widgets/liquid_glass_ui.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化配置管理器
  await ConfigManager.getInstance();
  await GlassPerformanceController.instance.initialize();

  // 锁定竖屏
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // ── 全局异常日志写入：防重入 + 降级兜底 ──
  bool isLoggingError = false;

  Future<void> appendErrorToLog(
      String tag, Object error, StackTrace stack) async {
    if (isLoggingError) return;
    isLoggingError = true;
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
      isLoggingError = false;
    }
  }

  // 捕获 Flutter 框架层异常并追加写入 run.log
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    appendErrorToLog(
        'FlutterError', details.exception, details.stack ?? StackTrace.empty);
  };

  // 捕获异步帧级未处理异常
  await runZonedGuarded<Future<void>>(() async {
    runApp(const ESurfingClientApp());
  }, (error, stack) {
    appendErrorToLog('UnhandledAsyncError', error, stack);
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
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      home: const HomePage(),
      routes: {
        '/settings': (context) => const SettingsPage(),
      },
      debugShowCheckedModeBanner: false,
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2D7DFF),
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: dark ? const Color(0xFF0A1726) : const Color(0xFFF3F8FF),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            dark ? const Color(0xE6293B51) : const Color(0xEFFFFFFF),
        contentTextStyle: TextStyle(color: scheme.onSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.42),
        space: 1,
      ),
    );
  }
}
