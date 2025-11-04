//lib/Pagina/website_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../Configuraciones/settings_controller.dart';
import '../Configuraciones/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

class WebsitePage extends StatelessWidget {
  const WebsitePage({super.key});

  // Método para abrir la URL oficial
  Future<void> _launchSite(BuildContext context) async {
    final url = Uri.parse('https://hookmexico.com/');
    try {
      // Intenta abrir el enlace directamente
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      // Si falla, muestra el snackbar
      final lang = context.read<SettingsController>().language;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(lang == AppLanguage.es
              ? 'No se pudo abrir el sitio web'
              : 'Could not open website'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsController>().language;
    final theme = Theme.of(context);

    // Usa un Scaffold para mostrar el snackbar correctamente
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 40.0),
          child: Card(
            elevation: 6,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.language, color: theme.primaryColor, size: 60),
                  const SizedBox(height: 15),
                  Text(
                    lang == AppLanguage.es
                        ? 'Versión de la App:'
                        : 'App Version:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: theme.primaryColor),
                  ),
                  Text('1.0.0+1', style: TextStyle(fontSize: 16)),
                  const SizedBox(height: 10),
                  Text(
                    lang == AppLanguage.es
                        ? 'Autor:'
                        : 'Author:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: theme.primaryColor),
                  ),
                  Text('Hook México', style: TextStyle(fontSize: 16)),
                  const SizedBox(height: 10),
                  Text(
                    lang == AppLanguage.es
                        ? '© 2025 Todos los derechos reservados'
                        : '© 2025 All rights reserved',
                    style: TextStyle(fontStyle: FontStyle.italic, fontSize: 15),
                  ),
                  const SizedBox(height: 28),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 32),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                    ),
                    icon: const Icon(Icons.language, color: Colors.white, size: 32),
                    label: Text(
                      lang == AppLanguage.es ? 'Abrir sitio web oficial' : 'Open Official Website',
                      style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () => _launchSite(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}