//lib/Viaje/configuracion_viaje_page.dart

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../Configuraciones/settings_controller.dart';
import '../Configuraciones/app_localizations.dart';
import 'package:provider/provider.dart';

// Modelo para los pasos de la ruta
class StepOnRoute {
  final String id;
  final String routeId;
  final int numberStep;
  final String terminalName;
  final String timezone;
  final double latitude;
  final double longitude;
  final String address;
  final String city;
  final String region;
  final String country;

  StepOnRoute({
    required this.id,
    required this.routeId,
    required this.numberStep,
    required this.terminalName,
    required this.timezone,
    required this.latitude,
    required this.longitude,
    required this.address,
    required this.city,
    required this.region,
    required this.country,
  });

  factory StepOnRoute.fromJson(Map<String, dynamic> json) {
    double _toDouble(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString() ?? '') ?? 0.0;
    }

    int _toInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    return StepOnRoute(
      id: json['r_id_step_on_route']?.toString() ?? '',
      routeId: json['r_id_route']?.toString() ?? '',
      numberStep: _toInt(json['r_number_step']),
      terminalName: json['r_terminal_name']?.toString() ?? '',
      timezone: json['r_timezone_name']?.toString() ?? '',
      latitude: _toDouble(json['r_latitude']),
      longitude: _toDouble(json['r_longitude']),
      address: json['r_address']?.toString() ?? '',
      city: json['r_city']?.toString() ?? '',
      region: json['r_region']?.toString() ?? '',
      country: json['r_country']?.toString() ?? '',
    );
  }
}

const String kViajeCredKey = 'viajeCredencial';
const String kCiudadActualKey = 'ciudadActual';
const String googleMapsApiKey = 'AIzaSyCdmX3iHElqQEj2rM-smg6o1t68PmdSjLs';

class ConfiguracionViajePage extends StatefulWidget {
  final String operatorId;
  const ConfiguracionViajePage({super.key, required this.operatorId});
  @override
  State<ConfiguracionViajePage> createState() => _ConfiguracionViajePageState();
}

class _ConfiguracionViajePageState extends State<ConfiguracionViajePage> {
  GoogleMapController? mapController;
  LatLng _currentPosition = const LatLng(19.4326, -99.1332);
  String _ubicacionTexto = '';
  String _ciudadActual = '';
  String? viajeSeleccionado;
  List<Map<String, dynamic>> viajes = [];
  bool cargandoViajes = true;
  Map<String, dynamic>? datosViaje;

  List<StepOnRoute> _stepsOnRoute = [];
  List<LatLng> _fullRoutePoints = [];
  String? terminalSeleccionada;

  bool get isDarkMode => Theme.of(context).brightness == Brightness.dark;
  AppLanguage get appLang => Provider.of<SettingsController>(context).language;

  bool _mapCollapsed = false;

  @override
  void initState() {
    super.initState();
    _ubicacionTexto = AppLocalizations.t('getting_location', AppLanguage.es);
    _loadViajeCredencial();
    _getCurrentLocation();
    _getViajes();
  }

