import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

/// Referencia a un evento creado en el calendario del dispositivo.
/// Permite actualizarlo/borrarlo después sin duplicar eventos.
typedef CalendarEventRef = ({String calendarId, String eventId});

/// Servicio para sincronizar recordatorios directamente con Google Calendar
/// y el calendario del dispositivo móvil.
class CalendarService {
  CalendarService._();
  static final CalendarService instance = CalendarService._();

  final DeviceCalendarPlugin _deviceCalendar = DeviceCalendarPlugin();

  static const _kSyncEnabled = 'calendar_sync_enabled';
  static const _kSelectedCalendarId = 'calendar_selected_id';
  static const _kSelectedCalendarName = 'calendar_selected_name';

  /// Indica si la sincronización con Google Calendar está activada en ajustes.
  Future<bool> isSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kSyncEnabled) ?? false;
  }

  /// Guarda la preferencia de sincronización.
  Future<void> setSyncEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSyncEnabled, enabled);
  }

  /// Nombre del calendario actualmente seleccionado o null.
  Future<String?> getSelectedCalendarName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kSelectedCalendarName);
  }

  /// Guarda el calendario elegido por el usuario.
  Future<void> setSelectedCalendar(String id, String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSelectedCalendarId, id);
    await prefs.setString(_kSelectedCalendarName, name);
  }

  /// Verifica si ya se cuenta con permisos concedidos.
  Future<bool> hasPermissions() async {
    try {
      final res = await _deviceCalendar.hasPermissions();
      return res.isSuccess && (res.data ?? false);
    } catch (e) {
      debugPrint('CalendarService hasPermissions error: $e');
      return false;
    }
  }

  /// Solicita permisos de acceso al calendario al sistema operativo.
  Future<bool> requestPermissions() async {
    try {
      final granted = await hasPermissions();
      if (granted) return true;
      final result = await _deviceCalendar.requestPermissions();
      return result.isSuccess && (result.data ?? false);
    } catch (e) {
      debugPrint('CalendarService requestPermissions error: $e');
      return false;
    }
  }

  /// Devuelve la lista de calendarios disponibles y editables.
  Future<List<Calendar>> getAvailableCalendars() async {
    try {
      final hasPerm = await requestPermissions();
      if (!hasPerm) return [];

      final result = await _deviceCalendar.retrieveCalendars();
      if (!result.isSuccess || result.data == null) return [];

      return result.data!.where((c) => !(c.isReadOnly ?? false)).toList();
    } catch (e) {
      debugPrint('CalendarService getAvailableCalendars error: $e');
      return [];
    }
  }

  /// Obtiene el calendario configurado o el mejor calendario de Google disponible.
  Future<Calendar?> getActiveCalendar() async {
    try {
      final calendars = await getAvailableCalendars();
      if (calendars.isEmpty) return null;

      final prefs = await SharedPreferences.getInstance();
      final savedId = prefs.getString(_kSelectedCalendarId);

      // Si el usuario seleccionó uno previamente
      if (savedId != null) {
        final found = calendars.where((c) => c.id == savedId).firstOrNull;
        if (found != null) return found;
      }

      // 1. Intentar encontrar calendario de Google editable
      final googleCal = calendars.where((c) =>
          ((c.accountType?.toLowerCase().contains('google') ?? false) ||
           (c.accountName?.toLowerCase().contains('@gmail.com') ?? false) ||
           (c.name?.toLowerCase().contains('google') ?? false))).firstOrNull;

      if (googleCal != null) {
        await setSelectedCalendar(googleCal.id ?? '', googleCal.name ?? 'Google Calendar');
        return googleCal;
      }

      // 2. Intentar calendario por defecto
      final defaultCal = calendars.where((c) => (c.isDefault ?? false)).firstOrNull;
      if (defaultCal != null) {
        await setSelectedCalendar(defaultCal.id ?? '', defaultCal.name ?? 'Calendario Principal');
        return defaultCal;
      }

      // 3. Primer calendario disponible
      final firstCal = calendars.first;
      await setSelectedCalendar(firstCal.id ?? '', firstCal.name ?? 'Calendario');
      return firstCal;
    } catch (e) {
      debugPrint('CalendarService getActiveCalendar error: $e');
      return null;
    }
  }

  /// Crea o actualiza un evento con notificación en Google Calendar.
  ///
  /// Devuelve la referencia (calendarId + eventId) para que el caller
  /// pueda persistirla y reutilizarla (evita duplicados al editar y
  /// permite borrar el evento cuando se elimina la tarea).
  Future<CalendarEventRef?> syncReminderEvent({
    required String title,
    required DateTime reminderTime,
    String? description,
    String? existingEventId,
    String? existingCalendarId,
  }) async {
    try {
      final enabled = await isSyncEnabled();
      if (!enabled) return null;

      // Si conocemos el calendario original del evento, lo reutilizamos
      // (el usuario pudo haber cambiado el calendario activo desde entonces).
      final calendar = await getActiveCalendar();
      if (calendar == null || calendar.id == null) return null;
      final targetCalendarId = existingCalendarId ?? calendar.id!;

      final isAllDay = reminderTime.hour == 0 && reminderTime.minute == 0;
      final start = tz.TZDateTime.from(
        isAllDay
            ? DateTime(reminderTime.year, reminderTime.month, reminderTime.day, 9, 0)
            : reminderTime,
        tz.local,
      );
      final end = start.add(Duration(minutes: isAllDay ? 60 : 30));

      final event = Event(
        targetCalendarId,
        eventId: existingEventId,
        title: '🎯 $title',
        description: description ?? 'Recordatorio de tarea programada en Slay',
        start: start,
        end: end,
        allDay: isAllDay,
        reminders: [
          Reminder(minutes: 0), // Notificación a la hora exacta
          Reminder(minutes: 10), // Alerta previa
        ],
      );

      final createResult = await _deviceCalendar.createOrUpdateEvent(event);
      if (createResult != null && createResult.isSuccess) {
        debugPrint('CalendarService: Evento creado exitosamente en Google Calendar: ${createResult.data}');
        return (
          calendarId: targetCalendarId,
          eventId: createResult.data!,
        );
      } else {
        debugPrint('CalendarService: Fallo createOrUpdateEvent: ${createResult?.errors.map((e) => e.errorMessage).join(', ')}');
      }
    } catch (e) {
      debugPrint('CalendarService syncReminderEvent error: $e');
    }
    return null;
  }

  /// Elimina un evento de recordatorio del calendario si existe.
  ///
  /// Si se pasa [calendarId] se usa ese calendario directamente; si no,
  /// se usa el calendario activo actual.
  Future<bool> deleteReminderEvent(String? eventId, {String? calendarId}) async {
    if (eventId == null || eventId.isEmpty) return false;
    try {
      final calId = calendarId ?? (await getActiveCalendar())?.id;
      if (calId == null) return false;

      final deleteResult = await _deviceCalendar.deleteEvent(calId, eventId);
      return deleteResult.isSuccess && (deleteResult.data ?? false);
    } catch (e) {
      debugPrint('CalendarService deleteReminderEvent error: $e');
      return false;
    }
  }

  /// Crea un recordatorio de prueba para verificar la conexión (en 2 minutos).
  Future<bool> createTestReminder() async {
    final now = DateTime.now().add(const Duration(minutes: 2));
    final ref = await syncReminderEvent(
      title: 'Prueba de Recordatorio Slay',
      reminderTime: now,
      description: 'Si ves esta notificación, la sincronización con Google Calendar funciona perfecto!',
    );
    return ref != null;
  }
}