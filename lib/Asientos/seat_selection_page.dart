// lib/Asientos/seat_selection_page.dart
import 'dart:convert';
import 'dart:math';
import 'dart:ui' show FontFeature;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:shared_preferences/shared_preferences.dart';
// === USA SIEMPRE LOS MISMOS TIPOS: UNA SOLA ORIGEN (con prefijo) ===
import 'package:hook_obsprueba/Configuraciones/app_localizations.dart' as loc;
import 'package:hook_obsprueba/Configuraciones/settings_controller.dart' as cfg;
import 'package:intl/intl.dart';

// Impresión
import 'package:printing/printing.dart';

// Colores de estado (por defecto en layout)
const _kColorAvailable = Color(0xFFE4E4E4);
const _kColorOccupied = Color(0xFFC133FF);
const _kColorSelected = Color(0xFF00E1FF);
const _kColorInProcess = Color(0xFFFF7D00);

// Estilo verde en negritas
const TextStyle greenBold = TextStyle(
  color: Colors.green,
  fontWeight: FontWeight.w700,
);

// === Endpoints ===
const _STEP_RELATED_URL =
    'https://api-ticket-6wly.onrender.com/search-steps-related-on-route';
const _CONFIRM_ORDER_URL =
    'https://api-ticket-6wly.onrender.com/insert-normalize-process-sale';
const String _PRINT_URL =+
    'https://api-ticket-container-711150519387.us-west1.run.app/process-tickets-trail-travel-html';
const _VALIDATE_CURP_URL = 'https://api-ticket-6wly.onrender.com/validate-curp';

String _pp(dynamic v) {
  try {
    return const JsonEncoder.withIndent('  ').convert(v);
  } catch (_) {
    return '$v';
  }
}

String _mask(String v) => v.replaceAll(RegExp(r'[A-Za-z0-9]{16,}'), '***');
String _curl(String url, Map<String, String> headers, Object? body) {
  final h = headers.entries
      .map((e) => "-H '${e.key}: ${_mask(e.value)}'")
      .join(' ');
  final b = body == null
      ? ''
      : "-d '${_mask(body is String ? body : jsonEncode(body))}'";
  return "curl -X POST $h $b '$url'";
}

void _d(String label, String msg) {
  if (kDebugMode) debugPrint('[$label] $msg');
}

class SeatSelectionInline extends StatefulWidget {
  final String busId;
  final String tripId; // id_trip para RPC
  final int passengers;

  // UUIDs para RPC get_id_step_related
  final String originStepId;
  final String destinationStepId;

  // Números de paso para la API de ocupación
  final int? originStepNumber;
  final int? destinationStepNumber;

  final bool initiallyExpanded;
  final String occupiedApiBase;
  final void Function(List<String> seatIds, int floorCount)? onConfirmed;

  // Idioma actual
  final cfg.AppLanguage lang;

  // datos para descuentos y costo base
  final double? routeBasePrice; // r_price
  final String? idRoute;
  final String? idService; // ej. '18'
  final String? serviceLabel; // ej. 'PRIMERA'
  final String? nameRole; // ← nombre del rol
  final String? idPersonalInLine; // para id_personal_in_line
  final String? name; // ← NOMBRE visible para UI/impresión
  final String? paymentReference; // para payment-reference
  final DateTime? travelDate;
  final VoidCallback? onClose;

  const SeatSelectionInline({
    super.key,
    required this.busId,
    required this.tripId,
    required this.passengers,
    required this.originStepId,
    required this.destinationStepId,
    this.onClose,
    this.originStepNumber,
    this.destinationStepNumber,
    this.initiallyExpanded = true,
    this.occupiedApiBase =
        'https://api-ticket-6wly.onrender.com/process-aviable-seats-on-trip',
    this.onConfirmed,
    this.lang = cfg.AppLanguage.es,
    this.routeBasePrice,
    this.idRoute,
    this.idService,
    this.serviceLabel,
    this.nameRole,
    this.idPersonalInLine,
    this.name,
    this.paymentReference,
    this.travelDate,
  });

  @override
  State<SeatSelectionInline> createState() => _SeatSelectionInlineState();
}

class _PassengerControllers {
  final nombres = TextEditingController();
  final apPat = TextEditingController();
  final apMat = TextEditingController();
  final phone = TextEditingController();
  final curp = TextEditingController();
  final sexo = TextEditingController();
  final edad = TextEditingController();
  String? tipo;

  void dispose() {
    nombres.dispose();
    apPat.dispose();
    apMat.dispose();
    phone.dispose();
    curp.dispose();
    sexo.dispose();
    edad.dispose();
  }
}

Color _accentColor(BuildContext ctx) =>
    Theme.of(ctx).brightness == Brightness.dark ? Colors.blue : Colors.red;

enum _PaymentMethod { cash, card, mixed }

class _SeatSelectionInlineState extends State<SeatSelectionInline> {
  bool _closed = false;

  String tr(String key) => loc.AppLocalizations.t(key, widget.lang);

  String _serviceLabelFromId(String? id) {
    switch (id) {
      case '18':
        return 'PRIMERA';
      case '19':
        return 'EJECUTIVO';
      default:
        return id ?? '-';
    }
  }

  ButtonStyle _themedOutlinedStyle(BuildContext ctx) {
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    final Color bg = isDark
        ? const Color(0xFF0B6FFF).withOpacity(0.12)
        : const Color(0xFFFFE6EA);
    final Color fg = isDark ? const Color(0xFFA8D4F3) : const Color(0xFFD50000);
    final Color br = isDark ? const Color(0xFF0B6FFF) : const Color(0xFFD50000);

    return ButtonStyle(
      foregroundColor: MaterialStateProperty.resolveWith(
        (states) =>
            states.contains(MaterialState.disabled) ? fg.withOpacity(0.4) : fg,
      ),
      backgroundColor: MaterialStateProperty.resolveWith(
        (states) =>
            states.contains(MaterialState.disabled) ? bg.withOpacity(0.5) : bg,
      ),
      side: MaterialStateProperty.resolveWith(
        (states) => BorderSide(
          color: states.contains(MaterialState.disabled)
              ? br.withOpacity(0.4)
              : br,
          width: 2,
        ),
      ),
    );
  }

  String _paymentMethodLabelES() {
    switch (_paymentMethod) {
      case _PaymentMethod.cash:
        return 'Efectivo';
      case _PaymentMethod.card:
        return 'Tarjeta';
      case _PaymentMethod.mixed:
        return 'Mixto';
    }
  }

  bool _expanded = true;
  bool _loadingSeats = true;
  bool _loadingOcc = true;
  String _error = '';

  List<Map<String, dynamic>> _floor1 = [];
  List<Map<String, dynamic>> _floor2 = [];
  int _currentFloor = 1;

  final Set<String> _selectedSeatIds = {};
  final Set<int> _occupiedNumbers = {};
  final Set<int> _inProcessNumbers = {};

  bool _showCheckIn = false;

  // pago
  bool _showPayment = false;
  _PaymentMethod _paymentMethod = _PaymentMethod.cash;

  // montos
  final TextEditingController _cashCtrl = TextEditingController(text: '0.00');
  final TextEditingController _changeCtrl = TextEditingController(text: '0.00');
  final TextEditingController _cardCtrl = TextEditingController(text: '0.00');

  double _changeValue = 0.0;

  List<String> get _passengerTypesI18n => [
    tr('ptype_minor'),
    tr('ptype_adult'),
    tr('ptype_senior'),
  ];

  List<_PassengerControllers> _forms = [];
  late final stt.SpeechToText _stt = stt.SpeechToText();

  // Precio base y descuentos
  double? _routePrice; // r_price
  final Map<int, Map<String, dynamic>> _selectedDiscounts = {};
  List<Map<String, dynamic>> _discountsCache = [];
  bool _loadingDiscounts = false;
  String? _discountsError;

  // RPC escalas relacionadas (label + id)
  String? _stepRelatedLabel;
  String? _stepRelatedId; // ID real para el normalizador
  bool _loadingStepRelated = false;
  String? _stepRelatedErr;

  // Envío de orden
  bool _sendingOrder = false;

  // Identificadores/fechas
  String? _orderTemporalId; // temporal-id de orden
  late final DateTime _now = DateTime.now();

  // impresión
  bool _printing = false;

  // Tickets recién vendidos (para impresión/mostrar)
  List<Map<String, dynamic>> _lastSoldTickets = [];
  List<String> _lastTicketOriginIds = [];

  // Cache local
  String? _idPersonalInLine;
  String? _name;

  // Snapshot de nombres para impresión post-reset
  List<String> _lastPassengersFullNames = [];

  // — Reimpresión controlada —
  List<Map<String, dynamic>>? _reprintTickets;
  String? _reprintFolio;
  int _reprintCount = 0;
  static const int _reprintMax = 2;

  bool get _canReprint =>
      _reprintTickets != null && _reprintCount < _reprintMax;
  int get _reprintsLeft => _reprintMax - _reprintCount;

  // ---------- IMPRESIÓN ----------
  String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  String _fmtTime(DateTime d) {
    final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final minute = d.minute.toString().padLeft(2, '0');
    final ampm = d.hour < 12 ? 'am' : 'pm';
    return '${hour12.toString().padLeft(2, '0')}:$minute $ampm';
  }

  String _longDateEs(DateTime d) {
    const dias = [
      'Lunes',
      'Martes',
      'Miércoles',
      'Jueves',
      'Viernes',
      'Sábado',
      'Domingo',
    ];
    const meses = [
      'Enero',
      'Febrero',
      'Marzo',
      'Abril',
      'Mayo',
      'Junio',
      'Julio',
      'Agosto',
      'Septiembre',
      'Octubre',
      'Noviembre',
      'Diciembre',
    ];
    final wd = dias[d.weekday - 1];
    final mes = meses[d.month - 1];
    final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final mm = d.minute.toString().padLeft(2, '0');
    final ampm = d.hour < 12 ? 'a. m.' : 'p. m.';
    return '$wd, $mes ${d.day}, ${d.year} - $h12:$mm $ampm';
  }

