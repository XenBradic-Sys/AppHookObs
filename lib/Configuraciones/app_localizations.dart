//lib/Configuraciones/app_localizations.dart
import 'settings_controller.dart';

class AppLocalizations {
  static final Map<String, Map<AppLanguage, String>> _localizedValues = {
    // ==== Ajustes / UI base ====
    'settings': {AppLanguage.es: 'Configuración', AppLanguage.en: 'Settings'},
    'language': {AppLanguage.es: 'Idioma', AppLanguage.en: 'Language'},
    'theme': {AppLanguage.es: 'Tema', AppLanguage.en: 'Theme'},
    'light': {AppLanguage.es: 'Claro', AppLanguage.en: 'Light'},
    'blueDark': {AppLanguage.es: 'Modo Oscuro', AppLanguage.en: 'Dark Mode'},
    'Dark': {AppLanguage.es: 'Modo Oscuro', AppLanguage.en: 'Dark Mode'},
    'spanish': {AppLanguage.es: 'Español', AppLanguage.en: 'Spanish'},
    'english': {AppLanguage.es: 'Inglés', AppLanguage.en: 'English'},
    'change_language': {
      AppLanguage.es: 'Cambiar idioma de la app',
      AppLanguage.en: 'Change app language',
    },
    'change_theme': {
      AppLanguage.es: 'Cambiar tema (claro/oscuro)',
      AppLanguage.en: 'Change theme (light/dark)',
    },
    'logout': {AppLanguage.es: 'Cerrar sesión', AppLanguage.en: 'Logout'},
    'welcome': {AppLanguage.es: 'Bienvenido', AppLanguage.en: 'Welcome'},
    'full_name': {
      AppLanguage.es: 'Nombre Completo',
      AppLanguage.en: 'Full Name',
    },
    'role': {AppLanguage.es: 'Rol', AppLanguage.en: 'Role'},
    'office': {AppLanguage.es: 'Oficina', AppLanguage.en: 'Office'},
    'operator': {AppLanguage.es: 'Operador', AppLanguage.en: 'Operator'},

    // ==== Historial / Decline ====
    'history_title': {
      AppLanguage.es: 'Historial de Boletos',
      AppLanguage.en: 'Tickets History',
    },
    'no_history': {
      AppLanguage.es: 'No hay historial para hoy.',
      AppLanguage.en: 'No history for today.',
    },
    'decline_title': {
      AppLanguage.es: 'Registrar Descenso',
      AppLanguage.en: 'Register Decline',
    },
    'decline_success': {
      AppLanguage.es: 'Descenso registrado',
      AppLanguage.en: 'Decline registered',
    },
    'decline_instructions': {
      AppLanguage.es:
          '1. Enfoque el código QR del boleto\n'
          '2. Espere a que se detecte automáticamente\n'
          '3. Revise la información del pasajero\n'
          '4. Confirme el registro de descenso',
      AppLanguage.en:
          '1. Point the camera at the ticket QR code\n'
          '2. Wait for auto-detection\n'
          '3. Review passenger info\n'
          '4. Confirm decline registration',
    },
    'confirm_decline': {
      AppLanguage.es: 'Confirmar Descenso',
      AppLanguage.en: 'Confirm Decline',
    },
    'passenger_already_declined': {
      AppLanguage.es: 'El pasajero ya registró su descenso',
      AppLanguage.en: 'Passenger already registered decline',
    },
    'passenger_not_boarded': {
      AppLanguage.es: 'El pasajero aún no ha abordado',
      AppLanguage.en: 'Passenger has not boarded yet',
    },
    'decline_scanner': {
      AppLanguage.es: 'Escáner Descenso',
      AppLanguage.en: 'Decline Scanner',
    },
    'passenger_name': {AppLanguage.es: 'Pasajero', AppLanguage.en: 'Passenger'},
    'route_name': {AppLanguage.es: 'Ruta', AppLanguage.en: 'Route'},
    'seat_number': {AppLanguage.es: 'Asiento', AppLanguage.en: 'Seat'},
    'status': {AppLanguage.es: 'Estado', AppLanguage.en: 'Status'},
    'boarded': {AppLanguage.es: 'Abordó', AppLanguage.en: 'Boarded'},
    'declined': {AppLanguage.es: 'Descendió', AppLanguage.en: 'Declined'},
    'yes': {AppLanguage.es: 'Sí', AppLanguage.en: 'Yes'},
    'no': {AppLanguage.es: 'No', AppLanguage.en: 'No'},

    // ==== Venta / mapa ====
    'sale': {AppLanguage.es: 'Venta', AppLanguage.en: 'Sale'},
    'your_location': {
      AppLanguage.es: 'Tu ubicación:',
      AppLanguage.en: 'Your location:',
    },
    'getting_location': {
      AppLanguage.es: 'Obteniendo ubicación...',
      AppLanguage.en: 'Getting location...',
    },
    'location_disabled': {
      AppLanguage.es: 'Ubicación deshabilitada',
      AppLanguage.en: 'Location disabled',
    },
    'location_denied': {
      AppLanguage.es: 'Permiso de ubicación denegado',
      AppLanguage.en: 'Location permission denied',
    },
    'here_you_are': {
      AppLanguage.es: 'Aquí estás',
      AppLanguage.en: 'You are here',
    },
    'select_trip': {
      AppLanguage.es: 'Selecciona tu viaje',
      AppLanguage.en: 'Select your trip',
    },
    'no_tno_tripsrips': {
      AppLanguage.es: 'No hay viajes disponibles',
      AppLanguage.en: 'No trips available',
    },
    'route_name_dup': {
      AppLanguage.es: 'Nombre de ruta',
      AppLanguage.en: 'Route name',
    },
    'departure': {
      AppLanguage.es: 'Fecha/hora de salida',
      AppLanguage.en: 'Departure date/time',
    },
    'city_not_found': {
      AppLanguage.es: 'Ciudad no encontrada',
      AppLanguage.en: 'City not found',
    },
    'refresh': {AppLanguage.es: 'Actualizar', AppLanguage.en: 'Refresh'},
    'expand': {AppLanguage.es: 'Expandir mapa', AppLanguage.en: 'Expand map'},
    'collapse': {
      AppLanguage.es: 'Colapsar mapa',
      AppLanguage.en: 'Collapse map',
    },
    'select_terminal': {
      AppLanguage.es: 'Selecciona terminal',
      AppLanguage.en: 'Select terminal',
    },
    'no_trips': {
      AppLanguage.es: 'No hay viajes disponibles',
      AppLanguage.en: 'No trips available',
    },

    // ==== Selección de asientos ====
    'seat_select_title': {
      AppLanguage.es: 'Selecciona tus asientos',
      AppLanguage.en: 'Select your seats',
    },
    'passengers_label': {
      AppLanguage.es: 'Pasajeros',
      AppLanguage.en: 'Passengers',
    },
    'selected_label': {
      AppLanguage.es: 'Seleccionados',
      AppLanguage.en: 'Selected',
    },
    'legend_available': {
      AppLanguage.es: 'Disponible',
      AppLanguage.en: 'Available',
    },
    'legend_occupied': {AppLanguage.es: 'Ocupado', AppLanguage.en: 'Occupied'},
    'legend_selected': {
      AppLanguage.es: 'Seleccionado',
      AppLanguage.en: 'Selected',
    },
    'legend_in_process': {
      AppLanguage.es: 'En proceso',
      AppLanguage.en: 'In process',
    },
    'floor_1': {AppLanguage.es: 'Piso 1', AppLanguage.en: 'Floor 1'},
    'floor_2': {AppLanguage.es: 'Piso 2', AppLanguage.en: 'Floor 2'},
    'refresh_occupancy': {
      AppLanguage.es: 'Actualizar ocupación',
      AppLanguage.en: 'Refresh occupancy',
    },
    'autofill_seats': {
      AppLanguage.es: 'Llenar auto',
      AppLanguage.en: 'Auto-fill',
    },
    'view_discounts': {
      AppLanguage.es: 'Ver descuentos',
      AppLanguage.en: 'View discounts',
    },
    'confirm_seats': {
      AppLanguage.es: 'Confirmar asientos',
      AppLanguage.en: 'Confirm seats',
    },
    'seats_confirmed': {
      AppLanguage.es: 'Asientos confirmados',
      AppLanguage.en: 'Seats confirmed',
    },
    'seat_unavailable': {
      AppLanguage.es: 'Ese asiento no está disponible',
      AppLanguage.en: 'That seat is not available',
    },
    'max_seats_reached': {
      AppLanguage.es: 'Máximo de asientos alcanzado',
      AppLanguage.en: 'Maximum seats reached',
    },
    'no_seats_to_fill': {
      AppLanguage.es: 'No hay asientos disponibles para llenar',
      AppLanguage.en: 'No available seats to fill',
    },
    'seats_added': {
      AppLanguage.es: 'Se añadieron asientos disponibles',
      AppLanguage.en: 'Available seats were added',
    },
    'mic_unavailable': {
      AppLanguage.es: 'Micrófono no disponible',
      AppLanguage.en: 'Microphone not available',
    },
    'dictated_data_loaded': {
      AppLanguage.es: 'Datos dictados cargados',
      AppLanguage.en: 'Dictated data loaded',
    },

    // ==== Descuentos (encabezados solicitados) ====
    'discounts_title': {
      AppLanguage.es: 'Descuentos disponibles',
      AppLanguage.en: 'Available discounts',
    },
    'no_discounts': {
      AppLanguage.es: 'No hay descuentos disponibles.',
      AppLanguage.en: 'No discounts available.',
    },
    'apply_discount': {
      AppLanguage.es: 'Descuentos',
      AppLanguage.en: 'Discounts',
    },
    // NUEVOS labels:
    'price': {AppLanguage.es: 'Precio', AppLanguage.en: 'Price'},
    'service_cost': {
      AppLanguage.es: 'Costo de servicio',
      AppLanguage.en: 'Service cost',
    },
    'discount': {AppLanguage.es: 'Descuento', AppLanguage.en: 'Discount'},
    'final_cost': {AppLanguage.es: 'Costo final', AppLanguage.en: 'Final cost'},

    // ==== Check-in ====
    'checkin_title': {
      AppLanguage.es: 'Check-in Pasajero',
      AppLanguage.en: 'Passenger Check-in',
    },
    'seat_outbound_label': {
      AppLanguage.es: 'Asiento ida pasajero',
      AppLanguage.en: 'Outbound seat passenger',
    },
    'first_names': {
      AppLanguage.es: 'Nombre(s)',
      AppLanguage.en: 'First name(s)',
    },
    'last_name_father': {
      AppLanguage.es: 'Apellido paterno',
      AppLanguage.en: 'Paternal last name',
    },
    'last_name_mother': {
      AppLanguage.es: 'Apellido materno',
      AppLanguage.en: 'Maternal last name',
    },
    'passenger_type': {
      AppLanguage.es: 'Tipo pasajero',
      AppLanguage.en: 'Passenger type',
    },
    'phone_number': {
      AppLanguage.es: 'Número de teléfono',
      AppLanguage.en: 'Phone number',
    },
    'curp': {AppLanguage.es: 'CURP', AppLanguage.en: 'CURP'},
    'validate': {AppLanguage.es: 'Validar', AppLanguage.en: 'Validate'},
    'dictate_data': {
      AppLanguage.es: 'Dictar datos',
      AppLanguage.en: 'Dictate data',
    },
    'sex': {AppLanguage.es: 'Sexo', AppLanguage.en: 'Sex'},
    'age': {AppLanguage.es: 'Edad', AppLanguage.en: 'Age'},

    // Tipos de pasajero
    'ptype_minor': {AppLanguage.es: 'Menor de edad', AppLanguage.en: 'Minor'},
    'ptype_adult': {AppLanguage.es: 'Adulto', AppLanguage.en: 'Adult'},
    'ptype_senior': {AppLanguage.es: 'Adulto mayor', AppLanguage.en: 'Senior'},

    // ==== Pago ====
    'pay_order_title': {
      AppLanguage.es: 'Pagar orden',
      AppLanguage.en: 'Pay order',
    },
    'payment_method': {
      AppLanguage.es: 'Método de pago',
      AppLanguage.en: 'Payment method',
    },
    'Efectivo': {AppLanguage.es: 'Efectivo', AppLanguage.en: 'Cash'},
    'Tarjeta': {AppLanguage.es: 'Tarjeta', AppLanguage.en: 'Card'},
    'Mixto': {AppLanguage.es: 'Mixto', AppLanguage.en: 'Mixed'},
    'cash_payment_title': {
      AppLanguage.es: 'Pago en efectivo',
      AppLanguage.en: 'Cash payment',
    },
    'card_payment_title': {
      AppLanguage.es: 'Pago en tarjeta',
      AppLanguage.en: 'Card payment',
    },
    'mixed_payment_title': {
      AppLanguage.es: 'Pago en mixto',
      AppLanguage.en: 'Mixed payment',
    },
    'amount_to_charge': {
      AppLanguage.es: 'Monto a cobrar',
      AppLanguage.en: 'Amount to charge',
    },
    'cash_received': {
      AppLanguage.es: 'Efectivo recibido',
      AppLanguage.en: 'Cash received',
    },
    'change_to_return': {
      AppLanguage.es: 'Cambio a regresar',
      AppLanguage.en: 'Change to return',
    },
    'card_received': {
      AppLanguage.es: 'Monto en tarjeta recibido',
      AppLanguage.en: 'Card amount received',
    },
    'confirm_order': {
      AppLanguage.es: 'Confirmar orden',
      AppLanguage.en: 'Confirm order',
    },
    'cancel_order': {
      AppLanguage.es: 'Cancelar orden',
      AppLanguage.en: 'Cancel order',
    },

    // ==== Resumen / precios por pasajero ====
    'passenger': {AppLanguage.es: 'Pasajero', AppLanguage.en: 'Passenger'},
    'fare_origin_fee': {
      AppLanguage.es: 'Cuota de servicio origen',
      AppLanguage.en: 'Origin service fare',
    },
    'selected_seat_origin': {
      AppLanguage.es: 'Asiento seleccionado origen',
      AppLanguage.en: 'Selected seat (origin)',
    },
    'no_base_price': {
      AppLanguage.es: 'No hay precio base disponible',
      AppLanguage.en: 'No base price available',
    },

    // Botones auxiliares
    'autofill_form': {
      AppLanguage.es: 'Llenar automáticamente',
      AppLanguage.en: 'Auto-fill',
    },
    'autofill_saved': {
      AppLanguage.es: 'Formulario autollenado y guardado',
      AppLanguage.en: 'Form auto-filled & saved',
    },
    'continue_to_payment': {
      AppLanguage.es: 'Continuar a pago',
      AppLanguage.en: 'Continue to payment',
    },
    // Encabezados de la tabla de descuentos
    'type_label': {AppLanguage.es: 'Tipo', AppLanguage.en: 'Type'},
    'value_label': {AppLanguage.es: 'Valor', AppLanguage.en: 'Value'},
    'type_value_label': {
      AppLanguage.es: 'Tipo de valor',
      AppLanguage.en: 'Type of value',
    },

    // Snackbar al aplicar
    'discount_applied': {
      AppLanguage.es: 'Descuento aplicado',
      AppLanguage.en: 'Discount applied',
    },

    // lib/Configuraciones/app_localizations.dart
    'id_personal_in_line': {
      AppLanguage.es: 'ID Personal En Línea',
      AppLanguage.en: 'Personal ID In Line',
    },
  };

  static String t(String key, AppLanguage lang) {
    return _localizedValues[key]?[lang] ?? key;
  }
}
