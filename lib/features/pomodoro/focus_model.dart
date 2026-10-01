/// Modelo puro de la configuración de una sesión de foco.
///
/// El usuario elige:
/// - cuánto tiempo total cree que le toma la tarea (`totalMinutes`),
/// - en cuántos intervalos lo divide (`intervalCount`),
/// - cuántos minutos de descanso entre cada intervalo (`breakMinutes`).
///
/// Ejemplo: 60 min en 5 intervalos con 1 min de descanso =
/// 5 sesiones de 12 min con 1 min de descanso entre cada una.
///
/// NOTA sobre el descanso: el descanso va ENTRE intervalos, así que
/// con N intervalos hay N-1 descansos. El último intervalo termina
/// el run directamente con el wrap-up (¿terminaste? sí/no).
class FocusConfig {
  const FocusConfig({
    required this.totalMinutes,
    required this.intervalCount,
    required this.breakMinutes,
  });

  /// Tiempo total que el usuario estima para la tarea.
  final int totalMinutes;

  /// En cuántos intervalos divide el tiempo total. Mínimo 1.
  final int intervalCount;

  /// Minutos de descanso ENTRE intervalos.
  final int breakMinutes;

  /// Duración de cada intervalo de trabajo, en minutos.
  /// Redondeo hacia abajo para no pasarse del total elegido.
  int get workMinutesPerInterval =>
      totalMinutes ~/ intervalCount.clamp(1, 1 << 31);

  /// Segundos por intervalo de trabajo.
  int get workSecondsPerInterval => workMinutesPerInterval * 60;

  /// Segundos de descanso entre intervalos.
  int get breakSeconds => breakMinutes * 60;

  /// Número real de descansos (N intervalos → N-1 descansos).
  int get breakCount => (intervalCount - 1).clamp(0, 1 << 31);

  /// Duración REAL total del run en minutos, incluyendo descansos.
  int get realTotalMinutes =>
      totalMinutes + breakCount * breakMinutes;

  /// Validación mínima para no crear configs absurdas.
  bool get isValid =>
      totalMinutes >= 1 &&
      intervalCount >= 1 &&
      breakMinutes >= 0 &&
      workMinutesPerInterval >= 1;

  FocusConfig copyWith({
    int? totalMinutes,
    int? intervalCount,
    int? breakMinutes,
  }) =>
      FocusConfig(
        totalMinutes: totalMinutes ?? this.totalMinutes,
        intervalCount: intervalCount ?? this.intervalCount,
        breakMinutes: breakMinutes ?? this.breakMinutes,
      );

  Map<String, dynamic> toJson() => {
        'total': totalMinutes,
        'intervals': intervalCount,
        'break': breakMinutes,
      };

  static FocusConfig fromJson(Map<String, dynamic> json) => FocusConfig(
        totalMinutes: (json['total'] as num).toInt(),
        intervalCount: (json['intervals'] as num).toInt(),
        breakMinutes: (json['break'] as num).toInt(),
      );
}

/// Fase actual dentro del run: trabajo i-ésimo o descanso i-ésimo.
sealed class FocusPhase {
  const FocusPhase();

  /// Índice 0-based del intervalo de trabajo (o del descanso que sigue).
  int get index;

  bool get isWork => this is FocusWork;
  bool get isBreak => this is FocusBreak;
}

/// Intervalo de trabajo #i (0-based). `i == config.intervalCount - 1`
/// es el último.
class FocusWork extends FocusPhase {
  const FocusWork(this.index);
  @override
  final int index;
}

/// Descanso después del trabajo #index (0-based). Sólo hay descansos
/// hasta `intervalCount - 2`.
class FocusBreak extends FocusPhase {
  const FocusBreak(this.index);
  @override
  final int index;
}

/// Estado completo del run de foco. Inmutable: el controller emite
/// estados nuevos y la UI sólo los renderiza.
class FocusRunState {
  const FocusRunState({
    required this.taskId,
    required this.taskTitle,
    required this.config,
    required this.phase,
    required this.remainingSeconds,
    required this.running,
    required this.startedAt,
    required this.workedSecondsTotal,
    required this.runId,
    this.pauseCount = 0,
    this.reconfiguredCount = 0,
    this.phaseEndsAtMs,
  });

  final String runId;

  /// Tarea en foco. Todo el tiempo trabajado se le registra.
  final String taskId;
  final String taskTitle;
  final FocusConfig config;

  /// Fase actual (trabajo o descanso) y su índice.
  final FocusPhase phase;

  /// Segundos restantes de la fase ACTUAL.
  final int remainingSeconds;

  /// ¿El reloj corre? (pausa manual = running false, fase igual).
  final bool running;

  /// Timestamp (ms) del inicio del RUN completo. Para el historial.
  final int startedAt;

