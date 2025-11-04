//main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'Configuraciones/splash_screen.dart';
import 'InicioSesión/login_page.dart';
import 'Configuraciones/settings_controller.dart';

const Color mainColor = Color(0xFFF20A32);
const Color backgroundColor = Color(0xFFF5F5F5);
const Color blueColor = Color(0xFF29B6F6);

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => SettingsController(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  ThemeData _buildTheme(SettingsController settings) {
    if (settings.theme == AppTheme.blueDark) {
      return ThemeData(
        brightness: Brightness.dark,
        primaryColor: blueColor,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.dark(
          primary: blueColor,
          secondary: blueColor,
          background: Colors.black,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          foregroundColor: blueColor,
          iconTheme: IconThemeData(color: blueColor),
        ),
        iconTheme: const IconThemeData(color: blueColor),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: blueColor,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.black,
          indicatorColor: blueColor.withOpacity(0.1),
          iconTheme: MaterialStateProperty.all(
            const IconThemeData(color: blueColor),
          ),
          labelTextStyle: MaterialStateProperty.all(
            const TextStyle(color: blueColor),
          ),
        ),
      );
    } else {
      return ThemeData(
        brightness: Brightness.light,
        primaryColor: mainColor,
        scaffoldBackgroundColor: backgroundColor,
        colorScheme: ColorScheme.light(
          primary: mainColor,
          secondary: mainColor,
          background: backgroundColor,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: backgroundColor,
          foregroundColor: mainColor,
          iconTheme: IconThemeData(color: mainColor),
        ),
        iconTheme: const IconThemeData(color: mainColor),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: mainColor,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: backgroundColor,
          indicatorColor: mainColor.withOpacity(0.1),
          iconTheme: MaterialStateProperty.all(
            const IconThemeData(color: mainColor),
          ),
          labelTextStyle: MaterialStateProperty.all(
            const TextStyle(color: mainColor),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    return MaterialApp(
      title: 'HOOK OBS',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(settings),
      home: SplashScreen(nextPage: LoginPage()),
    );
  }
}
