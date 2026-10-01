import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/repositories/task_repository.dart';
import '../../notifications/local_notifications.dart';
import 'focus_history.dart';
import 'focus_model.dart';

/// Controlador del run de foco (pomodoro v2).
///
/// Un "run" es el ciclo completo para UNA tarea: N intervalos de
/// trabajo con descansos entre ellos. El estado completo vive acá
/// (Notifier) y se persiste en SharedPreferences al cambiar de fase,
/// pausar o reconfigurar — sobrevive kills del proceso.
///
/// El countdown es WALL-CLOCK: se guarda `phaseEndsAtMs` (timestamp
/// absoluto) y el remaining se recalcula contra el reloj. Los Timers
/// no corren congelados en background; con wall-clock el número es
/// correcto apenas la app despierta.
class FocusRunNotifier extends Notifier<FocusRunState?> {
  Timer? _ticker;
  bool _finishingPhase = false;

  @override
  FocusRunState? build() {
    _hydrate();
    return null;
  }

  // ── Hidratación (cold start) ─────────────────────────────

  Future<void> _hydrate() async {
    final snap = await FocusRunPersist.load();
    if (snap == null) return;
    // Reconstruir el estado y dejarlo corriendo si estaba corriendo.
    final now = DateTime.now().millisecondsSinceEpoch;
    final remaining = snap['endAtMs'] != null
        ? ((snap['endAtMs'] as int) - now) ~/ 1000
        : (snap['remainingSeconds'] as int? ?? 0);
    state = FocusRunState(
      runId: snap['runId'] as String,
      taskId: snap['taskId'] as String,
      taskTitle: snap['taskTitle'] as String,
      config: FocusConfig.fromJson(
          Map<String, dynamic>.from(snap['config'] as Map)),
      phase: _phaseFromJson(Map<String, dynamic>.from(snap['phase'] as Map)),
      remainingSeconds: max(0, remaining),
      running: snap['running'] as bool? ?? false,
      startedAt: snap['startedAt'] as int,
      workedSecondsTotal: snap['workedSecondsTotal'] as int? ?? 0,
      pauseCount: snap['pauseCount'] as int? ?? 0,
      reconfiguredCount: snap['reconfiguredCount'] as int? ?? 0,
      phaseEndsAtMs: snap['endAtMs'] as int?,
    );
    if (state!.running) {
      _startTicker();
      if (remaining <= 0) {
        // La fase terminó mientras la app estaba muerta.
        await _finishPhase();
      }
    }
  }

  FocusPhase _phaseFromJson(Map<String, dynamic> json) =>
      json['kind'] == 'break'
          ? FocusBreak(json['index'] as int)
          : FocusWork(json['index'] as int);

  Map<String, dynamic> _phaseToJson(FocusPhase phase) => {
        'kind': phase.isBreak ? 'break' : 'work',
        'index': phase.index,
      };

  // ── Persistencia ─────────────────────────────────────────

  Future<void> _persist() async {
    final s = state;
    if (s == null) {
      await FocusRunPersist.clear();
      return;
    }
    await FocusRunPersist.save({
      'runId': s.runId,
      'taskId': s.taskId,
      'taskTitle': s.taskTitle,
      'config': s.config.toJson(),
      'phase': _phaseToJson(s.phase),
      'remainingSeconds': s.remainingSeconds,
      'running': s.running,
      'startedAt': s.startedAt,
      'workedSecondsTotal': s.workedSecondsTotal,
      'pauseCount': s.pauseCount,
      'reconfiguredCount': s.reconfiguredCount,
      'endAtMs': s.phaseEndsAtMs,
    });
  }

  // ── Acciones públicas (llamadas desde la UI) ────────────

  /// Inicia un run nuevo para [taskId] con la [config] elegida en el
  /// wizard. Crea la fila del historial (status running).
  Future<void> start({
    required String taskId,
    required String taskTitle,
    required FocusConfig config,
  }) async {
    cancelTicker();
    final runId =
        'run_${DateTime.now().millisecondsSinceEpoch}_${taskId.substring(0, 8)}';
    final phase = const FocusWork(0);
    final seconds = workSecondsForIndex(config, 0);
    final now = DateTime.now();
    state = FocusRunState(
      runId: runId,
      taskId: taskId,
      taskTitle: taskTitle,
      config: config,
      phase: phase,
      remainingSeconds: seconds,
      running: true,
      startedAt: now.millisecondsSinceEpoch,
      workedSecondsTotal: 0,
      phaseEndsAtMs:
          now.add(Duration(seconds: seconds)).millisecondsSinceEpoch,
    );
    await _persist();
    _ensureHistoryRow();
    await _schedulePhaseNotification();
    await _startForegroundService(taskTitle);
    _startTicker();
  }

