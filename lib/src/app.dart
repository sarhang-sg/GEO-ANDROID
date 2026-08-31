import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:geo_android/src/app_config.dart';
import 'package:geo_android/src/nav_kurd_page.dart';

final class NavKurdApp extends StatelessWidget {
  const NavKurdApp({required this.initialDeepLink, super.key});

  final String? initialDeepLink;

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF061225);
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const <Locale>[
        Locale('ku'),
        Locale('en'),
        Locale('ar'),
      ],
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2F8CFF),
          brightness: Brightness.dark,
          surface: background,
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: Color(0xFF0B2342),
          contentTextStyle: TextStyle(color: Colors.white),
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: NavKurdPage(initialDeepLink: initialDeepLink),
    );
  }
}