  Future<
    ({
      String origen,
      String destino,
      String terminalOrigen,
      String terminalDestino,
    })
  >
  _resolveRouteEnds() async {
    String origen = '-', destino = '-', terminalO = '-', terminalD = '-';
    try {
      if ((widget.idRoute ?? '').isNotEmpty) {
        final resp = await http.post(
          Uri.parse(
            'https://api-ticket-6wly.onrender.com/search-steps-on-route-app',
          ),
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'x-api-key': 'yacjDEIxyrZPgAZMh83yUAiP86Y256QNkyhuix5qSgP7LnTQ4S',
            'ngrok-skip-browser-warning': 'true',
          },
          body: jsonEncode({'p_id_route': widget.idRoute}),
        );
        if (resp.statusCode == 200) {
          final list = (jsonDecode(resp.body)['data'] as List?) ?? const [];
          Map? sO = list.firstWhere(
            (e) => '${e['r_id_step_on_route']}' == widget.originStepId,
            orElse: () => null,
          );
          Map? sD = list.firstWhere(
            (e) => '${e['r_id_step_on_route']}' == widget.destinationStepId,
            orElse: () => null,
          );
          if (sO != null) {
            terminalO = '${sO['r_terminal_name'] ?? '-'}';
            origen = '${sO['r_city'] ?? '-'}';
          }
          if (sD != null) {
            terminalD = '${sD['r_terminal_name'] ?? '-'}';
            destino = '${sD['r_city'] ?? '-'}';
          }
        }
      }
    } catch (_) {}
    return (
      origen: origen,
      destino: destino,
      terminalOrigen: terminalO,
      terminalDestino: terminalD,
    );
  }

