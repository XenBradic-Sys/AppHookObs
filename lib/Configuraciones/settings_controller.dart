// lib/Cnfiguraciones/settings_controller.dart
import 'package:flutter/material.dart';

enum AppTheme { light, blueDark }
enum AppLanguage { es, en }

class SettingsController extends ChangeNotifier {
  AppTheme _theme = AppTheme.light;
  AppLanguage _language = AppLanguage.es;

  AppTheme get theme => _theme;
  AppLanguage get language => _language;

  ThemeMode get themeMode =>
      _theme == AppTheme.light ? ThemeMode.light : ThemeMode.dark;
  Locale get locale =>
      _language == AppLanguage.es ? const Locale('es') : const Locale('en');

  ThemeData get themeData =>
      _theme == AppTheme.light ? _lightTheme : _blueDarkTheme;

  void setTheme(AppTheme theme) {
    if (_theme != theme) {
      _theme = theme;
      notifyListeners();
    }
  }

  void setLanguage(AppLanguage lang) {
    if (_language != lang) {
      _language = lang;
      notifyListeners();
    }
  }
}

final ThemeData _lightTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF1565C0),
    brightness: Brightness.light,
  ),
);

final ThemeData _blueDarkTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF0D47A1),
    brightness: Brightness.dark,
  ),
);