  /// Android: notificación persistente tipo "app de música" mientras
  /// corre el foco. En otras plataformas es no-op.
  Future<void> _startForegroundService(String taskTitle) async {
    if (!_canUseForegroundService) return;
    try {
      // Android 13+: sin POST_NOTIFICATIONS la notificación del FGS no
      // se ve. Pedirlo al iniciar el run (con contexto de uso) en vez
      // de al abrir la app.
      await LocalNotifications.instance.requestPermission();
      if (await FlutterForegroundTask.isRunningService) return;
      await FlutterForegroundTask.startService(
        notificationTitle: 'Sesión de foco',
        notificationText: taskTitle,
      );
    } catch (_) {
      // Sin permiso de notificación o error nativo: el timer sigue
      // funcionando con las notificaciones programadas.
    }
  }

  Future<void> _stopForegroundService() async {
    if (!_canUseForegroundService) return;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (_) {}
  }

  static bool get _canUseForegroundService =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Pausa manual. El remaining queda congelado (se recalcula antes).
  Future<void> pause() async {
    final s = state;
    if (s == null || !s.running) return;
    cancelTicker();
    // Creditar el trabajo transcurrido de esta fase antes de pausar.
    final elapsed = _elapsedOfWorkPhase(s);
    state = s.copyWith(
      running: false,
      workedSecondsTotal: s.workedSecondsTotal + elapsed,
      pauseCount: s.pauseCount + 1,
      phaseEndsAtMsClear: true,
      remainingSeconds: _remainingOfPhase(s),
    );
    await _persist();
    await _updateHistoryRow();
    await LocalNotifications.instance.cancel(_notifId);
  }

  /// Reanuda desde la pausa.
  Future<void> resume() async {
    final s = state;
    if (s == null || s.running) return;
    final endAt =
        DateTime.now().add(Duration(seconds: s.remainingSeconds));
    state = s.copyWith(
      running: true,
      phaseEndsAtMs: endAt.millisecondsSinceEpoch,
    );
    await _persist();
    await _schedulePhaseNotification();
    _startTicker();
  }

  /// El usuario detiene y reconfigura TODO (nuevo wizard).
  /// La fila del historial actual se marca `reconfigured` y el tiempo
  /// trabajado hasta acá queda registrado.
  Future<void> reconfigure() async {
    final s = state;
    cancelTicker();
    if (s != null) {
      final elapsed = s.running ? _elapsedOfWorkPhase(s) : 0;
      final finalWorked = s.workedSecondsTotal + elapsed;
      await _finalizeHistoryRow(
        workedSeconds: finalWorked,
        status: 'reconfigured',
        endedAt: DateTime.now(),
      );
    }
    await LocalNotifications.instance.cancel(_notifId);
    await _stopForegroundService();
    state = null;
    await _persist();
  }

  /// Abandona el run del todo (desde el wrap-up: "no hice nada").
  Future<void> abandon() async {
    final s = state;
    cancelTicker();
    if (s != null) {
      final elapsed = s.running ? _elapsedOfWorkPhase(s) : 0;
      await _finalizeHistoryRow(
        workedSeconds: s.workedSecondsTotal + elapsed,
        status: 'stopped',
        endedAt: DateTime.now(),
      );
    }
    await LocalNotifications.instance.cancel(_notifId);
    await _stopForegroundService();
    state = null;
    await _persist();
  }

  /// Wrap-up: el usuario dijo "terminé" → completar la tarea.
  Future<void> completeTaskAndFinish() async {
    final s = state;
    cancelTicker();
    if (s != null) {
      final elapsed = s.running ? _elapsedOfWorkPhase(s) : 0;
      final worked = s.workedSecondsTotal + elapsed;
      await _finalizeHistoryRow(
        workedSeconds: worked,
        status: 'finished',
        endedAt: DateTime.now(),
        completedTask: true,
      );
      // Completar la tarea con la política de orden global.
      try {
        final repo = ref.read(taskRepositoryProvider);
        final all = await repo.getAll();
        await repo.toggleWithReorder(s.taskId, true, all);
        ref.invalidate(tasksStreamProvider);
      } catch (_) {
        // Si falla la red, la tarea queda pendiente de sync; el run
        // igual se cierra con completedTask=true.
      }
    }
    await LocalNotifications.instance.cancel(_notifId);
    await _stopForegroundService();
    state = null;
    await _persist();
  }

  /// Wrap-up: "no terminé" → extender SOLO el tiempo total. Los
  /// intervalos y el descanso se mantienen. Arranca un run nuevo
  /// (historial nuevo) con el extra como total.
  Future<void> extendAndRestart({required int extraMinutes}) async {
    final s = state;
    if (s == null) return;
    await start(
      taskId: s.taskId,
      taskTitle: s.taskTitle,
      config: s.config.copyWith(
          totalMinutes: s.config.totalMinutes + extraMinutes),
    );
  }