  /// Segundos de TRABAJO acumulados en todo el run (sin descansos).
  /// Se actualiza al completar cada intervalo y al pausar.
  final int workedSecondsTotal;

  /// Cuántas veces pausó el usuario (métrica del historial).
  final int pauseCount;

  /// Cuántas veces reconfiguró ("detener y empezar de nuevo").
  final int reconfiguredCount;

  /// Hora ABSOLUTA (ms epoch) en que termina la fase actual, si está
  /// corriendo. Todo el countdown se deriva de acá (wall-clock):
  /// sobrevive backgrounds y freezes del SO.
  final int? phaseEndsAtMs;

  /// Derivados cómodos para la UI.
  bool get isLastWork =>
      phase is FocusWork && (phase as FocusWork).index == config.intervalCount - 1;

  bool get isRunningWork => running && phase.isWork;

  /// Progreso [0..1] de la fase actual.
  double get phaseProgress {
    final total = _totalSecondsOfCurrentPhase;
    if (total <= 0) return 0;
    return (1 - remainingSeconds / total).clamp(0.0, 1.0);
  }

  int get _totalSecondsOfCurrentPhase => switch (phase) {
        FocusWork(:final index) =>
          index == config.intervalCount - 1
              ? _lastWorkSeconds
              : config.workSecondsPerInterval,
        FocusBreak() => config.breakSeconds,
      };

  /// El último intervalo puede ser más corto si el total no es
  /// divisible por el número de intervalos (ej: 60 min en 4 →
  /// 15,15,15,15; 62 en 4 → 15,15,15,17 con esta aritmética de
  /// resto en el último).
  int get _lastWorkSeconds {
    final per = config.workSecondsPerInterval;
    final remainderSec =
        (config.totalMinutes % config.intervalCount) * 60;
    return per + remainderSec;
  }

  /// Segundos de la fase actual (para labels tipo "12 min").
  int get currentPhaseTotalSeconds => _totalSecondsOfCurrentPhase;

  FocusRunState copyWith({
    String? taskId,
    String? taskTitle,
    FocusConfig? config,
    FocusPhase? phase,
    int? remainingSeconds,
    bool? running,
    int? workedSecondsTotal,
    int? pauseCount,
    int? reconfiguredCount,
    int? phaseEndsAtMs,
    Object? phaseEndsAtMsClear = null,
  }) =>
      FocusRunState(
        runId: runId,
        taskId: taskId ?? this.taskId,
        taskTitle: taskTitle ?? this.taskTitle,
        config: config ?? this.config,
        phase: phase ?? this.phase,
        remainingSeconds: remainingSeconds ?? this.remainingSeconds,
        running: running ?? this.running,
        startedAt: startedAt,
        workedSecondsTotal: workedSecondsTotal ?? this.workedSecondsTotal,
        pauseCount: pauseCount ?? this.pauseCount,
        reconfiguredCount: reconfiguredCount ?? this.reconfiguredCount,
        phaseEndsAtMs: phaseEndsAtMsClear != null
            ? null
            : (phaseEndsAtMs ?? this.phaseEndsAtMs),
      );
}

/// Lógica de transición de fases — función pura, testeable sin Flutter.
///
/// Devuelve el estado nuevo tras terminar la fase actual de [state].
/// - Fin de trabajo i (no último) → descanso i.
/// - Fin de descanso i → trabajo i+1.
/// - Fin del último trabajo → null: terminó el run, toca wrap-up.
FocusRunState? advancePhase(FocusRunState state) {
  final cfg = state.config;
  final phase = state.phase;

  if (phase is FocusWork) {
    if (phase.index >= cfg.intervalCount - 1) {
      return null; // fin del run → wrap-up
    }
    return state.copyWith(
      phase: FocusBreak(phase.index),
      remainingSeconds: cfg.breakSeconds,
      running: cfg.breakSeconds > 0,
      phaseEndsAtMsClear: true,
    );
  }

  if (phase is FocusBreak) {
    return state.copyWith(
      phase: FocusWork(phase.index + 1),
      remainingSeconds: _workSecondsFor(state, phase.index + 1),
      running: true,
      phaseEndsAtMsClear: true,
    );
  }

  return null;
}

/// Segundos de trabajo para el intervalo [index] (considera el resto
/// en el último intervalo, igual que FocusRunState._lastWorkSeconds).
int workSecondsForIndex(FocusConfig config, int index) {
  if (index < config.intervalCount - 1) return config.workSecondsPerInterval;
  final per = config.workSecondsPerInterval;
  final remainderSec = (config.totalMinutes % config.intervalCount) * 60;
  return per + remainderSec;
}

int _workSecondsFor(FocusRunState state, int index) =>
    workSecondsForIndex(state.config, index);
