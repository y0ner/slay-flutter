import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// Wrapper sobre `flutter_local_notifications` que centraliza
/// el scheduling, la cancelación y la inicialización multiplataforma.
///
/// En Android, Linux y Windows los recordatorios funcionan
/// de forma idéntica a como lo hacían con `AlarmManager.setAlarmClock`.
class LocalNotifications {
  LocalNotifications._();
  static final LocalNotifications instance = LocalNotifications._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Inicializa el plugin con los canales y opciones para cada plataforma.
  Future<void> init() async {
    if (_initialized) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const linuxInit = LinuxInitializationSettings(
      defaultActionName: 'Abrir',
    );
    const settings = InitializationSettings(
      android: androidInit,
      linux: linuxInit,
    );

    try {
      await _plugin.initialize(settings);
      _initialized = true;
    } catch (e) {
      debugPrint('LocalNotifications init falló: $e');
    }
  }

  /// Solicita permiso para mostrar notificaciones (Android 13+ y similares).
  Future<bool> requestPermission() async {
    final android =
        _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final granted = await android.requestNotificationsPermission();
      return granted ?? false;
    }
    return true; // En otras plataformas asumimos concedido.
  }

  /// Programa un recordatorio.
  ///
  /// Si la hora ya pasó, no agenda nada y devuelve false.
  Future<bool> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    if (!_initialized) await init();
    if (when.isBefore(DateTime.now())) return false;

    final scheduled = tz.TZDateTime.from(when, tz.local);

    const androidDetails = AndroidNotificationDetails(
      'slay_reminders',
      'Recordatorios',
      channelDescription: 'Recordatorios de tareas programadas.',
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
    );
    const linuxDetails = LinuxNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      linux: linuxDetails,
    );

    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      return true;
    } catch (e) {
      debugPrint('scheduleReminder falló: $e');
      return false;
    }
  }

  Future<void> cancel(int id) => _plugin.cancel(id);
  Future<void> cancelAll() => _plugin.cancelAll();

  /// Programa una notificación para el fin de un pomodoro. Si el
  /// momento ya pasó, devuelve false sin agendar.
  ///
  /// Usa un canal separado ("Pomodoro") para no mezclarse con
  /// recordatorios. El id debe ser único por sesión activa (la app
  /// usa un id estable derivado del taskId para poder cancelarlo).
  Future<bool> scheduleSessionEnd({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    if (!_initialized) await init();
    if (when.isBefore(DateTime.now())) return false;

    final scheduled = tz.TZDateTime.from(when, tz.local);

    const androidDetails = AndroidNotificationDetails(
      'slay_pomodoro',
      'Pomodoro',
      channelDescription: 'Avisos cuando termina un pomodoro.',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(
      android: androidDetails,
      linux: LinuxNotificationDetails(),
    );

    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      return true;
    } catch (e) {
      debugPrint('scheduleSessionEnd falló: $e');
      return false;
    }
  }
}
