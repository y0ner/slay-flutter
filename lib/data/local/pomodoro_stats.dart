import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Estado de las estadísticas persistidas del Pomodoro.
///
/// - `today`: contador que se resetea automáticamente cuando cambia
///   la fecha (comparado contra `todayDate`).
/// - `perTask`: mapa `taskId → cantidad` para mostrar en TaskCard y
///   en futuras estadísticas por tarea.
/// - `autoComplete`: preferencia para auto-marcar la tarea como
///   completada al terminar el pomodoro de trabajo (sin diálogo).
///
/// Todo se persiste en SharedPreferences; sobrevive cierres de app.
class PomodoroStatsState {
  const PomodoroStatsState({
    required this.today,
    required this.todayDate,
    required this.perTask,
    required this.autoComplete,
    required this.isLoaded,
  });

  final int today;
  final String todayDate;
  final Map<String, int> perTask;
  final bool autoComplete;
  final bool isLoaded;

  PomodoroStatsState copyWith({
    int? today,
    String? todayDate,
    Map<String, int>? perTask,
    bool? autoComplete,
  }) {
    return PomodoroStatsState(
      today: today ?? this.today,
      todayDate: todayDate ?? this.todayDate,
      perTask: perTask ?? this.perTask,
      autoComplete: autoComplete ?? this.autoComplete,
      isLoaded: true,
    );
  }
}

class PomodoroStats extends Notifier<PomodoroStatsState> {
  static const _kToday = 'pomodoro.today';
  static const _kTodayDate = 'pomodoro.today.date';
  static const _kPerTask = 'pomodoro.per_task';
  static const _kAutoComplete = 'pomodoro.auto_complete';

  @override
  PomodoroStatsState build() {
    // Hidratamos en background; mientras tanto exponemos defaults.
    _hydrate();
    return PomodoroStatsState(
      today: 0,
      todayDate: _todayKey(),
      perTask: const {},
      autoComplete: false,
      isLoaded: false,
    );
  }

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_kToday) ?? 0;
    final savedDate = prefs.getString(_kTodayDate);
    final todayKey = _todayKey();
    int today;
    String todayDate;
    if (savedDate != todayKey) {
      today = 0;
      todayDate = todayKey;
      await prefs.setInt(_kToday, 0);
      await prefs.setString(_kTodayDate, todayKey);
    } else {
      today = stored;
      todayDate = savedDate ?? todayKey;
    }
    final raw = prefs.getString(_kPerTask);
    Map<String, int> perTask = const {};
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = json.decode(raw) as Map<String, dynamic>;
        perTask = decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
      } catch (_) {/* ignorar */}
    }
    final autoComplete = prefs.getBool(_kAutoComplete) ?? false;
    state = PomodoroStatsState(
      today: today,
      todayDate: todayDate,
      perTask: perTask,
      autoComplete: autoComplete,
      isLoaded: true,
    );
  }

  Future<void> incrementToday() async {
    final next = state.today + 1;
    state = state.copyWith(today: next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kToday, next);
  }

  Future<void> incrementTask(String taskId) async {
    final next = Map<String, int>.from(state.perTask);
    next[taskId] = (next[taskId] ?? 0) + 1;
    state = state.copyWith(perTask: next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPerTask, json.encode(next));
  }

  Future<void> setAutoComplete(bool value) async {
    state = state.copyWith(autoComplete: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoComplete, value);
  }

  static String _todayKey() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

final pomodoroStatsProvider =
    NotifierProvider<PomodoroStats, PomodoroStatsState>(PomodoroStats.new);