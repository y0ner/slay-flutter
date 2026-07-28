import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/pomodoro_preset.dart';

/// Estado de las estadísticas persistidas del Pomodoro.
///
/// - `today`: contador diario que se resetea automáticamente cuando
///   cambia la fecha (comparado contra `todayDate`).
/// - `perTask`: mapa `taskId → cantidad` para mostrar en TaskCard.
/// - `history`: lista de fechas (yyyy-MM-dd) en las que se completó
///   al menos un pomodoro. Usada para calcular la racha.
/// - `perTaskHistory`: mapa `taskId → [timestamps]` de cada sesión.
///   Permite mostrar historial por tarea y "hace cuánto fue la
///   última sesión".
/// - `autoComplete`: preferencia para auto-marcar la tarea.
///
/// Todo se persiste en SharedPreferences; sobrevive cierres de app.
class PomodoroStatsState {
  const PomodoroStatsState({
    required this.today,
    required this.todayDate,
    required this.perTask,
    required this.history,
    required this.perTaskHistory,
    required this.autoComplete,
    required this.isLoaded,
  });

  final int today;
  final String todayDate;
  final Map<String, int> perTask;
  final List<String> history;
  final Map<String, List<DateTime>> perTaskHistory;
  final bool autoComplete;
  final bool isLoaded;

  PomodoroStatsState copyWith({
    int? today,
    String? todayDate,
    Map<String, int>? perTask,
    List<String>? history,
    Map<String, List<DateTime>>? perTaskHistory,
    bool? autoComplete,
  }) {
    return PomodoroStatsState(
      today: today ?? this.today,
      todayDate: todayDate ?? this.todayDate,
      perTask: perTask ?? this.perTask,
      history: history ?? this.history,
      perTaskHistory: perTaskHistory ?? this.perTaskHistory,
      autoComplete: autoComplete ?? this.autoComplete,
      isLoaded: true,
    );
  }
}

class PomodoroStats extends Notifier<PomodoroStatsState> {
  static const _kToday = 'pomodoro.today';
  static const _kTodayDate = 'pomodoro.today.date';
  static const _kPerTask = 'pomodoro.per_task';
  static const _kHistory = 'pomodoro.history';
  static const _kPerTaskHistory = 'pomodoro.per_task_history';
  static const _kAutoComplete = 'pomodoro.auto_complete';

  @override
  PomodoroStatsState build() {
    _hydrate();
    return PomodoroStatsState(
      today: 0,
      todayDate: _todayKey(),
      perTask: const {},
      history: const [],
      perTaskHistory: const {},
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

    final rawPerTask = prefs.getString(_kPerTask);
    Map<String, int> perTask = const {};
    if (rawPerTask != null && rawPerTask.isNotEmpty) {
      try {
        final decoded = json.decode(rawPerTask) as Map<String, dynamic>;
        perTask = decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
      } catch (_) {/* ignorar */}
    }

    final rawHistory = prefs.getStringList(_kHistory) ?? const [];
    final history = List<String>.from(rawHistory);

    final rawPerTaskHistory = prefs.getString(_kPerTaskHistory);
    Map<String, List<DateTime>> perTaskHistory = const {};
    if (rawPerTaskHistory != null && rawPerTaskHistory.isNotEmpty) {
      try {
        final decoded = json.decode(rawPerTaskHistory) as Map<String, dynamic>;
        perTaskHistory = decoded.map((k, v) {
          final list = (v as List)
              .map((e) => DateTime.tryParse(e.toString()))
              .whereType<DateTime>()
              .toList();
          return MapEntry(k, list);
        });
      } catch (_) {/* ignorar */}
    }

    final autoComplete = prefs.getBool(_kAutoComplete) ?? false;

    state = PomodoroStatsState(
      today: today,
      todayDate: todayDate,
      perTask: perTask,
      history: history,
      perTaskHistory: perTaskHistory,
      autoComplete: autoComplete,
      isLoaded: true,
    );
  }

  Future<void> incrementToday() async {
    final next = state.today + 1;
    final todayKey = _todayKey();
    final history = List<String>.from(state.history);
    if (!history.contains(todayKey)) history.add(todayKey);
    state = state.copyWith(today: next, todayDate: todayKey, history: history);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kToday, next);
    await prefs.setString(_kTodayDate, todayKey);
    await prefs.setStringList(_kHistory, history);
  }

