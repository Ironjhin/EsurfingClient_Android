import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  runApp(const ESurfingClientApp());
}

class ESurfingClientApp extends StatelessWidget {
  const ESurfingClientApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESurfing Client',
      // i18n
      localizationsDelegates: const [
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