  /// Salta el descanso actual y pasa al siguiente intervalo de trabajo.
  Future<void> skipBreak() async {
    final s = state;
    if (s == null || !s.phase.isBreak) return;
    final next = advancePhase(FocusRunState(
      runId: s.runId,
      taskId: s.taskId,
      taskTitle: s.taskTitle,
      config: s.config,
      phase: s.phase,
      remainingSeconds: 0,
      running: s.running,
      startedAt: s.startedAt,
      workedSecondsTotal: s.workedSecondsTotal,
      pauseCount: s.pauseCount,
      reconfiguredCount: s.reconfiguredCount,
    ));
    if (next == null) return;
    final endAt = DateTime.now()
        .add(Duration(seconds: next.remainingSeconds));
    state = next.copyWith(
      phaseEndsAtMs: endAt.millisecondsSinceEpoch,
      running: true,
    );
    await _persist();
    await _schedulePhaseNotification();
    _startTicker();
  }

  // ── Tick wall-clock ─────────────────────────────────────

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final s = state;
    if (s == null) return;
    if (!s.running || s.phaseEndsAtMs == null) return;
    final rem =
        ((s.phaseEndsAtMs! - DateTime.now().millisecondsSinceEpoch) / 1000)
            .floor();
    if (rem <= 0) {
      if (!_finishingPhase) _finishPhase();
      return;
    }
    state = s.copyWith(remainingSeconds: rem);
  }

  /// Termina la fase actual: avanza de fase, agenda notificación y
  /// persiste. Si era el último trabajo → estado "wrap-up" (run null
  /// pendiente de decisión). El wrap-up se maneja en la UI via
  /// `runJustFinished` flag que exponemos con un provider aparte.
  Future<void> _finishPhase() async {
    if (_finishingPhase) return;
    _finishingPhase = true;
    try {
      final s = state;
      if (s == null) return;
      final fullPhaseSeconds = s.currentPhaseTotalSeconds;
      if (s.phase.isWork) {
        // Creditar el intervalo completo.
        final worked = s.workedSecondsTotal + fullPhaseSeconds;
        final next = advancePhase(s);
        if (next == null) {
          // Último trabajo terminado → fin del run. Guardar historial
          // y apagar el reloj. La UI muestra el wrap-up.
          _ticker?.cancel();
          state = s.copyWith(
            remainingSeconds: 0,
            running: false,
            workedSecondsTotal: worked,
            phaseEndsAtMsClear: true,
          );
          await _finalizeHistoryRow(
            workedSeconds: worked,
            status: 'finished',
            endedAt: DateTime.now(),
          );
          await _persist();
          await LocalNotifications.instance.cancel(_notifId);
          await _stopForegroundService();
          return;
        }
        // Trabajo → descanso: automatic.
        final endAt = DateTime.now()
            .add(Duration(seconds: next.remainingSeconds));
        state = next.copyWith(
          workedSecondsTotal: worked,
          phaseEndsAtMs:
              next.running ? endAt.millisecondsSinceEpoch : null,
        );
    await _persist();
    _ensureHistoryRow();
    await _schedulePhaseNotification();
    if (next.running) {
      _startTicker();
    } else {
      _ticker?.cancel();
    }
      } else {
        // Fin de descanso → trabajo. Automatic.
        final next = advancePhase(s);
        if (next == null) return;
        final endAt = DateTime.now()
            .add(Duration(seconds: next.remainingSeconds));
        state = next.copyWith(
          phaseEndsAtMs: endAt.millisecondsSinceEpoch,
        );
        await _persist();
        await _schedulePhaseNotification();
        _startTicker();
      }
    } finally {
      _finishingPhase = false;
    }
  }

  // ── Helpers ──────────────────────────────────────────────

  /// Segundos transcurridos de la fase laboral ACTUAL (para creditar
  /// al pausar). Si la fase es descanso devuelve 0.
  int _elapsedOfWorkPhase(FocusRunState s) {
    if (!s.phase.isWork || s.phaseEndsAtMs == null) return 0;
    final total = s.currentPhaseTotalSeconds;
    final remaining = _remainingOfPhase(s);
    return (total - remaining).clamp(0, total);
  }

  int _remainingOfPhase(FocusRunState s) {
    if (s.phaseEndsAtMs == null) return s.remainingSeconds;
    return max(
        0,
        ((s.phaseEndsAtMs! - DateTime.now().millisecondsSinceEpoch) / 1000)
            .floor());
  }

  static int get _notifId => 4000001;

  /// Notificación al final de la fase ACTUAL (trabajo→descanso o
  /// descanso→trabajo).
  Future<void> _schedulePhaseNotification() async {
    final s = state;
    if (s == null || !s.running || s.phaseEndsAtMs == null) return;
    await LocalNotifications.instance.cancel(_notifId);
    final end = DateTime.fromMillisecondsSinceEpoch(s.phaseEndsAtMs!);
    if (end.isBefore(DateTime.now())) return;
    final isWorkPhase = s.phase.isWork;
    final title = isWorkPhase
        ? 'Descanso — ${s.taskTitle}'
        : 'A trabajar — ${s.taskTitle}';
    final body = isWorkPhase
        ? 'Terminó el intervalo ${s.phase.index + 1}/${s.config.intervalCount}. Tomá ${s.config.breakMinutes} min.'
        : 'Arranca el intervalo ${s.phase.index + 2}/${s.config.intervalCount}.';
    await LocalNotifications.instance.scheduleSessionEnd(
      id: _notifId,
      title: title,
      body: body,
      when: end,
    );
  }

  // ── Historial (SharedPreferences) ───────────────────────

  FocusSessionEntry _entryFromState(
    FocusRunState s, {
    required int workedSeconds,
    String? status,
    int? endedAtMs,
    bool completedTask = false,
  }) {
    final existing = ref
        .read(focusHistoryProvider)
        .where((e) => e.id == s.runId)
        .firstOrNull;
    return (existing ?? FocusSessionEntry(
      id: s.runId,
      taskId: s.taskId,
      taskTitle: s.taskTitle,
      startedAtMs: s.startedAt,
      workedSeconds: 0,
      plannedTotalMinutes: s.config.totalMinutes,
      intervalCount: s.config.intervalCount,
      breakMinutes: s.config.breakMinutes,
    )).copyWith(
      workedSeconds: workedSeconds,
      endedAtMs: endedAtMs,
      pauseCount: s.pauseCount,
      reconfiguredCount: s.reconfiguredCount,
      completedTask: completedTask || (existing?.completedTask ?? false),
      status: status ?? existing?.status ?? 'running',
    );
  }

  void _ensureHistoryRow() {
    final s = state;
    if (s == null) return;
    ref.read(focusHistoryProvider.notifier).upsert(
          _entryFromState(s, workedSeconds: s.workedSecondsTotal),
        );
  }

  Future<void> _updateHistoryRow() async {
    final s = state;
    if (s == null) return;
    await ref.read(focusHistoryProvider.notifier).upsert(
          _entryFromState(s, workedSeconds: s.workedSecondsTotal),
        );
  }

  Future<void> _finalizeHistoryRow({
    required int workedSeconds,
    required String status,
    required DateTime endedAt,
    bool completedTask = false,
  }) async {
    final s = state;
    if (s == null) return;
    await ref.read(focusHistoryProvider.notifier).upsert(
          _entryFromState(
            s,
            workedSeconds: workedSeconds,
            status: status,
            endedAtMs: endedAt.millisecondsSinceEpoch,
            completedTask: completedTask,
          ),
        );
  }

  // ── Limpieza ─────────────────────────────────────────────

  void cancelTicker() {
    _ticker?.cancel();
    _ticker = null;
  }
}