  Future<void> incrementTask(String taskId) async {
    final nextCount = Map<String, int>.from(state.perTask);
    nextCount[taskId] = (nextCount[taskId] ?? 0) + 1;
    final nextHistory = Map<String, List<DateTime>>.from(state.perTaskHistory);
    final list = List<DateTime>.from(nextHistory[taskId] ?? const []);
    list.add(DateTime.now());
    nextHistory[taskId] = list;
    state = state.copyWith(perTask: nextCount, perTaskHistory: nextHistory);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPerTask, json.encode(nextCount));
    await prefs.setString(
        _kPerTaskHistory,
        json.encode(nextHistory.map(
            (k, v) => MapEntry(k, v.map((d) => d.toIso8601String()).toList()))));
  }

  Future<void> setAutoComplete(bool value) async {
    state = state.copyWith(autoComplete: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoComplete, value);
  }

  // ── Derivados (no se persisten, se computan) ──────────────

  /// Racha actual: días consecutivos hacia atrás con al menos 1
  /// pomodoro. Se corta si el día actual está vacío (porque recién
  /// arranca el día) o si hay un gap.
  int currentStreak() {
    final history = state.history.toSet();
    final today = _todayKey();
    int streak = 0;
    var cursor = DateTime.now();
    // Si hoy no tiene pomodoros pero ayer sí, la racha es de ayer hacia
    // atrás (racha "en riesgo"). Para el usuario la racha debe reflejar
    // continuidad, así que si hoy está en 0, empezamos desde ayer.
    if (!history.contains(today)) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    while (history.contains(_keyOf(cursor))) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// Tiempo total invertido en una tarea en minutos (suma de pomodoros
  /// × duración del preset actual de trabajo). Como el preset puede
  /// haber cambiado, aproximamos con 25 min (estándar). Si querés
  /// exactitud por preset, se persiste en cada sesión.
  int totalMinutesFor(String taskId, {int workMinutes = 25}) {
    final count = state.perTask[taskId] ?? 0;
    return count * workMinutes;
  }

  /// Última vez que se trabajó en la tarea, o null si nunca.
  DateTime? lastSessionFor(String taskId) {
    final list = state.perTaskHistory[taskId];
    if (list == null || list.isEmpty) return null;
    return list.last;
  }

  static String _todayKey() => _keyOf(DateTime.now());

  static String _keyOf(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '$y-$m-$dd';
  }
}

final pomodoroStatsProvider =
    NotifierProvider<PomodoroStats, PomodoroStatsState>(PomodoroStats.new);

// ── Configuración persistente del preset personalizado ──────

/// Duraciones elegidas por el usuario cuando selecciona el preset
/// "Personalizado". Persiste en SharedPreferences para sobrevivir
/// cierres de la app.
class PomodoroCustomConfig {
  const PomodoroCustomConfig({
    required this.work,
    required this.shortBreak,
    required this.longBreak,
    required this.cyclesBeforeLong,
  });
  final int work;
  final int shortBreak;
  final int longBreak;
  final int cyclesBeforeLong;

  static const defaults = PomodoroCustomConfig(
    work: 30,
    shortBreak: 7,
    longBreak: 20,
    cyclesBeforeLong: 4,
  );

  PomodoroCustomConfig copyWith({
    int? work,
    int? shortBreak,
    int? longBreak,
    int? cyclesBeforeLong,
  }) {
    return PomodoroCustomConfig(
      work: work ?? this.work,
      shortBreak: shortBreak ?? this.shortBreak,
      longBreak: longBreak ?? this.longBreak,
      cyclesBeforeLong: cyclesBeforeLong ?? this.cyclesBeforeLong,
    );
  }
}

class PomodoroCustomNotifier extends Notifier<PomodoroCustomConfig> {
  static const _kWork = 'pomodoro.custom.work';
  static const _kShort = 'pomodoro.custom.short';
  static const _kLong = 'pomodoro.custom.long';
  static const _kCycles = 'pomodoro.custom.cycles';

  @override
  PomodoroCustomConfig build() {
    _hydrate();
    return PomodoroCustomConfig.defaults;
  }

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    state = PomodoroCustomConfig(
      work: prefs.getInt(_kWork) ?? PomodoroCustomConfig.defaults.work,
      shortBreak:
          prefs.getInt(_kShort) ?? PomodoroCustomConfig.defaults.shortBreak,
      longBreak: prefs.getInt(_kLong) ?? PomodoroCustomConfig.defaults.longBreak,
      cyclesBeforeLong: prefs.getInt(_kCycles) ??
          PomodoroCustomConfig.defaults.cyclesBeforeLong,
    );
  }

  Future<void> save(PomodoroCustomConfig config) async {
    state = config;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kWork, config.work);
    await prefs.setInt(_kShort, config.shortBreak);
    await prefs.setInt(_kLong, config.longBreak);
    await prefs.setInt(_kCycles, config.cyclesBeforeLong);
  }
}

final pomodoroCustomProvider =
    NotifierProvider<PomodoroCustomNotifier, PomodoroCustomConfig>(
        PomodoroCustomNotifier.new);

// ── Preset seleccionado ─────────────────────────────────────

