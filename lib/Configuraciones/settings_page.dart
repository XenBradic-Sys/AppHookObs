//lib/Configuraciones/settings_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'settings_controller.dart';
import 'app_localizations.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final lang = settings.language;

    return ListView(
      children: [
        ListTile(
          title: Text(AppLocalizations.t('language', lang)),
          subtitle: Text(
            AppLocalizations.t(
              settings.language == AppLanguage.es ? 'spanish' : 'english',
              lang,
            ),
          ),
          trailing: DropdownButton<AppLanguage>(
            value: settings.language,
            onChanged: (AppLanguage? value) {
              if (value != null) settings.setLanguage(value);
            },
            items: [
              DropdownMenuItem(
                value: AppLanguage.es,
                child: Row(
                  children: [
                    Text('MX', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(width: 8),
                    Image.asset('assets/mx_flag.png', width: 24, height: 24),
                    SizedBox(width: 8),
                    Text(AppLocalizations.t('spanish', lang)),
                  ],
                ),
              ),
              DropdownMenuItem(
                value: AppLanguage.en,
                child: Row(
                  children: [
                    Text('US', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(width: 8),
                    Image.asset('assets/us_flag.png', width: 24, height: 24),
                    SizedBox(width: 8),
                    Text(AppLocalizations.t('english', lang)),
                  ],
                ),
              ),
            ],
          ),
        ),
        ListTile(
          title: Text(AppLocalizations.t('theme', lang)),
          subtitle: Text(
            AppLocalizations.t(
              settings.theme == AppTheme.light ? 'light' : 'Dark',
              lang,
            ),
          ),
          trailing: DropdownButton<AppTheme>(
            value: settings.theme,
            onChanged: (AppTheme? value) {
              if (value != null) settings.setTheme(value);
            },
            items: [
              DropdownMenuItem(
                value: AppTheme.light,
                child: Row(
                  children: [
                    Icon(Icons.wb_sunny, color: Colors.orange),
                    SizedBox(width: 8),
                    Text(AppLocalizations.t('light', lang)),
                  ],
                ),
              ),
              DropdownMenuItem(
                value: AppTheme.blueDark,
                child: Row(
                  children: [
                    Icon(Icons.nights_stay, color: Colors.indigo),
                    SizedBox(width: 8),
                    Text(AppLocalizations.t('Dark', lang)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