/// Estado derivado: ¿el run terminó su último intervalo y espera la
/// decisión del wrap-up? (estado no-null, no corriendo, remaining 0,
/// última fase de trabajo completada).
final focusRunProvider =
    NotifierProvider<FocusRunNotifier, FocusRunState?>(FocusRunNotifier.new);

/// True si hay un run vivo (corriendo o pausado) que NO terminó aún.
final focusRunActiveProvider = Provider<bool>((ref) {
  final s = ref.watch(focusRunProvider);
  if (s == null) return false;
  // Si el último trabajo terminó (remaining 0, fase work última,
  // running false), el run terminó y estamos en wrap-up.
  if (!s.running &&
      s.remainingSeconds == 0 &&
      s.isLastWork &&
      s.workedSecondsTotal > 0) {
    return false;
  }
  return true;
});

/// Persistencia del run activo en SharedPreferences (sobrevive kill).
class FocusRunPersist {
  static const _key = _kKey;
  static const _kKey = 'focus.active_run_v2';

  static Future<void> save(Map<String, dynamic> json) async {
    // (import perezoso para no depender de shared_preferences acá)
    // Se usa SharedPreferences vía el helper global.
    await FocusRunPersistStore.save(_key, json);
  }

  static Future<Map<String, dynamic>?> load() =>
      FocusRunPersistStore.load(_key);

  static Future<void> clear() => FocusRunPersistStore.clear(_key);
}

class FocusRunPersistStore {
  static Future<void> save(String key, Map<String, dynamic> json) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(json));
  }

  static Future<Map<String, dynamic>?> load(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}