/// Label persistido del preset activo. Cuando vale `'Personalizado'`,
/// las duraciones vienen de `pomodoroCustomProvider`; si no, es uno
/// de los built-in (Estándar / Corto / Largo). Esto permite que al
/// cerrar y reabrir la app el usuario conserve su elección sin tener
/// que volver a entrar al overlay de configuración.
class PomodoroSelectedPresetNotifier extends Notifier<PomodoroPreset> {
  static const _kPreset = 'pomodoro.preset';

  @override
  PomodoroPreset build() {
    _hydrate();
    return PomodoroPreset.standard;
  }

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final label = prefs.getString(_kPreset);
    if (label == null || label.isEmpty) return;
    final custom = ref.read(pomodoroCustomProvider);
    final match = PomodoroPreset.builtIn.firstWhere(
      (p) => p.label == label,
      orElse: () => PomodoroPreset(
        'Personalizado',
        custom.work,
        custom.shortBreak,
        custom.longBreak,
        custom.cyclesBeforeLong,
      ),
    );
    state = match;
  }

  Future<void> save(PomodoroPreset preset) async {
    state = preset;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPreset, preset.label);
  }
}

final pomodoroSelectedPresetProvider =
    NotifierProvider<PomodoroSelectedPresetNotifier, PomodoroPreset>(
        PomodoroSelectedPresetNotifier.new);

// ── Incremento configurable (chip "+N min") ─────────────────

/// Minutos que suma el chip "+N min" cuando el usuario quiere extender
/// la sesión actual (default 5). El user lo configura desde el overlay
/// de preset; persiste entre cierres de la app.
class PomodoroIncrementNotifier extends Notifier<int> {
  static const _kIncrement = 'pomodoro.increment_minutes';

  @override
  int build() {
    _hydrate();
    return 5; // default histórico
  }

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_kIncrement);
    if (stored == null || stored <= 0) return;
    state = stored;
  }

  Future<void> save(int minutes) async {
    state = minutes;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kIncrement, minutes);
  }
}

final pomodoroIncrementProvider =
    NotifierProvider<PomodoroIncrementNotifier, int>(
        PomodoroIncrementNotifier.new);

// ── Persistencia del timer en curso (Paquete B) ──────────

/// Snapshot del estado del timer para sobrevivir cierres de la app.
///
/// Sólo persiste UNA sesión a la vez (no histórico). Si la app se mata
/// durante un pomodoro, al reabrir ofrece "Recuperar" o "Descartar".
class PomodoroSessionSnapshot {
  const PomodoroSessionSnapshot({
    required this.kind, // 'work' | 'shortBreak' | 'longBreak'
    required this.remainingSeconds,
    required this.totalSeconds,
    required this.startedAtMs,
    required this.taskId,
    required this.taskTitle,
    required this.presetLabel,
    required this.cycleIndex,
    required this.cyclesBeforeLong,
  });

  final String kind;
  final int remainingSeconds;
  final int totalSeconds;
  final int startedAtMs;
  final String taskId;
  final String taskTitle;
  final String presetLabel;
  final int cycleIndex;
  final int cyclesBeforeLong;

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'remaining': remainingSeconds,
        'total': totalSeconds,
        'startedAt': startedAtMs,
        'taskId': taskId,
        'taskTitle': taskTitle,
        'preset': presetLabel,
        'cycle': cycleIndex,
        'cyclesBeforeLong': cyclesBeforeLong,
      };

  static PomodoroSessionSnapshot? fromJson(String raw) {
    try {
      final m = json.decode(raw) as Map<String, dynamic>;
      return PomodoroSessionSnapshot(
        kind: m['kind'] as String,
        remainingSeconds: (m['remaining'] as num).toInt(),
        totalSeconds: (m['total'] as num).toInt(),
        startedAtMs: (m['startedAt'] as num).toInt(),
        taskId: m['taskId'] as String,
        taskTitle: m['taskTitle'] as String,
        presetLabel: m['preset'] as String,
        cycleIndex: (m['cycle'] as num).toInt(),
        cyclesBeforeLong: (m['cyclesBeforeLong'] as num).toInt(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Cuántos segundos pasaron desde que se guardó el snapshot.
  /// Si el delta es mayor que el total, la sesión ya expiró.
  int elapsedSeconds(DateTime now) {
    final started = DateTime.fromMillisecondsSinceEpoch(startedAtMs);
    return now.difference(started).inSeconds;
  }

  /// Lo que le quedaba REAL al usuario si reabre la app ahora. Si es
  /// <= 0 la sesión ya terminó y se debe descartar.
  int remainingNow(DateTime now) {
    return remainingSeconds - elapsedSeconds(now);
  }
}

class PomodoroSessionPersist {
  static const _key = 'pomodoro.active_session';

  static Future<void> save(PomodoroSessionSnapshot snap) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, json.encode(snap.toJson()));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  static Future<PomodoroSessionSnapshot?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    return PomodoroSessionSnapshot.fromJson(raw);
  }
}