List<Map<String, dynamic>> _buildTicketsForPrint({
  required String metodoPago,
  required String origen,
  required String destino,
  required String terminalOrigen,
  required String terminalDestino,
  List<Map<String, dynamic>>? realTickets,
  List<String>? ticketIdsOrigin,
  String? fallbackFolio,
}) {
  final base = _routePrice ?? 0.0;

  // Compra: fecha y hora
  final nowStr = '${_fmtDate(_now)} ${_fmtTime(_now)}';

  // Viaje: SOLO fecha en formato ISO, hora por separado
  final salida = widget.travelDate ?? _now;
  final fechaSalida = _fmtDate(salida);   // <-- 2025-10-17
  final horaSalida = _fmtTime(salida);    // <-- 10:00 am
  final servicio = (widget.serviceLabel != null && widget.serviceLabel!.trim().isNotEmpty)
      ? widget.serviceLabel!.trim()
      : _serviceLabelFromId(widget.idService);
  const clase = 'Primera';

  final seller = (_name?.trim().isNotEmpty ?? false) ? _name!.trim() : (widget.nameRole ?? '');

  final seatIds = _selectedSeatIds.toList()
    ..sort((a, b) => (_seatNumberFromId(a) ?? 99999).compareTo(_seatNumberFromId(b) ?? 99999));

  return List.generate(widget.passengers, (i) {
    final rt = (realTickets != null && i < realTickets.length) ? realTickets[i] : null;

    final idTicket = (ticketIdsOrigin != null &&
            i < ticketIdsOrigin.length &&
            (ticketIdsOrigin[i]).toString().isNotEmpty)
        ? ticketIdsOrigin[i]
        : (rt?['id_ticket']?.toString() ?? (fallbackFolio ?? ''));

    final seatFromApi = (rt?['seat'] is num) ? (rt!['seat'] as num).toInt() : int.tryParse('${rt?['seat'] ?? ''}');
    final seatId = (i < seatIds.length) ? seatIds[i] : null;
    final seatNumLocal = seatId != null ? _seatNumberFromId(seatId) : null;
    final asiento = seatFromApi ?? seatNumLocal ?? '-';

    final dLocal = _selectedDiscounts[i];
    final descuentoMontoLocal = (dLocal?['monto_descuento'] is num) ? (dLocal!['monto_descuento'] as num).toDouble() : 0.0;
    final descuentoNombreLocal = dLocal?['name'];
    final precioFinalLocal = (dLocal?['precio_final'] is num) ? (dLocal!['precio_final'] as num).toDouble() : base;

    final descuentoMontoApi = (rt?['discount'] is num) ? (rt!['discount'] as num).toDouble() : null;
    final precioApi = (rt?['price'] is num) ? (rt!['price'] as num).toDouble() : null;
    final descuentoNombreApi = rt?['discount_name'];

    final descuentoMonto = descuentoMontoApi ?? descuentoMontoLocal;
    final total = precioApi ?? precioFinalLocal;

    final p = (i < _forms.length) ? _forms[i] : null;
    final actualFullName = (p == null)
        ? ''
        : [
            p.nombres.text.trim(),
            p.apPat.text.trim(),
            p.apMat.text.trim(),
          ].where((e) => e.isNotEmpty).join(' ').trim();

    final snapshotFullName = (i < _lastPassengersFullNames.length) ? _lastPassengersFullNames[i].trim() : '';
    final fullName = actualFullName.isNotEmpty ? actualFullName : snapshotFullName;
    final pasajero = fullName.isNotEmpty ? fullName : 'Pasajero ${i + 1}';

    return {
      "idTicket": idTicket,
      "seller": seller,
      "clase": clase,
      "origen": origen,
      "destino": destino,
      "terminalOrigen": terminalOrigen,
      "terminalDestino": terminalDestino,
      "subida": terminalOrigen,
      "fechaSalida": fechaSalida,           // 2025-10-17
      "horaSalida": horaSalida,             // 10:00 am
      "asiento": asiento,
      "servicio": servicio,
      "anden": "—",
      "tarifa": '\$${base.toStringAsFixed(2)}',
      "descuento": '\$${descuentoMonto.toStringAsFixed(2)}',
      "descuentoNombre": '${descuentoNombreApi ?? descuentoNombreLocal ?? ''}',
      "total": '\$${total.toStringAsFixed(2)}',
      "metodoPago": metodoPago,
      "pasajero": pasajero,
      "fechaCompra": nowStr,                // 2025-10-17 03:50 pm
    };
  });
}


  Future<void> _printTicketsWithServer(
    List<Map<String, dynamic>> tickets,
  ) async {
    try {
      setState(() => _printing = true);
      final resp = await http.post(
        Uri.parse(_PRINT_URL),
        headers: const {
          'Accept': 'application/pdf',
          'Content-Type': 'application/json',
          'x-api-key': 'yacjDEIxyrZPgAZMh83yUAiP86Y256QNkyhuix5qSgP7LnTQ4S',
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode(tickets),
      );

      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
      }

      final pdfBytes = resp.bodyBytes;
      await Printing.layoutPdf(onLayout: (_) async => pdfBytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo imprimir: $e')));
    } finally {
      if (!mounted) return;
      setState(() => _printing = false);
    }
  }

  // Reset DURO para dejar todo limpio (incluso layout y cachés)
  Future<void> _hardResetAll() async {
    if (!mounted) return;
    setState(() {
      _expanded = widget.initiallyExpanded;
      _showCheckIn = false;
      _showPayment = false;
      _sendingOrder = false;
      _printing = false;

      _selectedSeatIds.clear();
      _inProcessNumbers.clear();
      _occupiedNumbers.clear();

      for (final f in _forms) f.dispose();
      _forms.clear();
      _selectedDiscounts.clear();
      _discountsCache.clear();
      _loadingDiscounts = false;
      _discountsError = null;

      _cashCtrl.text = '0.00';
      _cardCtrl.text = '0.00';
      _changeCtrl.text = '0.00';
      _changeValue = 0.0;

      _lastSoldTickets.clear();
      _lastTicketOriginIds.clear();
      _lastPassengersFullNames.clear();

      _orderTemporalId = _genTemporalId();

      _error = '';
      _floor1.clear();
      _floor2.clear();
      _currentFloor = 1;

      _reprintTickets = null;
      _reprintFolio = null;
      _reprintCount = 0;
    });

    await _fetchSeats();
    await _fetchOccupiedSeats();
    await _prefetchDiscountsOnce();
    await _fetchStepRelatedLabel();
  }

  // Imprimir con conteo y limpiar al llegar a 2/2
  Future<bool> _printAndMaybeFinalize() async {
    if (_reprintTickets == null) return false;

    bool printedOk = false;
    try {
      await _printTicketsWithServer(_reprintTickets!);
      printedOk = true;
    } catch (e) {
      printedOk = false;
    }

    if (!mounted) return printedOk;

    // Contar intento SIEMPRE, haya impreso o no.
    final nextAttempt = _reprintCount + 1;
    setState(() => _reprintCount = nextAttempt);

    if (printedOk) {
      // Éxito: si llegó al máximo, cerrar y limpiar; si no, solo avisar.
      if (nextAttempt >= _reprintMax) {
        setState(() => _closed = true);
        widget.onClose?.call();
        WidgetsBinding.instance.addPostFrameCallback((_) => _hardResetAll());
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Reimpresiones restantes: ${_reprintMax - nextAttempt}',
            ),
          ),
        );
      }
      return true;
    }

    // Falló la impresión
    if (nextAttempt >= _reprintMax) {
      // Se acabaron los intentos: cancelar flujo local.
      await _resetFlowAfterOrder();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Orden cancelada: no se imprimió el ticket tras 2 intentos',
          ),
        ),
      );
      // Si tienes endpoint para anular/void, invócalo aquí.
      return false;
    } else {
      // Aún quedan intentos: pasar a flujo de reimpresión
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se imprimió. Reintenta. Restantes: ${_reprintMax - nextAttempt}',
          ),
        ),
      );
      return false;
    }
  }

  Future<void> _onPrintPressed({String? folio}) async {
    // Redirigir a la lógica de reimpresión con conteo
    if (_reprintTickets != null) {
      await _printAndMaybeFinalize();
      return;
    }
    // Si no hay snapshot de tickets, no hace nada
  }

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    _routePrice = widget.routeBasePrice;
    _orderTemporalId = _genTemporalId();
    _cashCtrl.addListener(_recalcPayment);
    _cardCtrl.addListener(_recalcPayment);
    _loadIdPersonalInLine();
    _bootstrap();
  }

  @override
  void didUpdateWidget(covariant SeatSelectionInline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tripId != widget.tripId ||
        oldWidget.originStepId != widget.originStepId ||
        oldWidget.destinationStepId != widget.destinationStepId) {
      _hardResetAll();
    }
  }

  Future<void> _loadIdPersonalInLine() async {
    final fromProp = widget.idPersonalInLine?.trim();
    if (fromProp != null && fromProp.isNotEmpty) {
      _idPersonalInLine = fromProp;
    } else {
      final prefs = await SharedPreferences.getInstance();
      final fromPrefs = prefs.getString('id_personal_in_line')?.trim();
      if (fromPrefs != null && fromPrefs.isNotEmpty) {
        _idPersonalInLine = fromPrefs;
      }
    }

    final nameFromProp = widget.name?.trim();
    if (nameFromProp != null && nameFromProp.isNotEmpty) {
      _name = nameFromProp;
    } else {
      final prefs = await SharedPreferences.getInstance();
      _name = prefs.getString('name')?.trim();
    }

    if (kDebugMode) {
      debugPrint('ID_PERSONAL_IN_LINE = ${_idPersonalInLine ?? '(null)'}');
      debugPrint('NAME = ${_name ?? '(null)'}');
    }
    if (mounted) setState(() {});
  }

  String _genTemporalId() {
    final rnd = Random.secure().nextInt(1 << 32);
    return '${_now.millisecondsSinceEpoch}-$rnd';
  }

  @override
  void dispose() {
    for (final f in _forms) {
      f.dispose();
    }
    _stt.stop();
    _cashCtrl.dispose();
    _changeCtrl.dispose();
    _cardCtrl.dispose();
    super.dispose();
  }

  void _ensureForms() {
    if (_forms.length == widget.passengers) return;
    for (final f in _forms) {
      f.dispose();
    }
    _forms = List.generate(widget.passengers, (_) => _PassengerControllers());
  }

  Future<void> _bootstrap() async {
    await _fetchSeats();
    await _fetchOccupiedSeats();
    await _prefetchDiscountsOnce();
    await _fetchStepRelatedLabel();
  }

  // -------- DESCUENTOS --------
  Future<void> _prefetchDiscountsOnce() async {
    if (_routePrice == null) return;
    setState(() {
      _loadingDiscounts = true;
      _discountsError = null;
    });
    try {
      _discountsCache = await _fetchDiscountsDynamic();
    } catch (e) {
      _discountsError = e.toString();
    } finally {
      if (mounted) setState(() => _loadingDiscounts = false);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchDiscountsDynamic() async {
    final String pIdOperator = '10';
    final String pIdService = widget.idService ?? '18';
    final String pBasePrice = (_routePrice ?? 0).toStringAsFixed(2);
    final String pDateIso = (widget.travelDate ?? DateTime.now().toUtc())
        .toIso8601String();

    final resp = await http.post(
      Uri.parse(
        'https://api-ticket-6wly.onrender.com/search-discounts-per-trip',
      ),
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'x-api-key': 'yacjDEIxyrZPgAZMh83yUAiP86Y256QNkyhuix5qSgP7LnTQ4S',
        'ngrok-skip-browser-warning': 'true',
      },
      body: jsonEncode({
        "p_id_operator": pIdOperator,
        "p_id_service": pIdService,
        "p_date": pDateIso,
        "p_base_price": pBasePrice,
      }),
    );

    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}');
    }

    final obj = jsonDecode(resp.body);
    final data = obj is Map<String, dynamic> ? obj['data'] : null;
    if (data is List) {
      return data.map<Map<String, dynamic>>((e0) {
        final e = Map<String, dynamic>.from(e0 as Map);
        e['id'] ??=
            e['r_id_discount'] ??
            e['r_id_discount_type'] ??
            e['r_id_promotion'] ??
            e['discount_id'];
        return e;
      }).toList();
    }
    return [];
  }

  // --------- Seats / Occupancy ----------
  Future<void> _fetchSeats() async {
    setState(() {
      _loadingSeats = true;
      _error = '';
      _floor1 = [];
      _floor2 = [];
      _selectedSeatIds.clear();
    });

    try {
      final url = Uri.parse(
        'https://api-ticket-6wly.onrender.com/process-views-templates?id_bus=${widget.busId}',
      );
      final resp = await http.get(
        url,
        headers: const {
          'x-api-key': 'yacjDEIxyrZPgAZMh83yUAiP86Y256QNkyhuix5qSgP7LnTQ4S',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
      );

      if (!mounted) return;

      if (resp.statusCode != 200) {
        setState(() {
          _error = 'Error ${resp.statusCode}: no se pudo cargar asientos';
          _loadingSeats = false;
        });
        return;
      }

      final data = (jsonDecode(resp.body)['data'] as Map<String, dynamic>?);
      List<Map<String, dynamic>> f1 = [], f2 = [];
      if (data != null) {
        if (data['floor1'] is List) {
          f1 = (data['floor1'] as List)
              .map<Map<String, dynamic>>(
                (e) => {
                  'number_seat': e['number_seat'],
                  'id_seat': e['id_seat'],
                  'index_template': e['index_template'],
                },
              )
              .toList();
        }
        if (data['floor2'] is List) {
          f2 = (data['floor2'] as List)
              .map<Map<String, dynamic>>(
                (e) => {
                  'number_seat': e['number_seat'],
                  'id_seat': e['id_seat'],
                  'index_template': e['index_template'],
                },
              )
              .toList();
        }
      }
      f1.sort(
        (a, b) =>
            (a['index_template'] as int).compareTo(b['index_template'] as int),
      );
      f2.sort(
        (a, b) =>
            (a['index_template'] as int).compareTo(b['index_template'] as int),
      );

      setState(() {
        _floor1 = f1;
        _floor2 = f2;
        _currentFloor = _floor2.isNotEmpty ? 2 : 1;
        _loadingSeats = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Error de red: $e';
        _loadingSeats = false;
      });
    }
  }

  Future<void> _fetchOccupiedSeats() async {
    setState(() => _loadingOcc = true);
    try {
      final stepA =
          (widget.originStepNumber ?? int.tryParse(widget.originStepId) ?? 0)
              .toString();
      final stepB =
          (widget.destinationStepNumber ??
                  int.tryParse(widget.destinationStepId) ??
                  0)
              .toString();

      final uri = Uri.parse(widget.occupiedApiBase).replace(
        queryParameters: {
          'id_trip': widget.tripId,
          'step_a': stepA,
          'step_b': stepB,
        },
      );

      final resp = await http.get(
        uri,
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'x-api-key': 'yacjDEIxyrZPgAZMh83yUAiP86Y256QNkyhuix5qSgP7LnTQ4S',
          'ngrok-skip-browser-warning': 'true',
        },
      );

      if (!mounted) return;

      final body = jsonDecode(resp.body);
      final occ = <int>{};
      if (body is List) {
        for (final item in body) {
          final n = item['occupied_seat'];
          if (n is int) {
            occ.add(n);
          } else if (n is num) {
            occ.add(n.toInt());
          }
        }
      }
      setState(() {
        _occupiedNumbers
          ..clear()
          ..addAll(occ);
        _loadingOcc = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingOcc = false);
    }
  }

  // === RPC relación de escalas ===
  Future<void> _fetchStepRelatedLabel() async {
    setState(() {
      _loadingStepRelated = true;
      _stepRelatedErr = null;
      _stepRelatedLabel = null;
      _stepRelatedId = null;
    });

    try {
      final payload = {
        'p_id_step_on_route_a': widget.originStepId,
        'p_id_step_on_route_b': widget.destinationStepId,
        'id_step_on_route_a': widget.originStepId,
        'id_step_on_route_b': widget.destinationStepId,
      };
      final resp = await http.post(
        Uri.parse(_STEP_RELATED_URL),
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'x-api-key': 'yacjDEIxyrZPgAZMh83yUAiP86Y256QNkyhuix5qSgP7LnTQ4S',
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode(payload),
      );

      if (resp.statusCode != 200) {
        setState(() {
          _stepRelatedErr = 'HTTP ${resp.statusCode} • ${resp.body}';
          _loadingStepRelated = false;
        });
        return;
      }

      final obj = jsonDecode(resp.body);
      final ok = obj is Map && obj['success'] == true;
      final List data = ok && obj['data'] is List
          ? (obj['data'] as List)
          : const [];
      final count = (obj['count'] is num)
          ? (obj['count'] as num).toInt()
          : data.length;

      String? firstId;
      if (data.isNotEmpty) {
        final d0 = data.first;
        if (d0 is Map) {
          firstId =
              ['r_id_step_related', 'id_step_related', 'step_related_id', 'id']
                  .map((k) => d0[k])
                  .firstWhere(
                    (v) => v != null && '$v'.trim().isNotEmpty,
                    orElse: () => null,
                  )
                  ?.toString();
        } else {
          firstId = '$d0';
        }
      }

      setState(() {
        _stepRelatedId = firstId;
        _stepRelatedLabel = firstId != null
            ? 'Relación de escalas • ID: $firstId  •  $count encontrados'
            : 'Relación de escalas • Sin relación ($count)';
        _loadingStepRelated = false;
      });
    } catch (e) {
      setState(() {
        _stepRelatedErr = e.toString();
        _loadingStepRelated = false;
      });
    }
  }

  List<List<Map<String, dynamic>?>> _chunkRows(
    List<Map<String, dynamic>> seats,
  ) {
    final List<List<Map<String, dynamic>?>> rows = [];
    for (int i = 0; i < seats.length; i += 4) {
      rows.add([
        i < seats.length ? seats[i] : null,
        i + 1 < seats.length ? seats[i + 1] : null,
        i + 2 < seats.length ? seats[i + 2] : null,
        i + 3 < seats.length ? seats[i + 3] : null,
      ]);
    }
    return rows;
  }

  bool _isOccNum(int n) => _occupiedNumbers.contains(n);
  bool _isProcNum(int n) => _inProcessNumbers.contains(n);
  bool _isSelId(String id) => _selectedSeatIds.contains(id);

  void _toggleSeat(Map<String, dynamic> seat) {
    if (_showPayment) return;
    final id = seat['id_seat'].toString();
    final n = (seat['number_seat'] ?? 0) as int;

    if (_isOccNum(n) || _isProcNum(n)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(tr('seat_unavailable'))));
      return;
    }
    if (_isSelId(id)) {
      setState(() => _selectedSeatIds.remove(id));
      return;
    }
    if (_selectedSeatIds.length >= widget.passengers) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${tr('max_seats_reached')}: ${widget.passengers}'),
        ),
      );
      return;
    }
    setState(() => _selectedSeatIds.add(id));
  }

  void _autoFillSeats() {
    if (_selectedSeatIds.length >= widget.passengers) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${tr('max_seats_reached')}: ${widget.passengers}'),
        ),
      );
      return;
    }

    final List<Map<String, dynamic>> ordered = [
      ...(_currentFloor == 1 ? _floor1 : _floor2),
      ...(_currentFloor == 1 ? _floor2 : _floor1),
    ];

    int remaining = widget.passengers - _selectedSeatIds.length;
    int added = 0;

    for (final seat in ordered) {
      if (remaining == 0) break;
      final id = seat['id_seat']?.toString();
      final n = (seat['number_seat'] ?? 0) as int;
      if (id == null) continue;
      if (_selectedSeatIds.contains(id)) continue;
      if (_isOccNum(n) || _isProcNum(n)) continue;
      _selectedSeatIds.add(id);
      remaining--;
      added++;
    }

    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added == 0 ? tr('no_seats_to_fill') : '${tr('seats_added')} ($added)',
        ),
      ),
    );
  }

  Widget _miniAmount(
    String label,
    String value, {
    bool bold = false,
    double size = 14,
    Color? labelColor,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: size, color: labelColor),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: size,
              fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  int? _seatNumberFromId(String id) {
    for (final s in [..._floor1, ..._floor2]) {
      if ('${s['id_seat']}' == id) {
        return (s['number_seat'] as num?)?.toInt();
      }
    }
    return null;
  }

  String _fullName(_PassengerControllers f) => [
    f.nombres.text,
    f.apPat.text,
    f.apMat.text,
  ].where((e) => e.trim().isNotEmpty).join(' ');

  double get _totalToCharge {
    double t = 0.0;
    final base = _routePrice ?? 0.0;
    for (int i = 0; i < widget.passengers; i++) {
      final d = _selectedDiscounts[i];
      if (d != null && d['precio_final'] is num) {
        t += (d['precio_final'] as num).toDouble();
      } else {
        t += base;
      }
    }
    return t;
  }

  double _parseMoney(String s) =>
      double.tryParse(s.replaceAll(',', '.')) ?? 0.0;

  void _recalcPayment() {
    final total = _totalToCharge;
    final cash = _parseMoney(_cashCtrl.text);
    final card = _parseMoney(_cardCtrl.text);

    double received;
    switch (_paymentMethod) {
      case _PaymentMethod.cash:
        received = cash;
        break;
      case _PaymentMethod.card:
        received = card;
        break;
      case _PaymentMethod.mixed:
        received = cash + card;
        break;
    }

    final diff = (received == 0) ? 0.0 : (received - total);
    _changeValue = diff;
    _changeCtrl.text = diff.toStringAsFixed(2);
    if (mounted) setState(() {});
  }

  void _onPaymentMethodChanged() {
    final total = _totalToCharge.toStringAsFixed(2);
    if (_paymentMethod == _PaymentMethod.card) {
      _cardCtrl.text = total;
      _cashCtrl.text = '0.00';
    } else if (_paymentMethod == _PaymentMethod.cash) {
      _cardCtrl.text = '0.00';
    } else {
      if (_cardCtrl.text.trim().isEmpty) _cardCtrl.text = '0.00';
      if (_cashCtrl.text.trim().isEmpty) _cashCtrl.text = '0.00';
    }
    _recalcPayment();
  }

  void _showOrderSummaryDialog() {
    if (_routePrice == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(tr('no_base_price'))));
      return;
    }
    _ensureForms();
    String L(String es, String en) =>
        widget.lang == cfg.AppLanguage.es ? es : en;

    final seatIdsSorted = _selectedSeatIds.toList()
      ..sort(
        (a, b) => (_seatNumberFromId(a) ?? 99999).compareTo(
          _seatNumberFromId(b) ?? 99999,
        ),
      );

    showDialog<void>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final bg = Theme.of(ctx).brightness == Brightness.dark
            ? Colors.grey.shade800
            : Colors.grey.shade200;

        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760, minWidth: 520),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.receipt_long, color: cs.primary),
                      const SizedBox(width: 8),
                      Text(
                        L('Resumen de pasajeros', 'Passengers summary'),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: widget.passengers,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final f = (i < _forms.length)
                            ? _forms[i]
                            : _PassengerControllers();
                        final seatId = i < seatIdsSorted.length
                            ? seatIdsSorted[i]
                            : null;
                        final seatNum = seatId != null
                            ? _seatNumberFromId(seatId)
                            : null;

                        final d = _selectedDiscounts[i];
                        final base = _routePrice ?? 0.0;
                        final monto = (d?['monto_descuento'] is num)
                            ? (d!['monto_descuento'] as num).toDouble()
                            : 0.0;
                        final total = (d?['precio_final'] is num)
                            ? (d!['precio_final'] as num).toDouble()
                            : base;

                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${L('Pasajero', 'Passenger')} ${i + 1}: ${_fullName(f)}',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${tr('fare_origin_fee')}: \$${_money(base)}',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                    Text(
                                      '${tr('selected_seat_origin')}: ${seatNum ?? '-'}',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                    Text(
                                      '${L('Descuento aplicado para viaje de ida', 'Applied discount (outbound)')}: ${_money(monto)}',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '\$${_money(total)}',
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(L('Cerrar', 'Close')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showDiscountsDialog(int passengerIndex) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;

        const lightSelectedBg = Color(0xFFF96982);
        const darkSelectedBg = Color(0xFFA8D4F3);
        final Color selectedBorder = isDark
            ? const Color(0xFF0B6FFF)
            : const Color(0xFFD50000);
        final Color selectedBg = isDark ? darkSelectedBg : lightSelectedBg;

        final double maxH = MediaQuery.of(ctx).size.height * 0.75;

        int? selectedIdx;

        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: SizedBox(
            width: 760,
            height: maxH,
            child: StatefulBuilder(
              builder: (ctx, setLocal) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Text(
                      tr('discounts_title'),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: _discountsCache.isEmpty
                        ? Center(child: Text(tr('no_discounts')))
                        : GridView.builder(
                            padding: const EdgeInsets.all(16),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  childAspectRatio: 2.4,
                                ),
                            itemCount: _discountsCache.length,
                            itemBuilder: (_, i) {
                              final d = _discountsCache[i];

                              final name = '${d['name'] ?? ''}';
                              final typeValue = '${d['type_value'] ?? ''}';
                              final value = d['value'];
                              final base = _routePrice ?? 0.0;

                              final monto = (d['monto_descuento'] is num)
                                  ? (d['monto_descuento'] as num).toDouble()
                                  : double.tryParse(
                                          '${d['monto_descuento']}',
                                        ) ??
                                        0.0;
                              final precioFin = (d['precio_final'] is num)
                                  ? (d['precio_final'] as num).toDouble()
                                  : double.tryParse('${d['precio_final']}') ??
                                        base;

                              final isPercent = typeValue
                                  .toString()
                                  .toUpperCase()
                                  .contains('PERC');
                              final vNum = (value is num)
                                  ? value.toDouble()
                                  : double.tryParse('$value');
                              final valorFmt = isPercent && vNum != null
                                  ? '${vNum.toStringAsFixed(0)}%'
                                  : '\$${_money(value)}';

                              final bool selected = selectedIdx == i;

                              return Material(
                                color: selected
                                    ? selectedBg
                                    : Theme.of(ctx).cardColor,
                                borderRadius: BorderRadius.circular(14),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () => setLocal(() => selectedIdx = i),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: selected
                                            ? selectedBorder
                                            : Colors.black12,
                                        width: selected ? 2 : 1,
                                      ),
                                    ),
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                name,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.w800,
                                                  color: Theme.of(
                                                    ctx,
                                                  ).colorScheme.primary,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Text(
                                              valorFmt,
                                              style: TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.w900,
                                                color: Theme.of(
                                                  ctx,
                                                ).colorScheme.secondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        _miniAmount(
                                          widget.lang == cfg.AppLanguage.es
                                              ? 'Costo de servicio'
                                              : 'Service cost',
                                          '\$${_money(base)}',
                                          size: 16,
                                          labelColor: Theme.of(
                                            ctx,
                                          ).colorScheme.onSurfaceVariant,
                                          valueColor: Theme.of(
                                            ctx,
                                          ).colorScheme.tertiary,
                                        ),
                                        _miniAmount(
                                          widget.lang == cfg.AppLanguage.es
                                              ? '% Descuento'
                                              : 'Discount %',
                                          base > 0
                                              ? '${(monto / base * 100).toStringAsFixed(0)}%'
                                              : '0%',
                                          size: 16,
                                          labelColor: Theme.of(
                                            ctx,
                                          ).colorScheme.onSurfaceVariant,
                                          valueColor: Colors.pink,
                                        ),
                                        _miniAmount(
                                          widget.lang == cfg.AppLanguage.es
                                              ? 'Costo final'
                                              : 'Final cost',
                                          '\$${_money(precioFin)}',
                                          bold: true,
                                          size: 17,
                                          valueColor: Colors.green.shade800,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: Text(
                            widget.lang == cfg.AppLanguage.es
                                ? 'Cerrar'
                                : 'Close',
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: selectedIdx == null
                              ? null
                              : () {
                                  final d = _discountsCache[selectedIdx!];
                                  setState(
                                    () =>
                                        _selectedDiscounts[passengerIndex] = d,
                                  );
                                  Navigator.pop(ctx);
                                  _recalcPayment();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        widget.lang == cfg.AppLanguage.es
                                            ? 'Descuento aplicado'
                                            : 'Discount applied',
                                      ),
                                    ),
                                  );
                                },
                          child: Text(
                            widget.lang == cfg.AppLanguage.es
                                ? 'Aplicar'
                                : 'Apply',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ======= Envío de orden / validación =======
  String? _validateBeforeConfirm() {
    if (_selectedSeatIds.length != widget.passengers) {
      return 'Selecciona ${widget.passengers} asientos.';
    }
    if (_routePrice == null) {
      return 'No hay precio base para el tramo.';
    }
    if (_stepRelatedId == null || _stepRelatedId!.isEmpty) {
      return 'No se pudo obtener id_step_related del RPC.';
    }
    if ((_idPersonalInLine ?? '').isEmpty) {
      return 'Falta id_personal_in_line.';
    }
    final total = _totalToCharge;
    final cash = _parseMoney(_cashCtrl.text);
    final card = _parseMoney(_cardCtrl.text);
    final received = switch (_paymentMethod) {
      _PaymentMethod.cash => cash,
      _PaymentMethod.card => card,
      _PaymentMethod.mixed => cash + card,
    };
    if (received < total) {
      return 'Monto recibido insuficiente.';
    }
    return null;
  }

  String? _getDiscountId(Map<String, dynamic>? d) {
    if (d == null) return null;
    final candidates = [
      'id',
      'uuid',
      'r_id_discount',
      'r_discount_id',
      'r_id_discount_type',
      'r_id_type_discount',
      'r_id_discount_trip',
      'r_id_discount_per_trip',
      'id_discount',
      'discount_id',
      'r_id_promotion',
      'promotion_id',
    ];
    for (final k in candidates) {
      final v = d[k];
      if (v != null && '$v'.trim().isNotEmpty) return '$v';
    }
    return null;
  }

  List<Map<String, dynamic>> _buildRawArrayForNormalizer() {
    final seatIds = _selectedSeatIds.toList()
      ..sort(
        (a, b) => (_seatNumberFromId(a) ?? 99999).compareTo(
          _seatNumberFromId(b) ?? 99999,
        ),
      );

    final double base = _routePrice ?? 0.0;
    final double cash = _parseMoney(_cashCtrl.text);
    final double card = _parseMoney(_cardCtrl.text);
    final double changeToReturn = _changeValue > 0 ? _changeValue : 0.0;

    final nowIso = _now.toIso8601String();
    final orderTemporalId = _orderTemporalId ?? _genTemporalId();
    final paymentRef = (widget.paymentReference?.trim().isNotEmpty ?? false)
        ? widget.paymentReference!.trim()
        : '${_now.millisecondsSinceEpoch}-${Random().nextInt(1 << 16)}';
    final concept = 'Venta app móvil';

    List<Map<String, dynamic>> arr = [];

    for (int i = 0; i < widget.passengers; i++) {
      final f = _forms[i];
      final seatId = (i < seatIds.length) ? seatIds[i] : null;
      final seatNum = seatId != null ? _seatNumberFromId(seatId) : null;

      final d = _selectedDiscounts[i];
      final discountId = _getDiscountId(d);
      final priceFinal = (d != null && d['precio_final'] is num)
          ? (d['precio_final'] as num).toDouble()
          : base;
      final discountValue = (base - priceFinal).clamp(0, double.infinity);

      final item = <String, dynamic>{
        // ---- CUSTOMER ----
        "name": f.nombres.text.trim().isEmpty ? null : f.nombres.text.trim(),
        "last-name": f.apPat.text.trim().isEmpty ? null : f.apPat.text.trim(),
        "second-last-name": f.apMat.text.trim().isEmpty
            ? null
            : f.apMat.text.trim(),
        "email": null,
        "phone-number": f.phone.text.trim().isEmpty
            ? null
            : f.phone.text.trim(),
        "gender": null,
        "user_relation": null,
        "type-passenger": f.tipo ?? tr('ptype_adult'),

        // ---- ORIGIN LEG ----
        "id-trip": widget.tripId,
        "bus-number-seat-origin": seatNum,
        "id-step-related-origin": _stepRelatedId,
        "price-service-origin": priceFinal,
        "taxe-gest-origin": 0.0,
        "price-seat-origin": 0.0,
        "discount-id-origin": discountId,
        "discount-origin": discountValue,

        // ---- ARRIVE (no usado) ----
        "id-trip-arrive": null,
        "bus-number-seat-arrive": null,
        "id-step-related-arrive": null,
        "price-service-arrive": 0,
        "taxe-gest-arrive": 0,
        "price-seat-arrive": 0,
        "discount-id-return": null,
        "discount-arrive": 0,

        // ---- Identificador temporal por pasajero ----
        "temporal-id": '$orderTemporalId-P$i',
      };

      arr.add(item);
    }

    if (arr.isNotEmpty) {
      arr[0].addAll({
        // ---- PAYMENT (global) ----
        "payment-method": _paymentMethod.name,
        "status": "paid",
        "payment-reference": paymentRef,
        "user_relation": null,

        // ---- ORDER / DERIVATION (global) ----
        "id_personal_in_line": _idPersonalInLine,
        "amount-recived": (cash + card),
        "amount-returned": changeToReturn,
        "money-amount": cash,
        "card-amount": card,
        "transfer-amount": 0,
        "concept": concept,

        // Solo bitácora/UI
        "operator-origin": widget.nameRole,

        // ---- Extras visibles
        "Creation Date": nowIso,
        "Modified Date": nowIso,
        "temporal-id": orderTemporalId,
      });
    }

    return arr;
  }

  void _setProcessFromSelection(bool value) {
    final nums = _selectedSeatIds.map(_seatNumberFromId).whereType<int>();
    setState(() {
      if (value) {
        _inProcessNumbers
          ..clear()
          ..addAll(nums);
      } else {
        _inProcessNumbers.clear();
      }
    });
  }

  Future<void> _resetFlowAfterOrder() async {
    setState(() {
      _showCheckIn = false;
      _showPayment = false;
      _selectedSeatIds.clear();
      _forms.clear();
      _selectedDiscounts.clear();
      _inProcessNumbers.clear();
      _cashCtrl.text = '0.00';
      _cardCtrl.text = '0.00';
      _changeCtrl.text = '0.00';
      _changeValue = 0.0;
      _orderTemporalId = _genTemporalId();
      _lastSoldTickets = [];
      _lastTicketOriginIds = [];
      // reimpresión
      _reprintTickets = null;
      _reprintFolio = null;
      _reprintCount = 0;
    });
    await _fetchOccupiedSeats();
  }

  Future<void> _showSuccessDialog({String? folio, String? msg}) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Venta realizada'),
        content: Text(
          msg ??
              'La orden se confirmó correctamente.${folio != null ? '\nFolio: $folio' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _resetFlowAfterOrder();
            },
            child: const Text('Cerrar'),
          ),
          FilledButton(
            onPressed: _printing
                ? null
                : () async {
                    Navigator.pop(context);
                    await _onPrintPressed(folio: folio);
                  },
            child: const Text('Imprimir ticket'),
          ),
        ],
      ),
    );
  }

  Future<void> _showErrorDialog(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('No se pudo confirmar'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Imprimir ticket (pendiente)')),
              );
            },
            child: const Text('Imprimir ticket'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitOrder() async {
    final err = _validateBeforeConfirm();
    if (err != null) {
      _d('SALE/VALID', err);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(err)));
      }
      return;
    }

    final rawArray = _buildRawArrayForNormalizer();

    setState(() => _sendingOrder = true);
    final sw = Stopwatch()..start();
    try {
      final url = _CONFIRM_ORDER_URL;
      final hdrs = const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'x-api-key': 'yacjDEIxyrZPgAZMh83yUAiP86Y256QNkyhuix5qSgP7LnTQ4S',
        'ngrok-skip-browser-warning': 'true',
      };
      final bodyStr = jsonEncode(rawArray);

      _d('SALE/REQ', 'POST $url');
      _d('SALE/HDR', _pp(hdrs));
      _d('SALE/BODY', _pp(rawArray));
      _d('SALE/CURL', _curl(url, Map<String, String>.from(hdrs), bodyStr));

      final resp = await http.post(
        Uri.parse(url),
        headers: hdrs,
        body: bodyStr,
      );
      sw.stop();

      _d(
        'SALE/RSP',
        'status=${resp.statusCode} timeMs=${sw.elapsedMilliseconds}',
      );
      _d('SALE/RHDR', _pp(resp.headers));
      final bodyText = resp.body;
      _d(
        'SALE/RBODY',
        bodyText.length > 4000
            ? '${bodyText.substring(0, 4000)}...(+${bodyText.length - 4000} bytes)'
            : bodyText,
      );

      if (resp.statusCode != 200) {
        await _showErrorDialog('HTTP ${resp.statusCode}: ${resp.body}');
        _setProcessFromSelection(false);
        await _fetchOccupiedSeats();
        setState(() => _sendingOrder = false);
        return;
      }

      final dynamic parsedBody = jsonDecode(resp.body);
      if (parsedBody is! Map || parsedBody['success'] != true) {
        await _showErrorDialog('Orden no confirmada: ${resp.body}');
        _setProcessFromSelection(false);
        await _fetchOccupiedSeats();
        setState(() => _sendingOrder = false);
        return;
      }

      final Map<String, dynamic> obj = Map<String, dynamic>.from(
        parsedBody as Map<String, dynamic>,
      );

      try {
        final Map<String, dynamic> rpc = (obj['rpc_result'] is Map)
            ? Map<String, dynamic>.from(obj['rpc_result'])
            : obj;

        final dynamic idsAny =
            rpc['r_tickets_origin_ids'] ?? rpc['tickets_origin_ids'];
        if (idsAny is List) {
          _lastTicketOriginIds = idsAny
              .map((e) => e?.toString() ?? '')
              .where((s) => s.isNotEmpty)
              .toList();
        } else {
          _lastTicketOriginIds = [];
        }

        final dynamic listLike =
            rpc['tickets'] ?? obj['tickets'] ?? obj['data'];
        if (listLike is List && listLike.isNotEmpty) {
          _lastSoldTickets = listLike
              .whereType<dynamic>()
              .where((e) => e is Map)
              .map<Map<String, dynamic>>((e0) {
                final e = Map<String, dynamic>.from(e0 as Map);
                return {
                  'id_ticket': '${e['id_ticket'] ?? ''}',
                  'seat':
                      e['seat'] ??
                      e['bus_number_seat_origin'] ??
                      e['bus_number_seat'],
                  'price':
                      (e['price_service_origin'] ?? e['price_service'] ?? 0)
                          is num
                      ? ((e['price_service_origin'] ?? e['price_service'])
                                as num)
                            .toDouble()
                      : 0.0,
                  'discount':
                      (e['discount_origin'] ?? e['discount'] ?? 0) is num
                      ? ((e['discount_origin'] ?? e['discount']) as num)
                            .toDouble()
                      : 0.0,
                  'discount_name': e['discount_name'],
                };
              })
              .toList();
        } else {
          final payload = obj['payload_sent'];
          final customers = (payload is Map) ? payload['customers'] : null;
          if (customers is List && customers.isNotEmpty) {
            _lastSoldTickets = customers
                .whereType<dynamic>()
                .where((c) => c is Map && (c as Map)['origin'] is Map)
                .map<Map<String, dynamic>>((c0) {
                  final c = Map<String, dynamic>.from(c0 as Map);
                  final origin = Map<String, dynamic>.from(c['origin'] as Map);
                  return {
                    'id_ticket': '',
                    'seat': origin['seat'],
                    'price': (origin['price_service'] ?? 0) is num
                        ? (origin['price_service'] as num).toDouble()
                        : 0.0,
                    'discount': (origin['discount_value'] ?? 0) is num
                        ? (origin['discount_value'] as num).toDouble()
                        : 0.0,
                    'discount_name': origin['discount_name'],
                  };
                })
                .toList();
          } else {
            _lastSoldTickets = [];
          }
        }
      } catch (_) {
        _lastTicketOriginIds = [];
        _lastSoldTickets = [];
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Orden confirmada')));
      }

      final String? folio =
          (_lastTicketOriginIds.isNotEmpty
              ? _lastTicketOriginIds.first
              : null) ??
          (obj['rpc_result'] is Map
              ? (obj['rpc_result']['id_ticket']?.toString())
              : null) ??
          obj['id_ticket']?.toString();

      _lastPassengersFullNames = List.generate(widget.passengers, (i) {
        if (i < _forms.length) {
          final f = _forms[i];
          return [
            f.nombres.text,
            f.apPat.text,
            f.apMat.text,
          ].where((e) => e.trim().isNotEmpty).join(' ').trim();
        }
        return '';
      });

      // Preparar datos para reimpresión controlada (0/2)
      final metodoPago = _paymentMethodLabelES();
      final ends = await _resolveRouteEnds();
      final tickets = _buildTicketsForPrint(
        metodoPago: metodoPago,
        origen: ends.origen,
        destino: ends.destino,
        terminalOrigen: ends.terminalOrigen,
        terminalDestino: ends.terminalDestino,
        realTickets: _lastSoldTickets.isEmpty ? null : _lastSoldTickets,
        ticketIdsOrigin: _lastTicketOriginIds.isEmpty
            ? null
            : _lastTicketOriginIds,
        fallbackFolio: folio ?? (_orderTemporalId ?? _genTemporalId()),
      );

      setState(() {
        _reprintTickets = tickets;
        _reprintFolio = folio ?? (_orderTemporalId ?? _genTemporalId());
        _reprintCount = 0;
        _showPayment = true; // mantener a la vista la tarjeta de pago
      });
      final printed = await _printAndMaybeFinalize();
      if (!mounted) return;

      if (!printed) {
        // No mostrar mensaje de éxito todavía.
        // El usuario podrá usar "Reimprimir ticket (x/2)".
        return;
      }

      // Solo si imprimió al menos una vez correctamente:
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Venta completada. Puedes reimprimir el ticket (${_reprintCount}/${_reprintMax}).',
          ),
        ),
      );

      // Si quieres imprimir automáticamente la 1a vez, descomenta:
      // await _printAndMaybeFinalize();
    } catch (e) {
      if (!mounted) return;
      await _showErrorDialog('Error enviando orden: $e');
      _setProcessFromSelection(false);
      await _fetchOccupiedSeats();
    } finally {
      if (mounted) setState(() => _sendingOrder = false);
    }
  }

  InputDecoration _moneyDecoration(String label, {Color? borderColor}) {
    final c = _accentColor(context);
    final b = OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(width: 1.6, color: c),
    );
    final fb = OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(width: 2.4, color: c),
    );
    return InputDecoration(
      labelText: label,
      prefixIcon: const Padding(
        padding: EdgeInsets.only(left: 16, right: 8),
        child: Text(
          '\$',
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
        ),
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      enabledBorder: b,
      border: b,
      focusedBorder: fb,
      contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 26),
    );
  }

  Widget _moneyFieldBig(
    TextEditingController c,
    String label, {
    bool enabled = true,
    Color? borderColor,
    Color? textColor,
  }) {
    return SizedBox(
      height: 74,
      child: TextField(
        controller: c,
        enabled: enabled,
        textAlignVertical: TextAlignVertical.center,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          color: textColor,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
        decoration: _moneyDecoration(label, borderColor: borderColor),
      ),
    );
  }

  Widget _paymentChoiceButton(_PaymentMethod m, IconData icon, String label) {
    final cs = Theme.of(context).colorScheme;
    final selected = _paymentMethod == m;

    return InkWell(
      onTap: () => setState(() {
        _paymentMethod = m;
        _onPaymentMethodChanged();
      }),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: selected
              ? cs.primaryContainer
              : cs.surfaceVariant.withOpacity(0.18),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? cs.primary : Colors.grey.shade400,
            width: selected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 28,
              color: selected ? cs.primary : Colors.grey.shade700,
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: selected ? cs.onPrimaryContainer : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Botonera con Confirmar/Cancelar y Reimprimir (x/2)
  Widget _paymentButtons() {
    String L(String es, String en) =>
        widget.lang == cfg.AppLanguage.es ? es : en;

    final canSend = !_sendingOrder && !_canReprint;
    final canReprint = _canReprint;

    // <<< colores por modo claro/oscuro >>>
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color reBg = isDark
        ? const Color(0xFF0B6FFF).withOpacity(0.12)
        : const Color(0xFFFFE6EA);
    final Color reFg = isDark
        ? const Color(0xFFA8D4F3)
        : const Color(0xFFD50000);
    final Color reBorder = isDark
        ? const Color(0xFF0B6FFF)
        : const Color(0xFFD50000);

    return Column(
      children: [
        const SizedBox(height: 18),

        // Confirmar
        SizedBox(
          width: double.infinity,
          height: 44,
          child: FilledButton(
            onPressed: canSend ? _submitOrder : null,
            child: _sendingOrder
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('Enviando...'),
                    ],
                  )
                : Text(L('Confirmar orden', 'Confirm order')),
          ),
        ),

        const SizedBox(height: 8),

        // Reimprimir (x/2)
        SizedBox(
          width: double.infinity,
          height: 44,
          child: OutlinedButton.icon(
            onPressed: canReprint ? _printAndMaybeFinalize : null,
            icon: const Icon(Icons.print),
            label: Text('Reimprimir ticket (${_reprintCount}/${_reprintMax})'),
            style: ButtonStyle(
              foregroundColor: MaterialStateProperty.resolveWith((states) {
                return states.contains(MaterialState.disabled)
                    ? reFg.withOpacity(0.4)
                    : reFg;
              }),
              backgroundColor: MaterialStateProperty.resolveWith((states) {
                return states.contains(MaterialState.disabled)
                    ? reBg.withOpacity(0.5)
                    : reBg;
              }),
              side: MaterialStateProperty.resolveWith((states) {
                final c = states.contains(MaterialState.disabled)
                    ? reBorder.withOpacity(0.4)
                    : reBorder;
                return BorderSide(color: c, width: 2);
              }),
            ),
          ),
        ),

        const SizedBox(height: 8),

        // Cancelar
        SizedBox(
          width: double.infinity,
          height: 44,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: canSend
                ? () async {
                    await _resetFlowAfterOrder();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Orden cancelada')),
                    );
                  }
                : null,
            child: Text(L('Cancelar orden', 'Cancel order')),
          ),
        ),
      ],
    );
  }

  Widget _paymentMethodBar() {
    return Row(
      children: [
        Expanded(
          child: _paymentChoiceButton(
            _PaymentMethod.cash,
            Icons.payments_outlined,
            tr('Efectivo'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _paymentChoiceButton(
            _PaymentMethod.card,
            Icons.credit_card,
            tr('Tarjeta'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _paymentChoiceButton(
            _PaymentMethod.mixed,
            Icons.merge_type,
            tr('Mixto'),
          ),
        ),
      ],
    );
  }

  Widget _paymentCard() {
    final cs = Theme.of(context).colorScheme;
    final totalFmt = _totalToCharge.toStringAsFixed(2);

    Color? _borderFromChangeForInput() => _changeValue < 0 ? Colors.red : null;
    Color _changeColor() => _changeValue < 0
        ? Colors.red
        : (_changeValue > 0 ? Colors.blue : Colors.green);

    Widget amountColumn() => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Monto a cobrar \$${totalFmt}',
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
      ],
    );

    Widget cashSection() => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr('cash_payment_title'),
          style: TextStyle(fontWeight: FontWeight.w900, color: cs.primary),
        ),
        const SizedBox(height: 12),
        amountColumn(),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _moneyFieldBig(
                _cashCtrl,
                tr('cash_received'),
                borderColor: _borderFromChangeForInput(),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _moneyFieldBig(
                _changeCtrl,
                tr('change_to_return'),
                enabled: false,
                borderColor: _borderFromChangeForInput(),
                textColor: _changeColor(),
              ),
            ),
          ],
        ),
        _paymentButtons(),
      ],
    );

    Widget cardSection() => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr('card_payment_title'),
          style: TextStyle(fontWeight: FontWeight.w900, color: cs.primary),
        ),
        const SizedBox(height: 12),
        amountColumn(),
        const SizedBox(height: 16),
        _moneyFieldBig(
          _cardCtrl,
          tr('card_received'),
          borderColor: _borderFromChangeForInput(),
        ),
        _paymentButtons(),
      ],
    );

    Widget mixedSection() => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr('mixed_payment_title'),
          style: TextStyle(fontWeight: FontWeight.w900, color: cs.primary),
        ),
        const SizedBox(height: 12),
        amountColumn(),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _moneyFieldBig(
                _cashCtrl,
                tr('cash_received'),
                borderColor: _borderFromChangeForInput(),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _moneyFieldBig(
                _changeCtrl,
                tr('change_to_return'),
                enabled: false,
                borderColor: _borderFromChangeForInput(),
                textColor: _changeColor(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _moneyFieldBig(
          _cardCtrl,
          tr('card_received'),
          borderColor: _borderFromChangeForInput(),
        ),
        _paymentButtons(),
      ],
    );

    Widget section() {
      switch (_paymentMethod) {
        case _PaymentMethod.cash:
          return cashSection();
        case _PaymentMethod.card:
          return cardSection();
        case _PaymentMethod.mixed:
          return mixedSection();
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 10),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  tr('pay_order_title'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                IconButton(
                  tooltip: widget.lang == cfg.AppLanguage.es
                      ? 'Ver resumen'
                      : 'View summary',
                  icon: const Icon(Icons.visibility_outlined),
                  onPressed: _showOrderSummaryDialog,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              tr('payment_method'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            _paymentMethodBar(),
            const SizedBox(height: 18),
            section(),
          ],
        ),
      ),
    );
  }

  String _money(dynamic v) {
    final d = (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;
    return d.toStringAsFixed(2);
  }

  Widget _seatIcon({
    required int number,
    required bool occ,
    required bool proc,
    required bool sel,
  }) {
    Color bg;
    Color fg;
    if (occ) {
      bg = _kColorOccupied;
      fg = Colors.white;
    } else if (proc) {
      bg = _kColorInProcess;
      fg = Colors.white;
    } else if (sel) {
      bg = _kColorSelected;
      fg = Colors.black;
    } else {
      bg = _kColorAvailable;
      fg = Colors.black87;
    }

    return Container(
      width: 48,
      height: 60,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(blurRadius: 3, color: Colors.black12, offset: Offset(0, 1)),
        ],
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_seat, size: 32, color: fg),
          const SizedBox(height: 2),
          Text(
            number.toString(),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _slot(Map<String, dynamic>? seat) {
    if (seat == null) return const SizedBox(width: 48, height: 60);
    final id = seat['id_seat'].toString();
    final n = (seat['number_seat'] ?? 0) as int;
    final occ = _isOccNum(n);
    final proc = _isProcNum(n);
    final sel = _isSelId(id);

    return InkWell(
      onTap: () => _toggleSeat(seat),
      borderRadius: BorderRadius.circular(10),
      child: _seatIcon(number: n, occ: occ, proc: proc, sel: sel),
    );
  }

  Widget _legend() {
    Widget line(Color c, String t) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Text(t, style: const TextStyle(fontSize: 14)),
      ],
    );
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        line(_kColorAvailable, tr('legend_available')),
        line(_kColorOccupied, tr('legend_occupied')),
        line(_kColorSelected, tr('legend_selected')),
        line(_kColorInProcess, tr('legend_in_process')),
      ],
    );
  }

  // Coloca esto en tu clase _SeatSelectionInlineState

  String _formatBannerDate(DateTime d) {
    const dias = [
      'lunes',
      'martes',
      'miércoles',
      'jueves',
      'viernes',
      'sábado',
      'domingo',
    ];
    const meses = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];
    return '${dias[d.weekday - 1]}, ${meses[d.month - 1]} ${d.day}, ${d.year}';
  }

  Widget _personalNameBanner() {
    final name = (_name?.isNotEmpty ?? false) ? _name! : '—';
    final dt = widget.travelDate ?? _now; // aseguras DateTime
    final fecha = _formatBannerDate(dt);
    final c = _accentColor(context);

    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: c.withOpacity(0.08),
        border: Border.all(color: c, width: 1.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: SelectableText(
        '$name - $fecha',
        style: TextStyle(color: c, fontWeight: FontWeight.w900),
      ),
    );
  }

  Widget _routePriceBanner() {
    if (_routePrice == null) return const SizedBox.shrink();
    final green = Colors.green[800];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.08),
        border: Border.all(color: Colors.green),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '${tr('price')}: \$${_money(_routePrice)}',
        style: TextStyle(color: green, fontWeight: FontWeight.w900),
      ),
    );
  }

  Widget _stepRelatedInfoRow() {
    if (_loadingStepRelated) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text(
              'Relación de escalas: cargando…',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
    }

    if (_stepRelatedErr != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Relación de escalas: error',
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w800,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'A=${widget.originStepId}  •  B=${widget.destinationStepId}',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 2),
            Text(
              'Detalle: ${_stepRelatedErr}',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
    }

    final text = _stepRelatedLabel ?? 'Relación de escalas: sin datos';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          const Icon(Icons.link, color: Colors.teal),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.teal,
                fontWeight: FontWeight.w800,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _plan(List<Map<String, dynamic>> seats) {
    final rows = _chunkRows(seats);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _accentColor(context), width: 6),
      ),
      child: Column(
        children: [
          for (final r in rows) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _slot(r[0]),
                const SizedBox(width: 14),
                _slot(r[1]),
                const SizedBox(width: 36),
                _slot(r[2]),
                const SizedBox(width: 14),
                _slot(r[3]),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Widget _discountSummaryChip(int index) {
    final d = _selectedDiscounts[index];
    if (d == null || _routePrice == null) return const SizedBox.shrink();
    final serviceCostLabel = tr('service_cost');
    final discountLabel = tr('discount');
    final finalCostLabel = tr('final_cost');
    final monto = d['monto_descuento'];
    final precioFinal = d['precio_final'];

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.08),
        border: Border.all(color: Colors.green),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.percent, color: Colors.green),
          const SizedBox(width: 8),
          Text(
            '$serviceCostLabel: \$${_money(_routePrice)}  •  $discountLabel: \$${_money(monto)}  •  $finalCostLabel: \$${_money(precioFinal)}',
            style: TextStyle(
              color: Colors.green[800],
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  // ======= NUEVOS HELPERS PARA UI ELEGANTE Y ASIENTO EN CHIP =======
  int? _seatNumForPassenger(int index) {
    final ids = _selectedSeatIds.toList()
      ..sort(
        (a, b) => (_seatNumberFromId(a) ?? 99999).compareTo(
          _seatNumberFromId(b) ?? 99999,
        ),
      );
    if (index >= ids.length) return null;
    return _seatNumberFromId(ids[index]);
  }

  InputDecoration _elegantDecoration({
    required String label,
    required IconData icon,
  }) {
    final cs = Theme.of(context).colorScheme;
    final c = _accentColor(context);

    final baseBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: c, width: 1.6),
    );

    return InputDecoration(
      labelText: label,
      prefixIcon: Container(
        margin: const EdgeInsets.only(left: 8, right: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cs.primary.withOpacity(0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: cs.primary),
      ),
      isDense: true,
      filled: true,
      fillColor: cs.surfaceVariant.withOpacity(0.12),
      enabledBorder: baseBorder,
      border: baseBorder,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c, width: 2.4),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    );
  }

  Widget _checkInCard(int index) {
    final f = _forms[index];

    Widget field(
      String label,
      IconData icon,
      TextEditingController c, {
      TextInputType? kt,
      bool readOnly = false,
    }) {
      return SizedBox(
        width: 260,
        child: TextField(
          controller: c,
          readOnly: readOnly,
          keyboardType: kt,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          decoration: _elegantDecoration(label: label, icon: icon),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 3,
      shadowColor: Colors.black.withOpacity(0.12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Encabezado con número de asiento
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${tr('checkin_title')} ${index + 1}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _accentColor(context),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.10),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.event_seat,
                        size: 18,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        (_seatNumForPassenger(index) ?? '—').toString(),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Campos de formulario
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                field(tr('first_names'), Icons.badge_outlined, f.nombres),
                field(tr('last_name_father'), Icons.badge, f.apPat),
                field(tr('last_name_mother'), Icons.badge, f.apMat),
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<String>(
                    value: f.tipo,
                    decoration: _elegantDecoration(
                      label: 'Tipo de pasajero',
                      icon: Icons.group_outlined,
                    ),
                    items: _passengerTypesI18n
                        .map(
                          (t) => DropdownMenuItem<String>(
                            value: t,
                            child: Text(t),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => f.tipo = v),
                  ),
                ),
                field(
                  tr('phone_number'),
                  Icons.phone_outlined,
                  f.phone,
                  kt: TextInputType.phone,
                ),
                field(tr('curp'), Icons.fingerprint_outlined, f.curp),
                field(tr('sex'), Icons.person, f.sexo, readOnly: true),
                field(tr('age'), Icons.cake_outlined, f.edad, readOnly: true),
              ],
            ),
            const SizedBox(height: 12),

            // Botones inferiores
            Row(
              children: [
                FilledButton(
                  onPressed: () => _validateCurpFor(index),
                  child: Text(tr('validate')),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => _dictateForPassenger(index),
                  icon: const Icon(Icons.mic),
                  label: Text(tr('dictate_data')),
                  style: _themedOutlinedStyle(context),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => _autoFillPassenger(index),
                  icon: const Icon(Icons.flash_auto),
                  label: Text(tr('autofill_form')),
                  style: _themedOutlinedStyle(context),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => _showDiscountsDialog(index),
                  icon: const Icon(Icons.percent),
                  label: Text(tr('view_discounts')),
                  style: _themedOutlinedStyle(context),
                ),
              ],
            ),

            _discountSummaryChip(index),
          ],
        ),
      ),
    );
  }

  Future<void> _dictateForPassenger(int index) async {
    final ok = await _stt.initialize(onStatus: (s) {}, onError: (e) {});
    if (!ok) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(tr('mic_unavailable'))));
      return;
    }

    await _stt.listen(
      localeId: widget.lang == cfg.AppLanguage.es ? 'es-MX' : 'en-US',
      listenFor: const Duration(seconds: 6),
      onResult: (res) {
        if (!mounted) return;
        final lastText = res.recognizedWords;
        if (res.finalResult) {
          _parseAndFill(lastText, index);
        }
      },
    );
    Future.delayed(const Duration(seconds: 7), () {
      if (mounted) _stt.stop();
    });
  }

  void _parseAndFill(String text, int index) {
    if (text.trim().isEmpty) return;
    final stop = {'de', 'del', 'la', 'las', 'los'};
    final tokens = text
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .where((w) => !stop.contains(w.toLowerCase()))
        .toList();

    final f = _forms[index];
    if (tokens.length == 1) {
      f.nombres.text = tokens[0];
    } else if (tokens.length == 2) {
      f.nombres.text = tokens[0];
      f.apPat.text = tokens[1];
    } else {
      f.apMat.text = tokens.last;
      f.apPat.text = tokens[tokens.length - 2];
      f.nombres.text = tokens.sublist(0, tokens.length - 2).join(' ');
    }
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(tr('dictated_data_loaded'))));
  }

  Future<void> _validateCurpFor(int index) async {
    final f = _forms[index];
    final curp = f.curp.text.trim().toUpperCase();

    if (curp.length != 18) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CURP debe tener 18 caracteres')),
      );
      return;
    }

    try {
      final resp = await http.post(
        Uri.parse(_VALIDATE_CURP_URL),
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'x-api-key': 'yacjDEIxyrZPgAZMh83yUAiP86Y256QNkyhuix5qSgP7LnTQ4S',
        },
        body: jsonEncode({
          'curp': curp,
          'currentDate': DateTime.now().toIso8601String(),
        }),
      );

      final data = jsonDecode(resp.body);

      if (resp.statusCode != 200 || data['success'] != true) {
        final msg = data['error'] ?? 'No se pudo validar la CURP';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
        return;
      }

      final int edad = (data['edad'] as num).toInt();
      final String sexo = '${data['sexo'] ?? ''}';

      String tipo;
      if (edad < 12) {
        tipo = tr('ptype_minor');
      } else if (edad >= 60) {
        tipo = tr('ptype_senior');
      } else {
        tipo = tr('ptype_adult');
      }

      setState(() {
        f.sexo.text = sexo;
        f.edad.text = edad.toString();
        f.tipo = tipo;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error de red al validar CURP: $e')),
      );
    }
  }

  Future<void> _autoFillPassenger(int index) async {
    _ensureForms();
    final f = _forms[index];
    final n = index + 1;
    final word = widget.lang == cfg.AppLanguage.es ? 'Pasajero' : 'Passenger';

    setState(() {
      f.nombres.text = '$word $n';
      f.apPat.text = '$word $n';
      f.apMat.text = '$word $n';
      f.phone.text = '1111111111';
      f.tipo = tr('ptype_adult');
    });

    await _saveAllPassengersToPrefs();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(tr('autofill_saved'))));
  }

  Future<void> _saveAllPassengersToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final data = List.generate(widget.passengers, (i) {
      final f = _forms[i];
      return {
        'nombres': f.nombres.text,
        'apPat': f.apPat.text,
        'apMat': f.apMat.text,
        'phone': f.phone.text,
        'curp': f.curp.text,
        'tipo': f.tipo,
      };
    });
    await prefs.setString('checkin_${widget.tripId}', jsonEncode(data));
  }

  Widget _checkInSection() {
    if (!_showCheckIn) return const SizedBox.shrink();
    _ensureForms();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        const Divider(),
        const SizedBox(height: 8),
        for (int i = 0; i < widget.passengers; i++) _checkInCard(i),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: () => setState(() {
              _showPayment = true;
              _onPaymentMethodChanged();
              _setProcessFromSelection(true);
            }),
            icon: const Icon(Icons.arrow_forward),
            label: Text(tr('continue_to_payment')),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_closed) return const SizedBox.shrink();

    final loaded = !_loadingSeats;
    if (_closed) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ExpansionTile(
        initiallyExpanded: _expanded,
        onExpansionChanged: (v) => setState(() => _expanded = v),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(tr('seat_select_title')),
        subtitle: Text('${tr('passengers_label')}: ${widget.passengers}'),
        children: [
          if (!loaded)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error.isNotEmpty)
            Padding(padding: const EdgeInsets.all(16), child: Text(_error))
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _personalNameBanner(),
                  _routePriceBanner(),
                  _stepRelatedInfoRow(),
                  const SizedBox(height: 12),
                  _legend(),
                  const SizedBox(height: 12),
                  if (_floor2.isNotEmpty)
                    SegmentedButton<int>(
                      segments: [
                        ButtonSegment(value: 1, label: Text(tr('floor_1'))),
                        ButtonSegment(value: 2, label: Text(tr('floor_2'))),
                      ],
                      selected: {_currentFloor},
                      onSelectionChanged: (s) =>
                          setState(() => _currentFloor = s.first),
                    ),
                  const SizedBox(height: 12),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      _plan(_currentFloor == 1 ? _floor1 : _floor2),
                      if (_loadingOcc)
                        Positioned.fill(
                          child: IgnorePointer(
                            ignoring: true,
                            child: const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${tr('selected_label')}: ${_selectedSeatIds.length} / ${widget.passengers}',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _fetchOccupiedSeats,
                        icon: const Icon(Icons.refresh),
                        label: Text(tr('refresh_occupancy')),
                        style: _themedOutlinedStyle(context),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _autoFillSeats,
                        icon: const Icon(Icons.auto_awesome),
                        label: Text(tr('autofill_seats')),
                        style: _themedOutlinedStyle(context),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: _selectedSeatIds.length == widget.passengers
                            ? () {
                                setState(() {
                                  _showCheckIn = true;
                                  _showPayment = false;
                                });
                                _ensureForms();
                                widget.onConfirmed?.call(
                                  _selectedSeatIds.toList(),
                                  _floor2.isNotEmpty ? 2 : 1,
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(tr('seats_confirmed')),
                                  ),
                                );
                              }
                            : null,
                        child: Text(tr('confirm_seats')),
                      ),
                    ],
                  ),
                  _checkInSection(),
                  if (_showPayment) ...[
                    const SizedBox(height: 8),
                    _paymentCard(),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// Pantalla completa
class SeatSelectionPage extends StatelessWidget {
  final String busId;
  final String tripId;
  final int passengers;
  final String originStepId; // UUID
  final String destinationStepId; // UUID

  final cfg.AppLanguage lang;

  final double? routeBasePrice;
  final String? idRoute;
  final String? idService;
  final String? serviceLabel;
  final String? nameRole;
  final String? idPersonalInLine;
  final String? name; // ← NOMBRE visible
  final String? paymentReference;
  final DateTime? travelDate;

  const SeatSelectionPage({
    super.key,
    required this.busId,
    required this.tripId,
    required this.passengers,
    required this.originStepId,
    required this.destinationStepId,
    this.lang = cfg.AppLanguage.es,
    this.routeBasePrice,
    this.idRoute,
    this.idService,
    this.serviceLabel,
    this.nameRole,
    this.idPersonalInLine,
    this.name,
    this.paymentReference,
    this.travelDate,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.AppLocalizations.t('seat_select_title', lang)),
      ),
      body: SeatSelectionInline(
        key: ValueKey('trip:${tripId}:${originStepId}:${destinationStepId}'),
        busId: busId,
        tripId: tripId,
        passengers: passengers,
        originStepId: originStepId,
        destinationStepId: destinationStepId,
        initiallyExpanded: true,
        occupiedApiBase:
            'https://api-ticket-6wly.onrender.com/process-aviable-seats-on-trip',
        onConfirmed: (seats, floors) {
          Navigator.pop(context, {'seats': seats, 'floorCount': floors});
        },
        lang: lang,
        routeBasePrice: routeBasePrice,
        idRoute: idRoute,
        idService: idService,
        serviceLabel: serviceLabel,
        nameRole: nameRole,
        idPersonalInLine: idPersonalInLine,
        name: name,
        paymentReference: paymentReference,
        travelDate: travelDate,
      ),
    );
  }
}

// https://api-ticket-6wly.onrender.com