  Future<void> _getCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(
        () =>
            _ubicacionTexto = AppLocalizations.t('location_disabled', appLang),
      );
      return;
    }
    final permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(
        () => _ubicacionTexto = AppLocalizations.t('location_denied', appLang),
      );
      return;
    }
    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    _currentPosition = LatLng(position.latitude, position.longitude);

    final city = await _getCityFromLatLng(
      position.latitude,
      position.longitude,
    );

    setState(() {
      _ciudadActual = city.isNotEmpty
          ? city
          : AppLocalizations.t('city_not_found', appLang);
      _ubicacionTexto = _ciudadActual;
    });
    _saveCiudadActual(_ciudadActual);
    mapController?.animateCamera(CameraUpdate.newLatLng(_currentPosition));
  }

  Future<String> _getCityFromLatLng(double lat, double lng) async {
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lng&key=$googleMapsApiKey',
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
    return '';
  }

  // ===== CAMBIADO SOLO ESTE MÉTODO =====
  Future<void> _getViajes() async {
    setState(() => cargandoViajes = true);

    // timestamptz completo, no sólo fecha
    final pDate = DateTime.now().toUtc().toIso8601String();
    final pTimezone = 'America/Mexico_City';

    // Reusa la prop actual como driver_id
    final pDriverId = widget.operatorId;

    final url = Uri.parse(
      'https://api-ticket-6wly.onrender.com/search-trips-app-v2',
    );

    try {
      final response = await http.post(
        url,
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'x-api-key': 'yacjDEIxyrZPgAZMh83yUAiP86Y256QNkyhuix5qSgP7LnTQ4S',
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode({
          'p_date': pDate,
          'p_timezone': pTimezone,
          'p_driver_id': pDriverId,
        }),
      );

      if (response.statusCode == 200) {
        final jsonResp = jsonDecode(response.body);
        final List<dynamic> data = (jsonResp['data'] as List?) ?? const [];
        setState(() {
          viajes = data
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          cargandoViajes = false;

          if (viajes.isNotEmpty) {
            final credId = viajeSeleccionado;
            final containsCred =
                credId != null &&
                viajes.any((v) => v['r_id_trip'].toString() == credId);

            viajeSeleccionado = containsCred
                ? credId
                : viajes[0]['r_id_trip'].toString();

            datosViaje = viajes.firstWhere(
              (v) => v['r_id_trip'].toString() == viajeSeleccionado,
              orElse: () => viajes[0],
            );

            _saveViajeCredencial(datosViaje!, null, _ciudadActual);

            final idRoute = datosViaje?['r_id_route'];
            if (idRoute != null && idRoute.toString().isNotEmpty) {
              // Mantienes tu método existente de escalas
              _fetchStepsOnRoute(idRoute.toString());
            }
          } else {
            viajeSeleccionado = null;
            datosViaje = null;
            _stepsOnRoute = [];
            _fullRoutePoints = [];
          }
        });
      } else {
        setState(() {
          cargandoViajes = false;
          viajes = [];
          viajeSeleccionado = null;
          datosViaje = null;
          _stepsOnRoute = [];
          _fullRoutePoints = [];
        });
      }
    } catch (_) {
      setState(() {
        cargandoViajes = false;
        viajes = [];
        viajeSeleccionado = null;
        datosViaje = null;
        _stepsOnRoute = [];
        _fullRoutePoints = [];
      });
    }
  }
  // ===== FIN DEL CAMBIO =====

  Future<void> _saveViajeCredencial(
    Map<String, dynamic> viaje,
    String? destino,
    String ciudad,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final cred = {
      'id': viaje['r_id_trip'].toString(),
      'nombreRuta': viaje['r_name_route'] ?? '',
      'fechaHora': viaje['r_departure_datetime_local'] ?? '',
      'id_route': viaje['r_id_route'] ?? '',
      'destino': destino ?? '',
      'ciudad': ciudad,
    };
    await prefs.setString(kViajeCredKey, jsonEncode(cred));
  }

  Future<void> _loadViajeCredencial() async {
    final prefs = await SharedPreferences.getInstance();
    final credString = prefs.getString(kViajeCredKey);
    if (credString != null) {
      final cred = jsonDecode(credString);
      setState(() {
        viajeSeleccionado = cred['id']?.toString();
        _ciudadActual = cred['ciudad']?.toString() ?? '';
        _ubicacionTexto = _ciudadActual;
      });
    }
    final ciudad = prefs.getString(kCiudadActualKey);
    if (ciudad != null) {
      setState(() {
        _ciudadActual = ciudad;
        _ubicacionTexto = ciudad;
      });
    }
  }

  Future<void> _saveCiudadActual(String ciudad) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kCiudadActualKey, ciudad);
  }

  String _formatFechaHora(String fecha) {
    try {
      final dt = DateTime.parse(fecha);
      return DateFormat('dd/MM/yyyy HH:mm').format(dt);
    } catch (_) {
      return fecha;
    }
  }

  Future<void> _fetchStepsOnRoute(String idRoute) async {
    final url = Uri.parse(
      'https://api-ticket-6wly.onrender.com/search-steps-on-route-app',
    );
    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': 'yacjDEIxyrZPgAZMh83yUAiP86Y256QNkyhuix5qSgP7LnTQ4S',
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode({'p_id_route': idRoute}),
      );
      if (response.statusCode == 200) {
        final jsonResp = jsonDecode(response.body);
        final List<dynamic> data = jsonResp['data'];
        final steps = data
            .map((e) => StepOnRoute.fromJson(e as Map<String, dynamic>))
            .toList();
        setState(() {
          _stepsOnRoute = steps;
          terminalSeleccionada = steps.isNotEmpty
              ? steps[0].terminalName
              : null;
        });
        await _buildFullRoute(steps);
        if (_stepsOnRoute.isNotEmpty) {
          mapController?.animateCamera(
            CameraUpdate.newLatLng(
              LatLng(
                _stepsOnRoute.first.latitude,
                _stepsOnRoute.first.longitude,
              ),
            ),
          );
        }
      } else {
        setState(() {
          _stepsOnRoute = [];
          _fullRoutePoints = [];
          terminalSeleccionada = null;
        });
      }
    } catch (_) {
      setState(() {
        _stepsOnRoute = [];
        _fullRoutePoints = [];
        terminalSeleccionada = null;
      });
    }
  }

  Future<List<LatLng>> getRoutePoints(LatLng origin, LatLng destination) async {
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json?origin=${origin.latitude},${origin.longitude}&destination=${destination.latitude},${destination.longitude}&key=$googleMapsApiKey',
    );
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final points = <LatLng>[];
      if (data['routes'] != null && data['routes'].isNotEmpty) {
        final overviewPolyline =
            data['routes'][0]['overview_polyline']['points'];
        points.addAll(_decodePolyline(overviewPolyline));
      }
      return points;
    }
    return [];
  }

  List<LatLng> _decodePolyline(String encoded) {
    final poly = <LatLng>[];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      poly.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return poly;
  }

  Future<void> _buildFullRoute(List<StepOnRoute> steps) async {
    final routePoints = <LatLng>[];
    for (int i = 0; i < steps.length - 1; i++) {
      final segment = await getRoutePoints(
        LatLng(steps[i].latitude, steps[i].longitude),
        LatLng(steps[i + 1].latitude, steps[i + 1].longitude),
      );
      if (routePoints.isNotEmpty && segment.isNotEmpty) {
        segment.removeAt(0);
      }
      routePoints.addAll(segment);
    }
    setState(() {
      _fullRoutePoints = routePoints;
    });
  }

  Set<Marker> _getMarkersOnRoute() {
    final markerColor = isDarkMode
        ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure)
        : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
    return _stepsOnRoute
        .map(
          (step) => Marker(
            markerId: MarkerId(step.id),
            position: LatLng(step.latitude, step.longitude),
            infoWindow: InfoWindow(
              title: '${step.numberStep}. ${step.terminalName}',
              snippet:
                  '${step.address.isNotEmpty ? '${step.address}, ' : ''}${step.city}',
            ),
            icon: markerColor,
          ),
        )
        .toSet();
  }

  Set<Polyline> _getPolylineOnRoute() {
    if (_fullRoutePoints.length < 2) return {};
    return {
      Polyline(
        polylineId: const PolylineId('real_route'),
        points: _fullRoutePoints,
        color: isDarkMode ? Colors.blue : Colors.red,
        width: 7,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
      ),
    };
  }

  void _setMapStyle() {
    // Intencionalmente vacío. Siempre modo claro.
  }

  @override
  Widget build(BuildContext context) {
    final Color mainColor = isDarkMode ? Colors.blue : Colors.red;
    final Color cardColor = isDarkMode ? const Color(0xFF222A35) : Colors.white;

    return Column(
      children: [
        // CARD 1: selector de viaje
        Padding(
          padding: const EdgeInsets.all(16),
          child: Card(
            color: cardColor,
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: cargandoViajes
                            ? const Center(child: CircularProgressIndicator())
                            : (viajes.isEmpty)
                            ? Text(
                                AppLocalizations.t('no_trips', appLang),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: mainColor,
                                ),
                              )
                            : DropdownButtonFormField<String>(
                                isExpanded: true,
                                decoration: InputDecoration(
                                  labelText: AppLocalizations.t(
                                    'select_trip',
                                    appLang,
                                  ),
                                  labelStyle: TextStyle(color: mainColor),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                value:
                                    (viajeSeleccionado != null &&
                                        viajes.any(
                                          (v) =>
                                              v['r_id_trip'].toString() ==
                                              viajeSeleccionado,
                                        ))
                                    ? viajeSeleccionado
                                    : (viajes.isNotEmpty
                                          ? viajes[0]['r_id_trip'].toString()
                                          : null),
                                items: viajes.map((viaje) {
                                  final idTrip = viaje['r_id_trip'].toString();
                                  final nombreRuta =
                                      (viaje['r_name_route'] ?? '').toString();
                                  final fechaHora =
                                      (viaje['r_departure_datetime_local'] ??
                                              '')
                                          .toString();
                                  final fechaHoraFmt = _formatFechaHora(
                                    fechaHora,
                                  );
                                  return DropdownMenuItem<String>(
                                    value: idTrip,
                                    child: Text.rich(
                                      TextSpan(
                                        children: [
                                          TextSpan(
                                            text: nombreRuta,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                          TextSpan(
                                            text: "\n$fechaHoraFmt",
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }).toList(),
                                onChanged: (value) async {
                                  setState(() {
                                    viajeSeleccionado = value;
                                    datosViaje = viajes.firstWhere(
                                      (v) => v['r_id_trip'].toString() == value,
                                      orElse: () => <String, dynamic>{},
                                    );
                                    if (datosViaje != null &&
                                        datosViaje!.isNotEmpty) {
                                      _saveViajeCredencial(
                                        datosViaje!,
                                        null,
                                        _ciudadActual,
                                      );
                                    }
                                  });
                                  final idRoute = datosViaje?['r_id_route'];
                                  if (idRoute != null &&
                                      idRoute.toString().isNotEmpty) {
                                    await _fetchStepsOnRoute(
                                      idRoute.toString(),
                                    );
                                  }
                                },
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 8.0),
                        child: SizedBox(
                          width: 32,
                          height: 32,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => setState(
                                () => _mapCollapsed = !_mapCollapsed,
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isDarkMode
                                      ? Colors.blue.shade50
                                      : Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Icon(
                                  _mapCollapsed
                                      ? Icons.expand_more
                                      : Icons.expand_less,
                                  color: mainColor,
                                  size: 20,
                                  semanticLabel: _mapCollapsed
                                      ? AppLocalizations.t('expand', appLang)
                                      : AppLocalizations.t('collapse', appLang),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (datosViaje != null && datosViaje!.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 6,
                      ),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (datosViaje!['r_name_route'] ?? '').toString(),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            datosViaje!['r_departure_datetime_local'] != null
                                ? _formatFechaHora(
                                    datosViaje!['r_departure_datetime_local']
                                        .toString(),
                                  )
                                : '',
                            style: const TextStyle(
                              fontSize: 11,
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
        ),

        // Mapa
        if (!_mapCollapsed)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              height: 260,
              child: Card(
                color: cardColor,
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: _currentPosition,
                      zoom: 7,
                    ),
                    onMapCreated: (controller) {
                      mapController = controller;
                      _setMapStyle();
                    },
                    markers: _stepsOnRoute.isNotEmpty
                        ? _getMarkersOnRoute()
                        : {},
                    polylines: _fullRoutePoints.length > 1
                        ? _getPolylineOnRoute()
                        : {},
                    myLocationEnabled: true,
                    zoomControlsEnabled: true,
                    scrollGesturesEnabled: true,
                    rotateGesturesEnabled: true,
                    tiltGesturesEnabled: true,
                    compassEnabled: true,
                    mapToolbarEnabled: true,
                  ),
                ),
              ),
            ),
          ),

        // Ubicación
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Card(
            color: cardColor,
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.location_on, color: mainColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${AppLocalizations.t('your_location', appLang)} $_ubicacionTexto',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: mainColor,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    color: mainColor,
                    tooltip: AppLocalizations.t('refresh', appLang),
                    onPressed: _getCurrentLocation,
                  ),
                ],
              ),
            ),
          ),
        ),

        // Terminales
        if (_stepsOnRoute.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Card(
              color: cardColor,
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.t('select_terminal', appLang),
                    labelStyle: TextStyle(color: mainColor),
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                  ),
                  dropdownColor: cardColor,
                  value: terminalSeleccionada,
                  items: _stepsOnRoute
                      .map(
                        (step) => DropdownMenuItem<String>(
                          value: step.terminalName,
                          child: Text(
                            step.terminalName,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: mainColor,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => terminalSeleccionada = value),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
