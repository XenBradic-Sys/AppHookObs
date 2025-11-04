// lib/Inicio/home_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../Asientos/seat_selection_page.dart'; // Usa SeatSelectionInline
import '../Configuraciones/app_localizations.dart';
import '../Configuraciones/settings_controller.dart';
import '../Configuraciones/settings_page.dart';
import '../InicioSesión/login_page.dart';
import '../Pagina/website_page.dart';
import '../Viaje/configuracion_viaje_page.dart';

const String kViajeCredKey = 'viajeCredencial';
const String kCiudadActualKey = 'ciudadActual';

class HomePage extends StatefulWidget {
  final Map<String, dynamic> userInfo;
  const HomePage({super.key, required this.userInfo});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // en _HomePageState
  bool _origenCollapsed = false;
  bool _destinoCollapsed = false;

  String? _nombreTerminalById(String? id) {
    if (id == null) return null;
    final m = _pasosActuales.firstWhere(
      (p) => p['r_id_step_on_route'] == id,
      orElse: () => {},
    );
    if (m.isEmpty) return null;
    return '${m['r_terminal_name'] ?? ''} • ${m['r_city'] ?? ''}';
  }

  final ScrollController _scrollCtrl = ScrollController();

  int _currentIndex = 0;
  Map<String, dynamic> get personal => widget.userInfo['personalInfo'][0];

  // ← fuerza reconstrucciones “en limpio” del selector de asientos
  int _seatPickerEpoch = 0;

  // Getter robusto para id_personal_in_line
  String? get idPersonalInLine {
    final p = personal;
    for (final k in const [
      'id_personal_in_line',
      'r_id_personal_in_line',
      'r_id_personal',
      'id_personal',
      'personal_id',
    ]) {
      final v = p[k];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString();
    }
    return null;
  }

  // Etiquetas opcionales por id servicio
  static const Map<String, String> _kServiceNames = {
    '17': 'PRIMERA',
    '19': 'CONFORT',
    '20': 'Primera',
    '21': 'Servivio básico',
    '22': 'Servicio Plus',
    '23': 'Servicio Lujo',
    '27': 'Primera clase',
  };

  String? _selectedRutaId; // r_id_trip
  List<Map<String, dynamic>> _rutas =
      []; // id_trip, id_route, id_bus, nombre, fechaHora, id_service, service
  List<Map<String, dynamic>> _pasosActuales = [];
  String _ciudadActual = "Detectando...";
  bool _cargandoRutas = false;
  bool _cargandoPasos = false;

  // Venta
  String? _origenStepId;
  String? _destinoStepId;
  int _pasajeros = 1;

  Map<String, dynamic>? _rutaSeleccionada; // card resumen

  // Mostrar selector de asientos inline
  bool _showSeatPicker = false;

  // Precio filtrado por origen/destino
  double? _precioR;
  bool _loadingPrecio = false;

  @override
  void initState() {
    super.initState();
    _loadCredencialesGuardadas(); // ← cargar última ruta guardada
    _getUbicacionActual();
    _fetchRutas();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('id_personal_in_line => ${idPersonalInLine ?? 'null'}');
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ---------------- SharedPreferences ----------------
  Future<void> _saveViajeCredencial({
    required String idTrip,
    required String nombreRuta,
    required String fechaHora,
    required String idRoute,
    required String ciudad,
    String? destino,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final cred = {
      'id': idTrip,
      'nombreRuta': nombreRuta,
      'fechaHora': fechaHora,
      'id_route': idRoute,
      'destino': destino ?? '',
      'ciudad': ciudad,
    };
    await prefs.setString(kViajeCredKey, jsonEncode(cred));
  }

  Future<void> _loadCredencialesGuardadas() async {
    final prefs = await SharedPreferences.getInstance();
    final credString = prefs.getString(kViajeCredKey);
    if (credString != null) {
      final cred = jsonDecode(credString);
      _selectedRutaId = cred['id']?.toString();
      _ciudadActual =
          (prefs.getString(kCiudadActualKey) ?? cred['ciudad'] ?? '') as String;
      setState(() {});
    }
  }

  Future<void> _saveCiudadActual(String ciudad) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kCiudadActualKey, ciudad);
  }

  // ---------------- Ubicación ----------------
  Future<void> _getUbicacionActual() async {
    setState(() => _ciudadActual = "Detectando...");
    try {
      // 1) Asegura servicio ON. Si está OFF, abre ajustes y sigue.
      var serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await Geolocator.openLocationSettings();
        serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          setState(() => _ciudadActual = "GPS desactivado");
          return;
        }
      }

