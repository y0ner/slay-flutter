import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'app.dart';
import 'core/supabase/supabase_config.dart';
import 'notifications/local_notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializa la base de datos de zonas horarias.
  tz_data.initializeTimeZones();
  try {
    tz.setLocalLocation(tz.getLocation(await FlutterTimezone.getLocalTimezone()));
  } catch (_) {
    // Si falla, queda UTC. Los recordatorios seguirán funcionando.
  }

  // Inicializa los datos de localización de intl (necesario para
  // formatear fechas en español con `DateFormat('EEEE', 'es_ES')`).
  await initializeDateFormatting('es_ES', null);

  // Inicializa Supabase.
  if (SupabaseConfig.isConfigured) {
    // ignore: deprecated_member_use
    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );
  }

  // Inicializa notificaciones locales.
  await LocalNotifications.instance.init();

  runApp(const ProviderScope(child: SlayApp()));
}
