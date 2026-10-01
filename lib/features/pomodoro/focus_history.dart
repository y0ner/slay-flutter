import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Una sesión de foco registrada en el historial.
///
/// Cada fila es un RUN completo (no por intervalo): qué tarea, cuándo
/// empezó, cuánto tiempo de TRABAJO acumuló (sin descansos) y con qué
/// configuración. `taskTitle` se guarda aparte para que el registro
/// siga siendo legible aunque la tarea se elimine después.
class FocusSessionEntry {
  const FocusSessionEntry({
    required this.id,
    required this.taskId,
    required this.taskTitle,
    required this.startedAtMs,
    required this.workedSeconds,
    required this.plannedTotalMinutes,
    required this.intervalCount,
    required this.breakMinutes,
    this.endedAtMs,
    this.pauseCount = 0,
    this.reconfiguredCount = 0,
    this.completedTask = false,
    this.status = 'running', // running | finished | stopped | reconfigured
  });

  final String id;
  final String taskId;
  final String taskTitle;
  final int startedAtMs;
  final int? endedAtMs;
  final int workedSeconds; // trabajo puro, sin descansos
  final int plannedTotalMinutes;
  final int intervalCount;
  final int breakMinutes;
  final int pauseCount;
  final int reconfiguredCount;
  final bool completedTask;
  final String status;

  bool get isRunning => status == 'running';

  Duration get workedDuration => Duration(seconds: workedSeconds);

  FocusSessionEntry copyWith({
    int? workedSeconds,
    int? endedAtMs,
    int? pauseCount,
    int? reconfiguredCount,
    bool? completedTask,
    String? status,
  }) =>
      FocusSessionEntry(
        id: id,
        taskId: taskId,
        taskTitle: taskTitle,
        startedAtMs: startedAtMs,
        workedSeconds: workedSeconds ?? this.workedSeconds,
        plannedTotalMinutes: plannedTotalMinutes,
        intervalCount: intervalCount,
        breakMinutes: breakMinutes,
        endedAtMs: endedAtMs ?? this.endedAtMs,
        pauseCount: pauseCount ?? this.pauseCount,
        reconfiguredCount: reconfiguredCount ?? this.reconfiguredCount,
        completedTask: completedTask ?? this.completedTask,
        status: status ?? this.status,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'taskId': taskId,
        'taskTitle': taskTitle,
        'startedAt': startedAtMs,
        'endedAt': endedAtMs,
        'workedSeconds': workedSeconds,
        'plannedTotal': plannedTotalMinutes,
        'intervals': intervalCount,
        'breakMin': breakMinutes,
        'pauses': pauseCount,
        'reconfigs': reconfiguredCount,
        'completed': completedTask,
        'status': status,
      };

  static FocusSessionEntry fromJson(Map<String, dynamic> j) =>
      FocusSessionEntry(
        id: j['id'] as String,
        taskId: j['taskId'] as String,
        taskTitle: (j['taskTitle'] as String?) ?? '',
        startedAtMs: (j['startedAt'] as num).toInt(),
        workedSeconds: (j['workedSeconds'] as num?)?.toInt() ?? 0,
        plannedTotalMinutes: (j['plannedTotal'] as num?)?.toInt() ?? 0,
        intervalCount: (j['intervals'] as num?)?.toInt() ?? 1,
        breakMinutes: (j['breakMin'] as num?)?.toInt() ?? 0,
        endedAtMs: (j['endedAt'] as num?)?.toInt(),
        pauseCount: (j['pauses'] as num?)?.toInt() ?? 0,
        reconfiguredCount: (j['reconfigs'] as num?)?.toInt() ?? 0,
        completedTask: (j['completed'] as bool?) ?? false,
        status: (j['status'] as String?) ?? 'running',
      );
}

/// Historial persistido en SharedPreferences (JSON list).
///
/// Por qué no Drift: el codegen del proyecto quedó incompatible con el
/// analyzer actual y el historial es local-personal (decenas de filas,
/// arranca limpio por decisión del usuario) — prefs alcanza con margen.
class FocusHistoryNotifier extends Notifier<List<FocusSessionEntry>> {
  static const _key = 'focus.history.v2';
  static const _maxEntries = 500;

  @override
  List<FocusSessionEntry> build() {
    _hydrate();
    return const [];
  }

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => FocusSessionEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      state = list;
    } catch (_) {
      // Historial corrupto: arrancar limpio (decisión del usuario).
      await prefs.remove(_key);
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
        state.take(_maxEntries).map((e) => e.toJson()).toList());
    await prefs.setString(_key, encoded);
  }

  /// Inserta o reemplaza por id (upsert).
  Future<void> upsert(FocusSessionEntry entry) async {
    final next = List<FocusSessionEntry>.from(state);
    final idx = next.indexWhere((e) => e.id == entry.id);
    if (idx >= 0) {
      next[idx] = entry;
    } else {
      next.insert(0, entry);
    }
    state = next;
    await _persist();
  }

  /// Segundos totales trabajados (sin descansos) para una tarea a lo
  /// largo de todos sus runs.
  int workedSecondsForTask(String taskId) {
    var total = 0;
    for (final e in state) {
      if (e.taskId == taskId) total += e.workedSeconds;
    }
    return total;
  }

  /// Runs registrados de una tarea (más nuevos primero).
  List<FocusSessionEntry> sessionsForTask(String taskId) =>
      state.where((e) => e.taskId == taskId).toList();

  /// Limpia todo el historial (por si el usuario quiere resetear).
  Future<void> clearAll() async {
    state = const [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

final focusHistoryProvider =
    NotifierProvider<FocusHistoryNotifier, List<FocusSessionEntry>>(
        FocusHistoryNotifier.new);
