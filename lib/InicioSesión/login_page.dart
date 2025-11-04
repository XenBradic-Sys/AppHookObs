// lib/InicioSesión/login_page.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../Inicio/home_page.dart';
import 'package:provider/provider.dart';
import '../Configuraciones/settings_controller.dart';
import '../Configuraciones/app_localizations.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool isLoading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _tryAutoLogin();
  }

  Future<void> _tryAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString('email');
    final savedPassword = prefs.getString('password');
    if (savedEmail != null && savedPassword != null) {
      emailController.text = savedEmail;
      passwordController.text = savedPassword;
      await login(auto: true);
    }
  }

  Future<bool> _hasConnection() async {
    final result = await Connectivity().checkConnectivity();
    return result != ConnectivityResult.none;
  }

  String? _extractIdPersonal(Map<String, dynamic> p) {
    for (final k in const [
      'r_id_personal_in_line',
      'id_personal_in_line',
      'r_id_personal',
      'id_personal',
      'r_personal_id',
      'personal_id',
      'r_id_user',
      'id_user',
    ]) {
      final v = p[k];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString();
    }
    return null;
  }

  Future<void> login({bool auto = false}) async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    final settings = context.read<SettingsController>();
    final lang = settings.language;

    if (email.isEmpty || password.isEmpty) {
      _showError(
        lang == AppLanguage.es
            ? '¡Ups! Faltan datos. Por favor, completa todos los campos.'
            : 'Oops! Missing data. Please fill in all fields.',
      );
      return;
    }

    if (!await _hasConnection()) {
      _showError(
        lang == AppLanguage.es
            ? 'Sin conexión a internet. Revisa tu conexión e intenta de nuevo.'
            : 'No internet connection. Please check your connection and try again.',
        showRetry: true,
      );
      return;
    }

    setState(() => isLoading = true);

    const apiUrl = 'https://api-ticket-6wly.onrender.com/login-supabase-to-app'; 
    const apiKey = 'yacjDEIxyrZPgAZMh83yUAiP86Y256QNkyhuix5qSgP7LnTQ4S';

    try {
      final response = await http
          .post(
            Uri.parse(apiUrl),
            headers: {'Content-Type': 'application/json', 'x-api-key': apiKey},
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(const Duration(seconds: 10));

      final responseData = jsonDecode(response.body);
      debugPrint('Respuesta completa del API: $responseData');

      if (response.statusCode == 200 && responseData['success'] == true) {
        final List<dynamic> pis =
            (responseData['personalInfo'] as List?) ?? const [];
        if (pis.isEmpty) {
          _showError(
            lang == AppLanguage.es
                ? 'No pudimos encontrar tus datos personales en el sistema.'
                : 'We could not find your personal information in the system.',
          );
          return;
        }

        final Map<String, dynamic> personal = Map<String, dynamic>.from(
          pis.first as Map,
        );
        final idPersonal = _extractIdPersonal(personal);

        if (idPersonal != null) {
          personal['id_personal_in_line'] = idPersonal;
          responseData['personalInfo'][0] = personal;

          // Guardar datos en SharedPreferences
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('email', email);
          await prefs.setString('password', password);
          await prefs.setString('id_personal_in_line', idPersonal);

          debugPrint('Datos guardados en SharedPreferences: $idPersonal');
        }

        // Navegar al HomePage
        if (mounted) {
          await Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => HomePage(userInfo: responseData),
              settings: const RouteSettings(name: '/home'),
            ),
          );
        }
      } else {
        final apiMessage = responseData['message'] ?? '';
        _showError(
          lang == AppLanguage.es
              ? (apiMessage.isNotEmpty
                    ? apiMessage
                    : 'Tu usuario o contraseña no coinciden. Inténtalo de nuevo.')
              : (apiMessage.isNotEmpty
                    ? apiMessage
                    : 'Incorrect user or password. Please try again.'),
        );
      }
    } on TimeoutException catch (_) {
      _showError(
        lang == AppLanguage.es
            ? 'El servidor tardó mucho en responder.'
            : 'The server took too long to respond.',
        showRetry: true,
      );
    } on http.ClientException catch (e) {
      _showError(
        (lang == AppLanguage.es
                ? 'Problemas de conexión: '
                : 'Connection problems: ') +
            e.message,
        showRetry: true,
      );
    } catch (e) {
      _showError(
        (lang == AppLanguage.es
                ? 'Algo salió mal: '
                : 'Something went wrong: ') +
            e.toString(),
        showRetry: true,
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showError(String message, {bool showRetry = false}) {
    if (!mounted) return;
    final settings = context.read<SettingsController>();
    final mainColor = settings.theme == AppTheme.blueDark
        ? const Color(0xFF29B6F6)
        : const Color(0xFFF20A32);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: mainColor,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        action: showRetry
            ? SnackBarAction(
                label: settings.language == AppLanguage.es
                    ? 'Reintentar'
                    : 'Retry',
                textColor: Colors.white,
                onPressed: () {
                  login();
                },
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final mainColor = settings.theme == AppTheme.blueDark
        ? const Color(0xFF29B6F6)
        : const Color(0xFFF20A32);
    final lang = settings.language;
    final isDark = settings.theme == AppTheme.blueDark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 60.0),
              SizedBox(
                height: 150,
                width: 150,
                child: isDark
                    ? ColorFiltered(
                        colorFilter: const ColorFilter.mode(
                          Colors.white,
                          BlendMode.srcIn,
                        ),
                        child: Image.asset(
                          'assets/logoOBS.png',
                          fit: BoxFit.contain,
                        ),
                      )
                    : Image.asset('assets/logoOBS.png', fit: BoxFit.contain),
              ),
              const SizedBox(height: 30.0),
              Text(
                lang == AppLanguage.es
                    ? 'Bienvenido HOOK OBS'
                    : 'Welcome to HOOK OBS',
                style: TextStyle(
                  fontSize: 28.0,
                  fontWeight: FontWeight.bold,
                  color: mainColor,
                ),
              ),
              const SizedBox(height: 10.0),
              Text(
                lang == AppLanguage.es
                    ? 'Inicia sesión para continuar'
                    : 'Sign in to continue',
                style: TextStyle(
                  fontSize: 16.0,
                  color: isDark ? Colors.white : Colors.grey[600],
                ),
              ),
              const SizedBox(height: 40.0),
              TextFormField(
                controller: emailController,
                decoration: InputDecoration(
                  labelText: lang == AppLanguage.es
                      ? 'Correo electrónico'
                      : 'Email',
                  labelStyle: TextStyle(
                    color: isDark ? Colors.white70 : Colors.grey[600],
                  ),
                  prefixIcon: Icon(Icons.email, color: mainColor),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10.0),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10.0),
                    borderSide: BorderSide(color: mainColor),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 15.0,
                    horizontal: 15.0,
                  ),
                ),
                keyboardType: TextInputType.emailAddress,
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
              ),
              const SizedBox(height: 20.0),
              TextFormField(
                controller: passwordController,
                decoration: InputDecoration(
                  labelText: lang == AppLanguage.es ? 'Contraseña' : 'Password',
                  labelStyle: TextStyle(
                    color: isDark ? Colors.white70 : Colors.grey[600],
                  ),
                  prefixIcon: Icon(Icons.lock, color: mainColor),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility
                          : Icons.visibility_off,
                      color: mainColor,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10.0),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10.0),
                    borderSide: BorderSide(color: mainColor),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 15.0,
                    horizontal: 15.0,
                  ),
                ),
                obscureText: _obscurePassword,
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
              ),
              const SizedBox(height: 30.0),
              SizedBox(
                width: double.infinity,
                height: 50.0,
                child: ElevatedButton(
                  onPressed: isLoading ? null : () => login(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: mainColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                    elevation: 5.0,
                  ),
                  child: isLoading
                      ? const SizedBox(
                          width: 20.0,
                          height: 20.0,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.0,
                          ),
                        )
                      : Text(
                          lang == AppLanguage.es ? 'Iniciar sesión' : 'Sign in',
                          style: const TextStyle(
                            fontSize: 18.0,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 20.0),
              TextButton(
                onPressed: () {},
                child: Text(
                  lang == AppLanguage.es
                      ? '¿Olvidaste tu contraseña?'
                      : 'Forgot your password?',
                  style: TextStyle(color: mainColor),
                ),
              ),
              const SizedBox(height: 20.0),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }
}
