import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/task.dart';
import 'calendar_service.dart';
import 'local_notifications.dart';

/// Gestor unificado de recordatorios.
/// Combina las notificaciones locales con la sincronización directa en Google Calendar
/// para garantizar alertas precisas incluso en dispositivos con optimizaciones agresivas de batería (como Xiaomi/Redmi).
class ReminderManager {
  ReminderManager._();
  static final ReminderManager instance = ReminderManager._();

  int _notifId(String taskId) => taskId.hashCode.abs() % 2147483647;

  // ── Persistencia local del evento de calendario por tarea ──
  //
  // El plugin `device_calendar` es local al dispositivo, así que el
  // mapeo taskId → (calendarId, eventId) vive en SharedPreferences.
  // Con esto podemos:
  //  - Actualizar el MISMO evento al editar la tarea (sin duplicados).
  //  - Borrar el evento cuando la tarea se elimina o se completa.
  static const _kEventPrefix = 'calendar_task_event_';
  static const _kCalendarPrefix = 'calendar_task_calendar_';

  Future<String?> _getStoredEventId(String taskId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_kEventPrefix$taskId');
  }

  Future<String?> _getStoredCalendarId(String taskId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_kCalendarPrefix$taskId');
  }

  Future<void> _storeEventRef(String taskId, CalendarEventRef ref) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_kEventPrefix$taskId', ref.eventId);
    await prefs.setString('$_kCalendarPrefix$taskId', ref.calendarId);
  }

  Future<void> _clearEventRef(String taskId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_kEventPrefix$taskId');
    await prefs.remove('$_kCalendarPrefix$taskId');
  }

  /// Programa el recordatorio en el calendario de Google y en las notificaciones locales.
  Future<void> scheduleTaskReminder(Task task) async {
    final reminder = task.reminder;
    if (reminder == null) {
      await cancelTaskReminder(task.id);
      return;
    }

    final notifId = _notifId(task.id);

    // 1. Google Calendar / Calendario nativo
    try {
      final syncEnabled = await CalendarService.instance.isSyncEnabled();
      final existingEventId =
          syncEnabled ? await _getStoredEventId(task.id) : null;
      if (existingEventId != null) {
        // Ya existe un evento para esta tarea → actualizarlo en su
        // calendario original (evita duplicados al editar).
        final ref = await CalendarService.instance.syncReminderEvent(
          title: task.title,
          reminderTime: reminder,
          description: 'Tarea programada en Slay',
          existingEventId: existingEventId,
          existingCalendarId: await _getStoredCalendarId(task.id),
        );
        if (ref != null) {
          await _storeEventRef(task.id, ref);
        } else {
          // El evento ya no existe (lo borraron a mano) o falló el update:
          // limpiar el mapeo para que el próximo intento cree uno nuevo.
          await _clearEventRef(task.id);
        }
      } else if (syncEnabled) {
        final ref = await CalendarService.instance.syncReminderEvent(
          title: task.title,
          reminderTime: reminder,
          description: 'Tarea programada en Slay',
        );
        if (ref != null) {
          await _storeEventRef(task.id, ref);
        }
      }
    } catch (_) {
      // Si falla el calendario igual programamos la notificación local.
    }

    // 2. Notificación local si está en el futuro
    if (reminder.isAfter(DateTime.now())) {
      await LocalNotifications.instance.scheduleReminder(
        id: notifId,
        title: 'Recordatorio: ${task.title}',
        body: 'Es hora de realizar tu tarea pendiente en Slay.',
        when: reminder,
      );
    }
  }

  /// Cancela el recordatorio local Y elimina el evento del calendario.
  ///
  /// Se llama al eliminar una tarea, al completarla o al quitarle el
  /// recordatorio — en todos los casos el evento del calendario ya no
  /// debe quedar huérfano.
  Future<void> cancelTaskReminder(String taskId) async {
    final notifId = _notifId(taskId);
    await LocalNotifications.instance.cancel(notifId);

    try {
      final eventId = await _getStoredEventId(taskId);
      if (eventId != null) {
        await CalendarService.instance.deleteReminderEvent(
          eventId,
          calendarId: await _getStoredCalendarId(taskId),
        );
        await _clearEventRef(taskId);
      }
    } catch (_) {
      // Nunca bloquear el flujo de borrado/completado por un fallo del calendario.
    }
  }
}