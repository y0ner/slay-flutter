import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'app.dart';
import 'core/supabase/supabase_config.dart';

/// Inicialización de Slay. Optimizada para reducir el TTI (time-to-interactive)
/// del cold start.
///
/// Antes (lento): 5 awaits secuenciales → tz_data (~50ms) + FlutterTimezone
/// (~30ms) + intl (~50ms) + Supabase (~50-100ms) + LocalNotifications
/// (~100-300ms) + runApp. **Total: ~300-530ms antes del primer frame**.
///
/// Ahora (paralelo + lazy):
/// 1. `WidgetsFlutterBinding.ensureInitialized` — sync, ~instantáneo.
/// 2. `tz_data.initializeTimeZones` — sync, ~50ms (carga ~500KB de zonas).
/// 3. `Future.wait` corre en paralelo:
///    - `initializeDateFormatting('es_ES', null)` (~50ms)
///    - `FlutterTimezone.getLocalTimezone()` + `setLocalLocation` (~30ms)
///    - `Supabase.initialize(...)` (~50-100ms)
///    LocalNotifications NO se inicializa acá — su `init()` crea canales
///    nativos de Android (NotificationManager) y cuesta ~100-300ms. Como
///    solo se necesita cuando se programa el primer recordatorio, el
///    wrapper ya hace lazy-init antes de la primera operación
///    (ver `LocalNotifications.scheduleReminder` / `scheduleSessionEnd`).
///
/// Con paralelización el wall-clock baja a ~max(50, 50, 30, 100) ≈ 100ms
/// en vez de la suma. **Ahorro neto: ~200-430ms.**
///
/// Hay timeout defensivo de 4s: si algún plugin nativo se cuelga
/// (caso real visto en Pixel viejos), continuamos con runApp igual
/// para no quedar atrapados en splash infinito.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1) Zona horaria — sync (necesario antes de getLocation).
  tz_data.initializeTimeZones();

  // 2) Init en paralelo.
  final timezoneFuture = FlutterTimezone.getLocalTimezone()
      .then<void>((name) {
    try {
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      // Fallback a UTC si la zona del sistema no existe en la DB.
    }
  }).catchError((_) {
    // Sin timezone del sistema → UTC. Los recordatorios siguen funcionando.
  });

  final inits = <Future<void>>[
    // Locale data — necesario para `DateFormat('EEEE', 'es_ES')`.
    initializeDateFormatting('es_ES', null),
    // TZ locale — paralelo al intl.
    timezoneFuture,
    // Supabase — abre cliente HTTP, prepara auth stream.
    if (SupabaseConfig.isConfigured)
      // ignore: deprecated_member_use
      Supabase.initialize(
        url: SupabaseConfig.url,
        anonKey: SupabaseConfig.anonKey,
      )
    else
      Future<void>.value(),
    // LocalNotifications NO se inicializa acá (lazy).
  ];

  try {
    await Future.wait(inits).timeout(
      const Duration(seconds: 4),
      onTimeout: () {
        debugPrint('main: init timeout (4s) — continuando con runApp igual');
        return <void>[];
      },
    );
  } catch (e) {
    debugPrint('main: init error: $e — continuando con runApp igual');
  }

  runApp(const ProviderScope(child: SlayApp()));
}