      // 2) Pide permiso runtime
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
        setState(() => _ciudadActual = "Sin permiso de ubicación");
        return;
      }
      if (perm != LocationPermission.always &&
          perm != LocationPermission.whileInUse) {
        setState(() => _ciudadActual = "Permiso denegado");
        return;
      }

      // 3) Obtener posición
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final city = await _getCityFromLatLng(
        position.latitude,
        position.longitude,
      );
      setState(
        () => _ciudadActual = city.isNotEmpty ? city : "Ciudad desconocida",
      );
      _saveCiudadActual(_ciudadActual);
    } catch (_) {
      setState(() => _ciudadActual = "Error de ubicación");
    }
  }

  Future<bool> ensureLocationReady() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      return false;
    }

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
      return false;
    }
    return perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse;
  }

  Future<String> _getCityFromLatLng(double lat, double lng) async {
    const apiKey = "AIzaSyCdmX3iHElqQEj2rM-smg6o1t68PmdSjLs";
    final url = Uri.parse(
      "https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lng&key=$apiKey",
    );
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final jsonResp = jsonDecode(response.body);
        if (jsonResp['status'] == 'OK') {
          final results = jsonResp['results'] as List<dynamic>;
          if (results.isNotEmpty) {
            for (final comp in results[0]['address_components']) {
              if ((comp['types'] as List).contains('locality')) {
                return comp['long_name'];
              }
            }
            for (final comp in results[0]['address_components']) {
              if ((comp['types'] as List).contains(
                'administrative_area_level_1',
              )) {
                return comp['long_name'];
              }
            }
            return results[0]['formatted_address'];
          }
        }
      }
    } catch (_) {}
    return "";
  }

  String _formatFechaHora(String fecha) {
    try {
      final dt = DateTime.parse(fecha);
      return DateFormat('dd/MM/yyyy HH:mm').format(dt);
    } catch (_) {
      return fecha;
    }
  }

  // Helper para driverId dinámico
  String? _resolveDriverId() {
    final p = personal;
    for (final k in const [
      'r_id_driver',
      'driver_id',
      'r_driver_id',
      'r_id_operator', // fallback si tu API mapea operador a chofer
    ]) {
      final v = p[k];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString();
    }
    return null;
  }

  // ---------------- Rutas/Viajes ----------------
  Future<void> _fetchRutas() async {
    setState(() => _cargandoRutas = true);
    try {
      final url = Uri.parse(
        'https://api-ticket-6wly.onrender.com/search-trips-app-v2',
      );

      // driverId = id_personal_in_line que ya normalizas en HomePage
      final driverId = idPersonalInLine;
      if (driverId == null || driverId.isEmpty) {
        debugPrint('driverId vacío (id_personal_in_line no disponible)');
        setState(() {
          _rutas = [];
          _selectedRutaId = null;
          _rutaSeleccionada = {};
        });
        return;
      }

      // El ejemplo exitoso de tu API usa ISO completo con Z
      final nowIsoUtc = DateTime.now().toUtc().toIso8601String();

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': 'yacjDEIxyrZPgAZMh83yUAiP86Y256QNkyhuix5qSgP7LnTQ4S',
        },
        body: jsonEncode({
          'p_date': nowIsoUtc,
          'p_timezone': 'America/Mexico_City',
          'p_driver_id': driverId, // << SOLO esto, sin operator
        }),
      );

      if (response.statusCode != 200) {
        debugPrint(
          'search-trips-app-v2 HTTP ${response.statusCode}: ${response.body}',
        );
        setState(() {
          _rutas = [];
          _selectedRutaId = null;
          _rutaSeleccionada = {};
        });
        return;
      }

      final jsonResp = jsonDecode(response.body);
      final List<dynamic> data = (jsonResp['data'] ?? []) as List<dynamic>;

      final list = <Map<String, dynamic>>[];
      for (final v in data) {
        list.add({
          'id_trip': (v['r_id_trip'] ?? '').toString(),
          'id_route': (v['r_id_route'] ?? '').toString(),
          'id_bus': (v['r_id_bus'] ?? '').toString(),
          'nombre': (v['r_name_route'] ?? '').toString(),
          'fechaHora': (v['r_departure_datetime_local'] ?? '').toString(),
          'id_service': (v['r_id_service'] ?? '').toString(),
          'service': (v['r_service'] ?? v['service'] ?? '').toString(),
        });
      }

      setState(() {
        _rutas = list;
        if (_selectedRutaId != null &&
            _rutas.any((r) => r['id_trip'] == _selectedRutaId)) {
          _rutaSeleccionada = _rutas.firstWhere(
            (r) => r['id_trip'] == _selectedRutaId,
          );
          final idRoute = _rutaSeleccionada!['id_route'] as String;
          if (idRoute.isNotEmpty) _fetchPasosDeRuta(idRoute);
        } else {
          _selectedRutaId = null;
          _rutaSeleccionada = {};
        }
      });
    } catch (e) {
      debugPrint('search-trips-app-v2 error: $e');
      setState(() {
        _rutas = [];
        _selectedRutaId = null;
        _rutaSeleccionada = {};
      });
    } finally {
      setState(() => _cargandoRutas = false);
    }
  }

  Future<void> _fetchPasosDeRuta(String idRoute) async {
    setState(() {
      _cargandoPasos = true;
      _pasosActuales = [];
      _origenStepId = null;
      _destinoStepId = null;
      _showSeatPicker = false;
      _precioR = null;
      _seatPickerEpoch++; // fuerza limpiar si estuviera abierto
      _origenCollapsed = false;
      _destinoCollapsed = false;
    });

    try {
      final url = Uri.parse(
        'https://api-ticket-6wly.onrender.com/search-steps-on-route-app',
      );
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': 'yacjDEIxyrZPgAZMh83yUAiP86Y256QNkyhuix5qSgP7LnTQ4S',
        },
        body: jsonEncode({'p_id_route': idRoute}),
      );
      if (response.statusCode == 200) {
        final jsonResp = jsonDecode(response.body);
        final List<dynamic> pasosData = jsonResp['data'];
        setState(() {
          _pasosActuales = pasosData
              .asMap()
              .entries
              .map<Map<String, dynamic>>(
                (entry) => {
                  "r_id_step_on_route": entry.value['r_id_step_on_route'],
                  "r_number_step": entry.value['r_number_step'],
                  "r_terminal_name": entry.value['r_terminal_name'],
                  "r_city": entry.value['r_city'],
                  "r_region": entry.value['r_region'],
                  "r_country": entry.value['r_country'],
                  "r_address": entry.value['r_address'],
                  "is_origen": entry.key == 0,
                },
              )
              .toList();
        });
      }
    } catch (_) {}
    setState(() => _cargandoPasos = false);
  }

  // ---- Precio por tramo (filtrado por origen/destino) ----
  Future<void> _fetchPrecioR({
    required String idRoute,
    required String idService,
    required String stepA,
    required String stepB,
  }) async {
    setState(() {
      _loadingPrecio = true;
      _precioR = null;
    });
    try {
      final resp = await http.post(
        Uri.parse(
          'https://api-ticket-6wly.onrender.com/search-prices-in-route',
        ),
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'x-api-key': 'yacjDEIxyrZPgAZMh83yUAiP86Y256QNkyhuix5qSgP7LnTQ4S',
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode({"p_id_route": idRoute, "p_id_service": idService}),
      );
      if (resp.statusCode == 200) {
        final obj = jsonDecode(resp.body);
        final data = obj['data'] as List?;
        if (data != null) {
          for (final it in data) {
            final a = '${it['r_id_id_step_on_route_a']}';
            final b = '${it['r_id_id_step_on_route_b']}';
            if (a == stepA && b == stepB) {
              final p = it['r_price'];
              setState(() => _precioR = (p is num) ? p.toDouble() : null);
              break;
            }
          }
        }
      }
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loadingPrecio = false);
    }
  }

  // ---------- helpers UI (tamaños responsivos) ----------
  double _scale(BoxConstraints c, double base, double tablet) =>
      c.maxWidth >= 800 ? tablet : base;

  // ---------- Select handlers ----------

  void _handleSelectOrigen(String stepOnRouteId) async {
    setState(() {
      _origenStepId = stepOnRouteId;
      _origenCollapsed = true;
      _destinoCollapsed = false;
      _showSeatPicker = false;
      _precioR = null;
    });

    final prefs = await SharedPreferences.getInstance();
    if (_rutaSeleccionada != null && _rutaSeleccionada!.isNotEmpty) {
      prefs.remove('checkin_${_rutaSeleccionada!['id_trip']}');
    }

    if (_destinoStepId != null &&
        _rutaSeleccionada != null &&
        _rutaSeleccionada!.isNotEmpty) {
      final svc = (_rutaSeleccionada!['id_service'] ?? '').toString();
      _fetchPrecioR(
        idRoute: _rutaSeleccionada!['id_route'],
        idService: svc,
        stepA: _origenStepId!,
        stepB: _destinoStepId!,
      );
    }
  }

  void _handleSelectDestino(String stepOnRouteId) async {
    setState(() {
      _destinoStepId = stepOnRouteId;
      _destinoCollapsed = true;
      _showSeatPicker = false;
      _precioR = null;
      _seatPickerEpoch++;
    });

    final prefs = await SharedPreferences.getInstance();
    if (_rutaSeleccionada != null && _rutaSeleccionada!.isNotEmpty) {
      prefs.remove('checkin_${_rutaSeleccionada!['id_trip']}');
    }

    if (_origenStepId != null &&
        _rutaSeleccionada != null &&
        _rutaSeleccionada!.isNotEmpty) {
      final svc = (_rutaSeleccionada!['id_service'] ?? '').toString();
      _fetchPrecioR(
        idRoute: _rutaSeleccionada!['id_route'],
        idService: svc,
        stepA: _origenStepId!,
        stepB: _destinoStepId!,
      );
    }
  }

  // ---------- VENTA ----------
  Widget _buildWelcomeScreen(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final isDark = settings.theme == AppTheme.blueDark;
    final mainColor = isDark
        ? const Color(0xFF29B6F6)
        : const Color(0xFFF20A32);
    final lang = settings.language;
    final cardColor = isDark ? const Color(0xFF232A35) : Colors.white;
    String t(String es, String en) => lang == AppLanguage.es ? es : en;

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = 2;
        final titleSize = _scale(constraints, 18, 22);
        final sectionLabel = _scale(constraints, 13, 16);
        final tileTitle = _scale(constraints, 12, 15);
        final tileSubtitle = _scale(constraints, 10, 13);
        final iconSize = _scale(constraints, 18, 22);
        final tileHeight = _scale(constraints, 60, 74);

        Widget stepTile(
          Map<String, dynamic> paso,
          bool active,
          VoidCallback onTap,
        ) {
          final city = (paso['r_city'] ?? '').toString();
          final key = GlobalKey();
          OverlayEntry? _entry;

          void hideOverlay() {
            _entry?.remove();
            _entry = null;
          }

          void showOverlay() {
            if (_entry != null) return;

            final box = key.currentContext!.findRenderObject() as RenderBox;
            final size = box.size;
            final offset = box.localToGlobal(Offset.zero);

            _entry = OverlayEntry(
              builder: (context) {
                return Stack(
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: hideOverlay,
                        behavior: HitTestBehavior.translucent,
                      ),
                    ),
                    Positioned(
                      left: offset.dx + size.width * 0.05,
                      top: offset.dy - 44,
                      child: Material(
                        color: Colors.transparent,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.85),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.location_on,
                                size: 16,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                city,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );

            Overlay.of(key.currentContext!, rootOverlay: true).insert(_entry!);
          }

          return GestureDetector(
            onLongPressStart: (_) => showOverlay(),
            onLongPressEnd: (_) => hideOverlay(),
            onTapCancel: hideOverlay,
            child: InkWell(
              key: key,
              onTap: () {
                hideOverlay();
                onTap();
              },
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: active ? mainColor : Colors.grey.shade300,
                    width: active ? 2 : 1,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 3,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(Icons.store, size: iconSize, color: mainColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        (paso['r_terminal_name'] ?? '').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: tileTitle + 20,
                        ),
                      ),
                    ),
                    if (active) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.check_circle,
                        size: iconSize,
                        color: mainColor,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }

        return SafeArea(
          child: ListView(
            controller: _scrollCtrl,
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + MediaQuery.of(context).viewPadding.bottom + 72,
            ),
            children: [
              Text(
                '1) ${t("Configura tu viaje", "Set up your trip")}',
                style: TextStyle(
                  fontSize: titleSize,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                elevation: 4,
                color: cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.directions_bus,
                            size: iconSize,
                            color: mainColor,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            t('Selecciona la ruta', 'Select route'),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: mainColor,
                              fontSize: sectionLabel,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        initialValue: _ciudadActual,
                        enabled: false,
                        decoration: InputDecoration(
                          labelText: t("Ciudad actual", "Current city"),
                          labelStyle: TextStyle(fontSize: sectionLabel),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          prefixIcon: Icon(Icons.location_city, size: iconSize),
                          isDense: true,
                        ),
                        style: TextStyle(fontSize: sectionLabel),
                      ),
                      const SizedBox(height: 10),

                      _cargandoRutas
                          ? const Center(
                              child: SizedBox(
                                height: 28,
                                width: 28,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : DropdownButtonFormField<String>(
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: t("Selecciona ruta", "Select route"),
                                labelStyle: TextStyle(fontSize: sectionLabel),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                prefixIcon: Icon(
                                  Icons.alt_route,
                                  size: iconSize,
                                ),
                                isDense: true,
                              ),
                              value:
                                  (_selectedRutaId != null &&
                                      _rutas.any(
                                        (r) => r['id_trip'] == _selectedRutaId,
                                      ))
                                  ? _selectedRutaId
                                  : null,
                              items: _rutas
                                  .map(
                                    (ruta) => DropdownMenuItem<String>(
                                      value: ruta['id_trip'],
                                      child: Text(
                                        '${ruta['nombre']}  •  ${_formatFechaHora(ruta['fechaHora'])}',
                                        style: TextStyle(
                                          fontSize: sectionLabel,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) async {
                                setState(() {
                                  _selectedRutaId = value;
                                  _rutaSeleccionada = _rutas.firstWhere(
                                    (e) => e['id_trip'] == value,
                                    orElse: () => {},
                                  );

                                  // LIMPIEZA TOTAL (sin tocar la ruta elegida)
                                  _pasosActuales = [];
                                  _origenStepId = null;
                                  _destinoStepId = null;
                                  _showSeatPicker = false;
                                  _origenCollapsed = false;
                                  _destinoCollapsed = false;

                                  _precioR = null;
                                  _pasajeros = 1;

                                  // fuerza “widget nuevo” del selector
                                  _seatPickerEpoch++;
                                });

                                if (_rutaSeleccionada != null &&
                                    _rutaSeleccionada!.isNotEmpty) {
                                  await _saveViajeCredencial(
                                    idTrip: _rutaSeleccionada!['id_trip'],
                                    nombreRuta: _rutaSeleccionada!['nombre'],
                                    fechaHora: _rutaSeleccionada!['fechaHora'],
                                    idRoute: _rutaSeleccionada!['id_route'],
                                    ciudad: _ciudadActual,
                                  );
                                  final idRoute =
                                      _rutaSeleccionada!['id_route'] as String;
                                  if (idRoute.isNotEmpty) {
                                    _fetchPasosDeRuta(idRoute);
                                  }

                                  // Borra cualquier check-in previo guardado para este viaje
                                  final prefs =
                                      await SharedPreferences.getInstance();
                                  prefs.remove(
                                    'checkin_${_rutaSeleccionada!['id_trip']}',
                                  );
                                }
                              },
                            ),
                      const SizedBox(height: 10),
                      if (_rutaSeleccionada != null &&
                          _rutaSeleccionada!.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 10,
                          ),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _rutaSeleccionada!['nombre'] ?? '',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: sectionLabel + 2,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _formatFechaHora(
                                  _rutaSeleccionada!['fechaHora'] ?? '',
                                ),
                                style: TextStyle(
                                  fontSize: sectionLabel,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),
              Text(
                '2) ${t("Elige Origen y Destino", "Choose Origin & Destination")}',
                style: TextStyle(
                  fontSize: titleSize,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),

              if (_pasosActuales.isEmpty && !_cargandoPasos)
                Card(
                  color: cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Selecciona una ruta para ver terminales',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              else if (_cargandoPasos)
                const Center(
                  child: SizedBox(
                    height: 28,
                    width: 28,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else ...[
                // ORIGEN
                Card(
                  color: cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.flag, size: iconSize, color: mainColor),
                            const SizedBox(width: 6),
                            Text(
                              t('Origen', 'Origin'),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: mainColor,
                                fontSize: sectionLabel + 10,
                              ),
                            ),
                            const Spacer(),
                            if (_origenCollapsed && _origenStepId != null)
                              TextButton.icon(
                                onPressed: () =>
                                    setState(() => _origenCollapsed = false),
                                icon: const Icon(Icons.edit),
                                label: Text(t('Cambiar', 'Change')),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        AnimatedCrossFade(
                          duration: const Duration(milliseconds: 200),
                          crossFadeState:
                              (_origenCollapsed && _origenStepId != null)
                              ? CrossFadeState.showSecond
                              : CrossFadeState.showFirst,

                          // Vista desplegada (selector)
                          firstChild: GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _pasosActuales.length,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisSpacing: 8,
                                  crossAxisSpacing: 8,
                                  mainAxisExtent: tileHeight,
                                ),
                            itemBuilder: (_, i) {
                              final p = _pasosActuales[i];
                              final active =
                                  _origenStepId == p['r_id_step_on_route'];
                              return stepTile(
                                p,
                                active,
                                () => _handleSelectOrigen(
                                  p['r_id_step_on_route'],
                                ),
                              );
                            },
                          ),

                          // Vista colapsada (resumen)
                          secondChild: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.08),
                              border: Border.all(color: Colors.green),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              _nombreTerminalById(_origenStepId) ?? '-',
                              style: TextStyle(
                                color: Colors.green[800],
                                fontWeight: FontWeight.w800,
                                fontSize: sectionLabel + 1,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // DESTINO
                Card(
                  color: cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.flag_circle,
                              size: iconSize,
                              color: mainColor,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              t('Destino', 'Destination'),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: mainColor,
                                fontSize: sectionLabel + 10,
                              ),
                            ),
                            const Spacer(),
                            if (_destinoCollapsed && _destinoStepId != null)
                              TextButton.icon(
                                onPressed: () =>
                                    setState(() => _destinoCollapsed = false),
                                icon: const Icon(Icons.edit),
                                label: Text(t('Cambiar', 'Change')),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        AnimatedCrossFade(
                          duration: const Duration(milliseconds: 200),
                          crossFadeState:
                              (_destinoCollapsed && _destinoStepId != null)
                              ? CrossFadeState.showSecond
                              : CrossFadeState.showFirst,

                          // Selector desplegado
                          firstChild: GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _pasosActuales.length,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisSpacing: 8,
                                  crossAxisSpacing: 8,
                                  mainAxisExtent: tileHeight,
                                ),
                            itemBuilder: (_, i) {
                              final p = _pasosActuales[i];
                              final active =
                                  _destinoStepId == p['r_id_step_on_route'];
                              return stepTile(
                                p,
                                active,
                                () => _handleSelectDestino(
                                  p['r_id_step_on_route'],
                                ),
                              );
                            },
                          ),

                          // Resumen colapsado
                          secondChild: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.08),
                                  border: Border.all(color: Colors.green),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  _nombreTerminalById(_destinoStepId) ?? '-',
                                  style: TextStyle(
                                    color: Colors.green[800],
                                    fontWeight: FontWeight.w800,
                                    fontSize: sectionLabel + 1,
                                  ),
                                ),
                              ),
                              if (_origenStepId != null &&
                                  _destinoStepId != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withOpacity(0.08),
                                      border: Border.all(color: Colors.green),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: _loadingPrecio
                                        ? const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              ),
                                              SizedBox(width: 8),
                                              Text('Calculando precio...'),
                                            ],
                                          )
                                        : (_precioR != null
                                              ? Text(
                                                  '${AppLocalizations.t("price", settings.language)}: \$${_precioR!.toStringAsFixed(2)}',
                                                  style: TextStyle(
                                                    color: Colors.green[800],
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                )
                                              : const Text(
                                                  'No hay tarifa para este tramo',
                                                  style: TextStyle(
                                                    color: Colors.red,
                                                  ),
                                                )),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 14),
              Text(
                '3) ${t("Pasajeros", "Passengers")}',
                style: TextStyle(
                  fontSize: titleSize,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),

              // --------- CONTADOR con – y + ---------
              Card(
                color: cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor: mainColor,
                          foregroundColor: Colors.white,
                          shape: const CircleBorder(),
                        ),
                        onPressed: () => setState(() {
                          if (_pasajeros > 1) _pasajeros--;
                          _showSeatPicker = false;
                          _seatPickerEpoch++; // fuerza rebuild limpio
                        }),
                        icon: const Icon(Icons.remove, size: 28),
                      ),
                      Column(
                        children: [
                          Text(
                            t('CANTIDAD', 'QUANTITY'),
                            style: TextStyle(
                              letterSpacing: 1.2,
                              fontSize: sectionLabel,
                              color: mainColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '$_pasajeros',
                            style: TextStyle(
                              fontSize: titleSize + 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor: mainColor,
                          foregroundColor: Colors.white,
                          shape: const CircleBorder(),
                        ),
                        onPressed: () => setState(() {
                          _pasajeros++;
                          _showSeatPicker = false;
                          _seatPickerEpoch++; // fuerza rebuild limpio
                        }),
                        icon: const Icon(Icons.add, size: 28),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed:
                      (_rutaSeleccionada != null &&
                          _rutaSeleccionada!.isNotEmpty &&
                          _origenStepId != null &&
                          _destinoStepId != null &&
                          _pasajeros >= 1)
                      ? () async {
                          await _saveViajeCredencial(
                            idTrip: _rutaSeleccionada!['id_trip'],
                            nombreRuta: _rutaSeleccionada!['nombre'],
                            fechaHora: _rutaSeleccionada!['fechaHora'],
                            idRoute: _rutaSeleccionada!['id_route'],
                            ciudad: _ciudadActual,
                            destino: _destinoStepId,
                          );

                          final busId = (_rutaSeleccionada!['id_bus'] ?? '')
                              .toString();
                          if (busId.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'No se encontró id_bus para la ruta seleccionada',
                                ),
                              ),
                            );
                            return;
                          }

                          setState(() {
                            _showSeatPicker = true;
                            _seatPickerEpoch++; // instancia fresca
                          });

                          await Future.delayed(
                            const Duration(milliseconds: 150),
                          );
                          if (_scrollCtrl.hasClients) {
                            _scrollCtrl.animateTo(
                              _scrollCtrl.position.maxScrollExtent,
                              duration: const Duration(milliseconds: 350),
                              curve: Curves.easeOut,
                            );
                          }
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: mainColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: TextStyle(
                      fontSize: sectionLabel + 1,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  icon: const Icon(Icons.event_seat, size: 24),
                  label: Text(t('Continuar', 'Continue')),
                ),
              ),

              // (Opcional) Botón “Limpiar todo”
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  if (_rutaSeleccionada != null &&
                      _rutaSeleccionada!.isNotEmpty) {
                    prefs.remove('checkin_${_rutaSeleccionada!['id_trip']}');
                  }

                  setState(() {
                    _pasosActuales = [];
                    _origenStepId = null;
                    _destinoStepId = null;
                    _pasajeros = 1;
                    _showSeatPicker = false;
                    _precioR = null;
                    _seatPickerEpoch++;
                    _origenCollapsed = false;
                    _destinoCollapsed = false;
                  });

                  final idRoute = (_rutaSeleccionada?['id_route'] ?? '')
                      .toString();
                  if (idRoute.isNotEmpty) {
                    _fetchPasosDeRuta(idRoute);
                  }
                },
                icon: const Icon(Icons.add_shopping_cart),
                label: const Text('Nueva orden'),
              ),

              // --------- Selector de asientos inline (expandible) ----------
              const SizedBox(height: 12),
              if (_showSeatPicker &&
                  _rutaSeleccionada != null &&
                  _rutaSeleccionada!.isNotEmpty)
                SeatSelectionInline(
                  key: ValueKey(
                    'seat-${_rutaSeleccionada!['id_trip']}-${_origenStepId}-${_destinoStepId}-${_pasajeros}-$_seatPickerEpoch',
                  ),
                  busId: _rutaSeleccionada!['id_bus'],
                  tripId: _rutaSeleccionada!['id_trip'],
                  passengers: _pasajeros,
                  originStepId: _pasosActuales
                      .firstWhere(
                        (p) => p['r_id_step_on_route'] == _origenStepId,
                      )['r_id_step_on_route']
                      .toString(),
                  destinationStepId: _pasosActuales
                      .firstWhere(
                        (p) => p['r_id_step_on_route'] == _destinoStepId,
                      )['r_id_step_on_route']
                      .toString(),
                  originStepNumber: int.tryParse(
                    _pasosActuales
                        .firstWhere(
                          (p) => p['r_id_step_on_route'] == _origenStepId,
                        )['r_number_step']
                        .toString(),
                  ),
                  destinationStepNumber: int.tryParse(
                    _pasosActuales
                        .firstWhere(
                          (p) => p['r_id_step_on_route'] == _destinoStepId,
                        )['r_number_step']
                        .toString(),
                  ),
                  initiallyExpanded: true,
                  occupiedApiBase:
                      'https://api-ticket-6wly.onrender.com/process-aviable-seats-on-trip',
                  onConfirmed: (seats, floors) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Asientos: ${seats.length} confirmados'),
                      ),
                    );
                  },
                  routeBasePrice: _precioR,
                  idRoute: _rutaSeleccionada!['id_route'],
                  idService: (_rutaSeleccionada!['id_service'] ?? '')
                      .toString(),
                  serviceLabel: (() {
                    final idSvc = (_rutaSeleccionada!['id_service'] ?? '')
                        .toString();
                    final lbl = _kServiceNames[idSvc];
                    if (lbl != null && lbl.trim().isNotEmpty) return lbl;
                    final s = (_rutaSeleccionada!['service'] ?? '').toString();
                    return s.isNotEmpty ? s : idSvc;
                  })(),
                  idPersonalInLine: idPersonalInLine,
                  // NOMBRE visible
                  name: (() {
                    final user = (personal['r_user_name'] ?? '').toString();
                    return user.isNotEmpty ? user : null;
                  })(),
                  travelDate: DateTime.tryParse(
                    _rutaSeleccionada!['fechaHora'] ?? '',
                  ),
                  lang: settings.language,
                ),
            ],
          ),
        );
      },
    );
  }

  // ---------- PERFIL ----------
  Widget _buildProfileScreen(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final lang = settings.language;
    final isDark = settings.theme == AppTheme.blueDark;
    final mainColor = isDark
        ? const Color(0xFF29B6F6)
        : const Color(0xFFF20A32);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          elevation: 4,
          color: isDark ? Colors.grey[900] : const Color(0xfff8f4fa),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ListTile(
            leading: Icon(Icons.person, size: 30, color: mainColor),
            title: Text(
              AppLocalizations.t('full_name', lang),
              style: TextStyle(fontWeight: FontWeight.bold, color: mainColor),
            ),
            subtitle: Text(
              personal['r_user_name'] ??
                  (lang == AppLanguage.es ? 'No disponible' : 'Not available'),
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          elevation: 4,
          color: isDark ? Colors.grey[900] : const Color(0xfff8f4fa),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ListTile(
            leading: Icon(Icons.work, size: 30, color: mainColor),
            title: Text(
              AppLocalizations.t('role', lang),
              style: TextStyle(fontWeight: FontWeight.bold, color: mainColor),
            ),
            subtitle: Text(
              personal['r_name_role'] ??
                  (lang == AppLanguage.es ? 'No disponible' : 'Not available'),
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          elevation: 4,
          color: isDark ? Colors.grey[900] : const Color(0xfff8f4fa),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ListTile(
            leading: Icon(Icons.business, size: 30, color: mainColor),
            title: Text(
              AppLocalizations.t('office', lang),
              style: TextStyle(fontWeight: FontWeight.bold, color: mainColor),
            ),
            subtitle: Text(
              personal['r_name_office'] ??
                  (lang == AppLanguage.es ? 'No disponible' : 'Not available'),
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          elevation: 4,
          color: isDark ? Colors.grey[900] : const Color(0xfff8f4fa),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ListTile(
            leading: Icon(Icons.badge, size: 30, color: mainColor),
            title: Text(
              AppLocalizations.t('operator', lang),
              style: TextStyle(fontWeight: FontWeight.bold, color: mainColor),
            ),
            subtitle: Text(
              personal['r_operator'] ??
                  (lang == AppLanguage.es ? 'No disponible' : 'Not available'),
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          elevation: 4,
          color: isDark ? Colors.grey[900] : const Color(0xfff8f4fa),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ListTile(
            leading: Icon(Icons.vpn_key, size: 30, color: mainColor),
            title: Text(
              AppLocalizations.t('id_personal_in_line', lang),
              style: TextStyle(fontWeight: FontWeight.bold, color: mainColor),
            ),
            subtitle: Text(
              idPersonalInLine ??
                  (lang == AppLanguage.es ? 'No disponible' : 'Not available'),
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ),
        ),

        const SizedBox(height: 30),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
                side: BorderSide(color: mainColor, width: 2),
              ),
            ),
            onPressed: () => _confirmLogout(context),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.logout, color: mainColor),
                const SizedBox(width: 10),
                Text(
                  AppLocalizations.t('logout', lang),
                  style: TextStyle(
                    fontSize: 16,
                    color: mainColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final lang = context.read<SettingsController>().language;
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(AppLocalizations.t('logout', lang)),
          content: Text(
            lang == AppLanguage.es
                ? '¿Volver a iniciar sesión?'
                : 'Do you want to login again?',
          ),
          actions: <Widget>[
            TextButton(
              child: Text(lang == AppLanguage.es ? 'No' : 'No'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: Text(lang == AppLanguage.es ? 'Sí' : 'Yes'),
              onPressed: () {
                Navigator.of(context).pop();
                _logout(context);
              },
            ),
          ],
        );
      },
    );
  }

  void _logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('email');
    await prefs.remove('password');
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginPage()),
      (Route<dynamic> route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final isDark = settings.theme == AppTheme.blueDark;
    final lang = settings.language;
    final mainColor = isDark
        ? const Color(0xFF29B6F6)
        : const Color(0xFFF20A32);

    final screens = [
      _buildWelcomeScreen(context),
      _buildProfileScreen(context),
      ConfiguracionViajePage(operatorId: idPersonalInLine ?? ''),
      const SettingsPage(),
      const WebsitePage(),
    ];

    final titles = [
      lang == AppLanguage.es ? 'Venta' : 'Sale',
      lang == AppLanguage.es ? 'Perfil' : 'Profile',
      lang == AppLanguage.es ? 'Configuración de viaje' : 'Trip setup',
      lang == AppLanguage.es ? 'Configuración' : 'Settings',
      lang == AppLanguage.es ? 'Sitio Web' : 'Website',
    ];

    final drawerOptions = [
      {
        'label': lang == AppLanguage.es ? 'Venta' : 'Sale',
        'index': 0,
        'icon': Icons.store,
      },
      {
        'label': lang == AppLanguage.es ? 'Perfil' : 'Profile',
        'index': 1,
        'icon': Icons.person,
      },
      {
        'label': lang == AppLanguage.es ? 'Conf. de viaje' : 'Trip setup',
        'index': 2,
        'icon': Icons.directions_bus,
      },
      {
        'label': lang == AppLanguage.es ? 'Config.' : 'Settings',
        'index': 3,
        'icon': Icons.settings,
      },
      {
        'label': lang == AppLanguage.es ? 'Sitio Web' : 'Website',
        'index': 4,
        'icon': Icons.language,
      },
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_currentIndex], style: TextStyle(color: mainColor)),
        automaticallyImplyLeading: false,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: mainColor,
        elevation: 0,
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: mainColor),
              child: const Center(
                child: Text(
                  'HOOK OBS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            ...drawerOptions
                .where((opt) => opt['index'] != _currentIndex)
                .map(
                  (opt) => ListTile(
                    leading: Icon(opt['icon'] as IconData, color: mainColor),
                    title: Text(opt['label'] as String),
                    onTap: () {
                      setState(() => _currentIndex = opt['index'] as int);
                      Navigator.pop(context);
                    },
                  ),
                )
                .toList(),
          ],
        ),
      ),
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: NavigationBar(
        height: 65,
        selectedIndex: _currentIndex,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        animationDuration: const Duration(milliseconds: 300),
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.store, color: mainColor),
            label: lang == AppLanguage.es ? 'Venta' : 'Sale',
          ),
          NavigationDestination(
            icon: Icon(Icons.person, color: mainColor),
            label: lang == AppLanguage.es ? 'Perfil' : 'Profile',
          ),
          NavigationDestination(
            icon: Icon(Icons.directions_bus, color: mainColor),
            label: lang == AppLanguage.es
                ? 'Configuración de viaje'
                : 'Trip setup',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings, color: mainColor),
            label: lang == AppLanguage.es ? 'Config.' : 'Settings',
          ),
          NavigationDestination(
            icon: Icon(Icons.language, color: mainColor),
            label: lang == AppLanguage.es ? 'Sitio Web' : 'Website',
          ),
        ],
      ),
    );
  }
}
