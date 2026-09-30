import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/theme/terminal_theme.dart';
import '../../data/local/pomodoro_stats.dart';
import '../../data/models/category.dart';
import '../../data/models/pomodoro_preset.dart';
import '../../data/models/task.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/task_repository.dart';
import '../../notifications/local_notifications.dart';

// `PomodoroPreset` se re-exporta implícitamente vía el import para
// mantener compatibilidad con los call-sites existentes del feature.

// ── Sentinel re-export para los `builtIn` etc. ────────────────
// (Definidos en data/models/pomodoro_preset.dart.)

/// Tipo de sesión activa. Determina el color del anillo y la duración.
enum SessionKind { work, shortBreak, longBreak }

class PomodoroScreen extends ConsumerStatefulWidget {
  const PomodoroScreen({super.key});

  @override
  ConsumerState<PomodoroScreen> createState() => _PomodoroScreenState();
}

class _PomodoroScreenState extends ConsumerState<PomodoroScreen>
    with SingleTickerProviderStateMixin {
  PomodoroPreset _preset = PomodoroPreset.standard;

  late int _remaining = _preset.work * 60;
  bool _running = false;
  SessionKind _kind = SessionKind.work;
  int _cycleIndex = 0; // cuántos pomodoros (trabajos) se completaron en el ciclo actual (0..cyclesBeforeLong)
  Task? _selectedTask;

  // Hora ABSOLUTA de fin mientras _running. Todo el countdown se deriva
  // de acá (wall-clock): sobrevive backgrounds, freezes del SO y cambios
  // de tab — el tiempo restante nunca se "descuenta a ciegas".
  DateTime? _endsAt;
  // Guardia anti-reentrada: el tick, el lifecycle y el restore pueden
  // intentar finalizar la sesión al mismo tiempo.
  bool _finishing = false;
  late final AppLifecycleListener _lifecycleListener;

  // ── In-screen overlays ──────────────────────────────────
  // Antes usábamos showModalBottomSheet, pero el modal quedaba en el
  // tope del Navigator interno del ShellRoute y sobrevivía al
  // context.go('/calendar') → aparecía como "fantasma" sobre Calendario.
  // Solución: renderizar el sheet como overlay dentro del widget del
  // Pomodoro. Cuando GoRouter reemplaza la ruta interna (cambio de
  // tab), el State se dispone y el overlay se va con él.
  bool _pickerOpen = false;
  List<Task> _pickerTasks = const [];
  List<Category> _pickerCategories = const [];
  bool _presetOpen = false;

  Timer? _timer;
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat(reverse: true);

  // Paquete A: evita mostrar el diálogo de "tarea completada mid-session"
  // dos veces si el stream emite varios eventos seguidos antes de que
  // el user elija.
  bool _midSessionDialogShowing = false;

  @override
  void initState() {
    super.initState();
    // Hidratamos el preset desde el provider en el primer frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final saved = ref.read(pomodoroSelectedPresetProvider);
      setState(() {
        _preset = saved;
        if (_kind == SessionKind.work &&
            _remaining == PomodoroPreset.standard.work * 60 &&
            !_running) {
          _remaining = saved.work * 60;
        }
      });
    });
    // FIX: "Enviar a Focus" navega a /pomodoro?task=<id> pero nadie
    // leía ese parámetro de consulta → la tarea nunca quedaba auto-seleccionada.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final queryTaskId =
          GoRouterState.of(context).uri.queryParameters['task'];
      if (queryTaskId == null || queryTaskId.isEmpty) return;
      ref.read(taskRepositoryProvider).getAll().then((all) {
        if (!mounted) return;
        final match = all.where((t) => t.id == queryTaskId).firstOrNull;
        if (match != null && !_running) {
          setState(() => _selectedTask = match);
        }
      }).catchError((_) {});
    });
    // Sesión previa: auto-retoma las que estaban CORRIENDO (wall-clock)
    // y ofrece recuperar las pausadas. Ver _restoreOrResume.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _restoreOrResume();
    });
    // Lifecycle: al volver del background recalculamos el remaining
    // contra el reloj (los Timers no corren congelados); al pausar la
    // app persistimos el snapshot para sobrevivir un kill del proceso.
    _lifecycleListener = AppLifecycleListener(
      onResume: _onAppResumed,
      onPause: () {
        if (_running || _hasSessionSnapshotLocally) _persistSession();
      },
    );
  }

  bool get _hasSessionSnapshotLocally =>
      !_running && _remaining < _totalForKind;

  void _onAppResumed() {
    if (!_running || _endsAt == null || _finishing) return;
    final rem = _endsAt!.difference(DateTime.now()).inSeconds;
    setState(() => _remaining = rem.clamp(0, _totalForKind * 10));
    if (rem <= 0) _finishSession();
  }

  // Paquete B: id fijo para la notificación del pomodoro activo. Si
  // cambiamos de tarea sin pausar, cancelamos y reprogramamos con el
  // mismo id — así no acumulamos notifs fantasma.
  static const _sessionNotifId = 999999;

  @override
  void dispose() {
    _lifecycleListener.dispose();
    _timer?.cancel();
    _pulse.dispose();
    WakelockPlus.disable();
    // La sesión SOBREVIVE al cambio de tab / cierre de la app: si está
    // corriendo persistimos el endAt absoluto; si estaba pausada a mitad
    // de sesión re-persistimos para que al volver se siga ofreciendo.
    if (_running || _hasSessionSnapshotLocally) _persistSession();
    super.dispose();
  }

  // ── Persistencia de la sesión + notificación ──────────────

  /// Guarda un snapshot wall-clock. `endAtMs` es absoluto y no cambia
  /// mientras corre, así que no hace falta persistir cada tick.
  void _persistSession() {
    PomodoroSessionPersist.save(PomodoroSessionSnapshot(
      kind: _kind.name,
      totalSeconds: _totalForKind,
      startedAtMs: DateTime.now().millisecondsSinceEpoch,
      running: _running,
      endAtMs: _endsAt?.millisecondsSinceEpoch ??
          DateTime.now()
              .add(Duration(seconds: _remaining))
              .millisecondsSinceEpoch,
      pausedRemainingSec: _running ? 0 : _remaining,
      taskId: _selectedTask?.id ?? '',
      taskTitle: _selectedTask?.title ?? '',
      presetLabel: _preset.label,
      cycleIndex: _cycleIndex,
      cyclesBeforeLong: _preset.cyclesBeforeLong,
    ));
  }

  Future<void> _clearSession() async {
    await PomodoroSessionPersist.clear();
    await LocalNotifications.instance.cancel(_sessionNotifId);
  }

  Future<void> _scheduleEndNotification() async {
    final endAt =
        _endsAt ?? DateTime.now().add(Duration(seconds: _remaining));
    await LocalNotifications.instance.cancel(_sessionNotifId);
    final kindLabel = switch (_kind) {
      SessionKind.work => 'trabajo',
      SessionKind.shortBreak => 'descanso corto',
      SessionKind.longBreak => 'descanso largo',
    };
    final title = _selectedTask != null
        ? '${_selectedTask!.title} — listo'
        : 'Pomodoro listo';
    final body = switch (_kind) {
      SessionKind.work => 'Terminó tu sesión de $kindLabel.',
      SessionKind.shortBreak => 'Volvé al trabajo.',
      SessionKind.longBreak => 'Gran descanso listo, a darle.',
    };
    await LocalNotifications.instance.scheduleSessionEnd(
      id: _sessionNotifId,
      title: title,
      body: body,
      when: endAt,
    );
  }

  /// Al entrar al tab mira si quedó una sesión guardada:
  /// - Corriendo y vigente → auto-retoma silencioso (wall-clock).
  /// - Corriendo pero ya llegó a 0 → cuenta pomodoro + snackbar.
  /// - Pausada con tiempo → ofrece Recuperar/Descartar.
  /// - Muy vieja u otro día → limpia silencioso.
  Future<void> _restoreOrResume() async {
    final snap = await PomodoroSessionPersist.load();
    if (!mounted || snap == null) return;
    final now = DateTime.now();
    final started = DateTime.fromMillisecondsSinceEpoch(snap.startedAtMs);
    if (started.day != now.day ||
        started.month != now.month ||
        started.year != now.year) {
      await PomodoroSessionPersist.clear();
      return;
    }
    _applySnapshot(snap);
    final remaining = snap.remainingNow(now);
    if (snap.running) {
      if (remaining > 3) {
        setState(() {
          _running = true;
          _remaining = remaining;
          _endsAt = now.add(Duration(seconds: remaining));
        });
        if (_kind == SessionKind.work) WakelockPlus.enable();
        await _scheduleEndNotification();
        _startTicking();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('Sesión retomada — quedan ${_format(remaining)}'),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      if (remaining > -300) {
        await _clearSession();
        final wasWork = snap.kind == 'work';
        setState(() {
          _advanceKind(completed: wasWork);
          _remaining = _totalForKind;
          _endsAt = null;
          _running = false;
        });
        if (wasWork) {
          ref.read(pomodoroStatsProvider.notifier).incrementToday();
          if (snap.taskId.isNotEmpty) {
            ref
                .read(pomodoroStatsProvider.notifier)
                .incrementTask(snap.taskId);
          }
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(wasWork
                ? 'Tu pomodoro terminó mientras estabas fuera'
                : 'Tu descanso terminó — de vuelta al trabajo'),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      await PomodoroSessionPersist.clear();
      return;
    }
    if (remaining > 0) {
      await _showRestoreDialog(snap, remaining);
    } else {
      await PomodoroSessionPersist.clear();
    }
  }

  void _applySnapshot(PomodoroSessionSnapshot snap) {
    final kind = SessionKind.values.firstWhere(
      (k) => k.name == snap.kind,
      orElse: () => SessionKind.work,
    );
    setState(() {
      _kind = kind;
      _cycleIndex = snap.cycleIndex.clamp(0, snap.cyclesBeforeLong > 0 ? snap.cyclesBeforeLong - 1 : 3);
    });
    if (snap.taskId.isNotEmpty) {
      ref.read(taskRepositoryProvider).getAll().then((all) {
        if (!mounted) return;
        final match = all.where((t) => t.id == snap.taskId).firstOrNull;
        if (match != null) {
          setState(() => _selectedTask ??= match);
        }
      }).catchError((_) {});
    }
  }

  Future<void> _showRestoreDialog(
      PomodoroSessionSnapshot snap, int remainingSec) async {
    final mins = remainingSec ~/ 60;
    final secs = remainingSec % 60;
    final friendlyTime =
        mins > 0 ? '$mins min ${secs > 0 ? '$secs s' : ''}' : '$secs s';
    final kindLabel = switch (snap.kind) {
      'shortBreak' => 'descanso corto',
      'longBreak' => 'descanso largo',
      _ => 'trabajo',
    };
    final choice = await showDialog<_RestoreChoice>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.history),
        title: const Text('Sesión en pausa'),
        content: Text(
          'Tenías un $kindLabel pausado'
          '${snap.taskTitle.isNotEmpty ? ' para "${snap.taskTitle}"' : ''}.\n'
          'Quedan $friendlyTime.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _RestoreChoice.discard),
            child: const Text('Descartar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _RestoreChoice.restore),
            child: const Text('Recuperar'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == _RestoreChoice.restore) {
      setState(() {
        _remaining = remainingSec.clamp(0, snap.totalSeconds);
        _endsAt = null;
      });
      await _clearSession();
    } else if (choice == _RestoreChoice.discard) {
      setState(() {
        _remaining = _totalForKind;
      });
      await _clearSession();
    }
  }

  int get _totalForKind => switch (_kind) {
        SessionKind.work => _preset.work * 60,
        SessionKind.shortBreak => _preset.shortBreak * 60,
        SessionKind.longBreak => _preset.longBreak * 60,
      };

  Color get _accentForKind {
    return switch (_kind) {
      // Naranja de la casa para trabajo.
      SessionKind.work => TerminalTheme.accentOf(context),
      // Ámbar "construyendo" para descansos (misma rampa cálida, apagada).
      SessionKind.shortBreak => TerminalTheme.buildingOf(context),
      // Verde ok para el gran descanso.
      SessionKind.longBreak => TerminalTheme.okOf(context),
    };
  }

  String get _labelForKind => switch (_kind) {
        SessionKind.work => 'Trabajo',
        SessionKind.shortBreak => 'Descanso',
        SessionKind.longBreak => 'Descanso largo',
      };

  IconData get _iconForKind => switch (_kind) {
        SessionKind.work => Icons.work_outline,
        SessionKind.shortBreak => Icons.coffee_outlined,
        SessionKind.longBreak => Icons.self_improvement_outlined,
      };

  /// Inicia/pausa. Si no hay tarea seleccionada y está intentando
  /// INICIAR (no pausar), abre el picker para guiar al usuario.
  void _toggle() {
    if (!_running && _selectedTask == null) {
      _pickTask();
      return;
    }
    HapticFeedback.selectionClick();
    if (_running) {
      _timer?.cancel();
      WakelockPlus.disable();
      setState(() => _running = false);
      _persistSession();
      LocalNotifications.instance.cancel(_sessionNotifId);
    } else {
      setState(() => _running = true);
      _beginRunning();
    }
  }

  /// Pone la sesión a correr: fija `_endsAt` desde AHORA + remaining,
  /// persiste, agenda la notificación de fin y arranca el tick.
  void _beginRunning() {
    _timer?.cancel();
    _endsAt = DateTime.now().add(Duration(seconds: _remaining));
    if (_kind == SessionKind.work) {
      WakelockPlus.enable();
    }
    _persistSession();
    _scheduleEndNotification();
    _startTicking();
  }

  void _startTicking() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  /// Tick wall-clock: el remaining SIEMPRE se recalcula contra `_endsAt`
  /// (nunca se decrementa a ciegas). Si el SO congeló la app, al volver
  /// el número es correcto de todas formas.
  void _tick() {
    if (!mounted || !_running || _endsAt == null) return;
    final rem = _endsAt!.difference(DateTime.now()).inSeconds;
    setState(() => _remaining = rem);
    if (rem <= 0 && !_finishing) _finishSession();
  }

  void _reset() {
    HapticFeedback.lightImpact();
    _timer?.cancel();
    WakelockPlus.disable();
    setState(() {
      _running = false;
      _remaining = _totalForKind;
      _endsAt = null;
    });
    _clearSession();
  }

  void _skip() {
    HapticFeedback.lightImpact();
    _timer?.cancel();
    WakelockPlus.disable();
    setState(() {
      _running = false;
      _endsAt = null;
      _advanceKind(completed: false);
      _remaining = _totalForKind;
    });
    _clearSession();
  }

  /// Agrega N minutos al remaining. Si estaba corriendo extiende
  /// `_endsAt`; si estaba pausada arranca directo.
  void _extendSession() {
    final extra = ref.read(pomodoroIncrementProvider) * 60;
    HapticFeedback.selectionClick();
    if (_running) {
      setState(() {
        _remaining += extra;
        _endsAt = _endsAt!.add(Duration(seconds: extra));
      });
      _persistSession();
      _scheduleEndNotification();
    } else {
      setState(() {
        _remaining += extra;
        _running = true;
      });
      _beginRunning();
    }
  }

  Future<void> _finishSession() async {
    if (_finishing) return;
    _finishing = true;
    try {
      _timer?.cancel();
      HapticFeedback.heavyImpact();
      final wasWork = _kind == SessionKind.work;
      final taskAtFinish = _selectedTask;
      await _clearSession();
      _advanceKind(completed: wasWork);
      setState(() {
        _running = false;
        _remaining = _totalForKind;
        _endsAt = null;
      });
      WakelockPlus.disable();
      if (wasWork) {
        ref.read(pomodoroStatsProvider.notifier).incrementToday();
        if (taskAtFinish != null) {
          ref.read(pomodoroStatsProvider.notifier).incrementTask(taskAtFinish.id);
        }
        if (taskAtFinish != null && !taskAtFinish.isCompleted && mounted) {
          await _maybeOfferComplete(taskAtFinish);
        }
      }
      if (!mounted) return;
      final msg = _kind == SessionKind.work
          ? '¡Vuelta al trabajo!'
          : (_kind == SessionKind.shortBreak
              ? 'Tomá un respiro'
              : 'Gran descanso');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(_iconForKind, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text(msg)),
            ],
          ),
          backgroundColor: _accentForKind,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      _finishing = false;
    }
  }

  Future<void> _maybeOfferComplete(Task task) async {
    final stats = ref.read(pomodoroStatsProvider);
    final autoComplete = stats.autoComplete;
    final choice = autoComplete
        ? _PostWorkChoice.complete
        : await showDialog<_PostWorkChoice>(
            context: context,
            builder: (_) => AlertDialog(
              icon: Icon(Icons.task_alt,
                  color: Theme.of(context).colorScheme.primary),
              title: const Text('¡Pomodoro terminado!'),
              content: Text(
                  '¿Qué hago con "${task.title}"?\n\n'
                  '· Completar: marco la tarea como hecha\n'
                  '· Seguir: descanso y vuelvo\n'
                  '· Otra pomodoro ya: salto al próximo trabajo'),
              actions: [
                TextButton(
                  onPressed: () =>
                      Navigator.pop(context, _PostWorkChoice.skipBreak),
                  child: const Text('Otra pomodoro ya'),
                ),
                TextButton(
                  onPressed: () =>
                      Navigator.pop(context, _PostWorkChoice.continueBreak),
                  child: const Text('Seguir'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(context, _PostWorkChoice.complete),
                  child: const Text('Completar'),
                ),
              ],
            ),
          ) ??
            _PostWorkChoice.continueBreak;

    if (!mounted) return;
    if (choice == _PostWorkChoice.complete) {
      // Completa Y mueve al fondo (misma política que Mi Día / Tareas).
      final all = await ref.read(taskRepositoryProvider).getAll();
      await ref
          .read(taskRepositoryProvider)
          .toggleWithReorder(task.id, true, all);
      ref.invalidate(tasksStreamProvider);
    } else if (choice == _PostWorkChoice.skipBreak) {
      // Paquete C: saltar el break y arrancar la próxima sesión de
      // trabajo al toque. _advanceKind ya nos dejó en shortBreak; lo
      // pisamos a work y reseteamos el remaining.
      setState(() {
        _kind = SessionKind.work;
        _remaining = _totalForKind;
      });
      // Pequeño feedback háptico y toast para que se note el salto.
      HapticFeedback.selectionClick();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Break saltado — al próximo trabajo'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
    // _PostWorkChoice.continueBreak no hace nada extra: dejamos que el
    // _advanceKind siga su curso (ya pasamos a shortBreak en
    // _finishSession). El snackbar principal lo muestra _finishSession
    // al volver de este await.
  }

  // ── Paquete A: lifecycle de tarea mid-session ────────────

  /// Callback del `ref.listen(tasksStreamProvider)`. Detecta:
  /// - tarea eliminada: limpiamos selección silenciosamente
  /// - tarea completada mientras corre: pausamos y preguntamos al user
  Task? _findCurrent(String id, List<Task> all) {
    for (final t in all) {
      if (t.id == id) return t;
    }
    return null;
  }

  void _onTasksChanged(List<Task> all) {
    final selected = _selectedTask;
    if (selected == null) return;
    final current = _findCurrent(selected.id, all);
    if (current == null) {
      // La tarea fue eliminada (en este u otro dispositivo).
      if (!_running) {
        setState(() => _selectedTask = null);
        return;
      }
      // Si está corriendo: pausamos, limpiamos y avisamos.
      _timer?.cancel();
      setState(() {
        _running = false;
        _selectedTask = null;
        _remaining = _totalForKind;
      });
      WakelockPlus.disable();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La tarea fue eliminada — sesión reiniciada'),
          duration: Duration(seconds: 3),
        ),
      );
    } else if (current.isCompleted && !selected.isCompleted) {
      // Marcaron como hecha en otro lado (Mi Día, Tareas, etc).
      if (_midSessionDialogShowing) return;
      _handleCompletedMidSession(current);
    }
  }

  Future<void> _handleCompletedMidSession(Task current) async {
    _midSessionDialogShowing = true;
    final wasRunning = _running;
    if (wasRunning) {
      // Pausamos sin disparar haptic ni feedback (lo hacemos acá abajo).
      _timer?.cancel();
      WakelockPlus.disable();
      setState(() {
        _running = false;
        _remaining = _totalForKind;
      });
    }
    if (!mounted) {
      _midSessionDialogShowing = false;
      return;
    }
    final choice = await showDialog<_MidSessionChoice>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        icon: Icon(Icons.task_alt,
            color: Theme.of(context).colorScheme.primary),
        title: const Text('¡Tarea completada!'),
        content: Text(
            '"${current.title}" se marcó como hecha desde otro lado. ¿Qué hago con el timer?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _MidSessionChoice.stop),
            child: const Text('Detener'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _MidSessionChoice.change),
            child: const Text('Cambiar tarea'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _MidSessionChoice.keep),
            child: const Text('Seguir'),
          ),
        ],
      ),
    );
    _midSessionDialogShowing = false;
    if (!mounted) return;
    switch (choice) {
      case _MidSessionChoice.keep:
        setState(() => _selectedTask = current);
        if (wasRunning) {
          HapticFeedback.selectionClick();
          setState(() => _running = true);
          _beginRunning();
        }
        break;
      case _MidSessionChoice.change:
        setState(() => _selectedTask = null);
        _pickTask();
        break;
      case _MidSessionChoice.stop:
        _reset();
        break;
      case null:
        // No se eligió nada (barrierDismissible:false evita esto normalmente,
        // pero por las dudas dejamos el timer pausado).
        break;
    }
  }

  void _advanceKind({required bool completed}) {
    // Después de un trabajo: descanso corto, o largo si completó el ciclo.
    // Después de un descanso: vuelve a trabajo.
    if (_kind == SessionKind.work && completed) {
      _cycleIndex++;
      if (_cycleIndex >= _preset.cyclesBeforeLong) {
        _kind = SessionKind.longBreak;
        _cycleIndex = 0;
      } else {
        _kind = SessionKind.shortBreak;
      }
    } else if (_kind == SessionKind.work) {
      _kind = SessionKind.shortBreak;
    } else {
      _kind = SessionKind.work;
    }
  }

  Future<void> _pickPreset() async {
    if (_running) return;
    setState(() => _presetOpen = true);
  }

  void _onPresetResult(_PresetPickResult result) {
    setState(() => _presetOpen = false);
    if (result.preset != null) {
      setState(() {
        _preset = result.preset!;
        _kind = SessionKind.work;
        _remaining = _totalForKind;
      });
      // Persistir la selección para que sobreviva al cerrar la app.
      ref.read(pomodoroSelectedPresetProvider.notifier).save(result.preset!);
    }
    if (result.autoComplete != null) {
      ref.read(pomodoroStatsProvider.notifier).setAutoComplete(
          result.autoComplete!);
    }
    if (result.incrementMinutes != null) {
      ref.read(pomodoroIncrementProvider.notifier)
          .save(result.incrementMinutes!);
    }
  }

  Future<void> _pickTask() async {
    final tasks = await ref.read(taskRepositoryProvider).getAll();
    final categories = await ref.read(categoryRepositoryProvider).getAll();
    if (!mounted) return;
    setState(() {
      _pickerTasks = tasks.where((t) => !t.isCompleted).toList();
      _pickerCategories = categories;
      _pickerOpen = true;
    });
  }

  void _onPickerResult(_TaskPickResult result) {
    setState(() => _pickerOpen = false);
    if (result.cleared) {
      setState(() => _selectedTask = null);
    } else if (result.task != null) {
      setState(() => _selectedTask = result.task);
    }
    // Si result.task == null y !cleared → dismiss sin elección, no tocamos nada.
  }

  String _format(int s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final r = (s % 60).toString().padLeft(2, '0');
    return '$m:$r';
  }

  @override
  Widget build(BuildContext context) {
    // Paquete A: detectar cambios en la tarea seleccionada mientras
    // corría la sesión (completada o eliminada en otro lugar). Usamos
    // listen (no watch) para no rebuild por cada cambio irrelevante.
    ref.listen<AsyncValue<List<Task>>>(tasksStreamProvider, (prev, next) {
      next.whenData((all) => _onTasksChanged(all));
    });

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final progress =
        (_totalForKind - _remaining) / _totalForKind.clamp(1, 999999);
    final accent = _accentForKind;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Stack(
          children: [
            // Contenido principal
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                children: [
              // ── Header ──────────────────────────────────
              Row(
                children: [
                  Text('Pomodoro',
                      style: theme.textTheme.displaySmall),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Configuración',
                    onPressed: _running ? null : _pickPreset,
                    icon: const Icon(Icons.tune),
                  ),
                ],
              ),
              // ── Cycle indicator (4 dots) ─────────────────
              _CycleDots(
                total: _preset.cyclesBeforeLong,
                done: _cycleIndex,
                isBreak:
                    _kind == SessionKind.shortBreak ||
                        _kind == SessionKind.longBreak,
              ),
              const SizedBox(height: 12),
              // ── Selected task chip ──────────────────────
              if (_selectedTask != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Chip(
                    avatar: const Icon(Icons.task_alt, size: 16),
                    label: Text(
                      _selectedTask!.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onDeleted: _running
                        ? null
                        : () => setState(() => _selectedTask = null),
                  ),
                ),

              // ── Timer ring ───────────────────────────────
              Expanded(
                child: Center(
                  child: AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, _) {
                      final pulseScale = _running
                          ? 1.0 + (_pulse.value * 0.02)
                          : 1.0;
                      return Transform.scale(
                        scale: pulseScale,
                        child: SizedBox(
                          width: 280,
                          height: 280,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Halo sutil cuando está corriendo
                              if (_running)
                                Container(
                                  width: 280,
                                  height: 280,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: accent.withValues(alpha: 0.06),
                                  ),
                                ),
                              SizedBox(
                                width: 260,
                                height: 260,
                                child: CircularProgressIndicator(
                                  value: progress,
                                  strokeWidth: 12,
                                  strokeCap: StrokeCap.square,
                                  backgroundColor:
                                      TerminalTheme.lineOf(context),
                                  valueColor: AlwaysStoppedAnimation(accent),
                                ),
                              ),
                              // Recuadro central tipo consola.
                              Container(
                                width: 232,
                                height: 232,
                                decoration: BoxDecoration(
                                  color: TerminalTheme.panelOf(context),
                                  border: Border.all(
                                    color: TerminalTheme.lineOf(context),
                                    width: 1,
                                  ),
                                ),
                                alignment: Alignment.center,
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Cuadradito de estado como los
                                        // labels del login.
                                        Container(
                                          width: 7,
                                          height: 7,
                                          color: accent,
                                        ),
                                        const SizedBox(width: 7),
                                        Text(
                                          _labelForKind.toUpperCase(),
                                          style: TextStyle(
                                            fontFamily:
                                                TerminalTheme.monoFamily,
                                            fontSize: 11.5,
                                            letterSpacing: 1.2,
                                            color: accent,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      _format(_remaining),
                                      style: TextStyle(
                                        fontFamily:
                                            TerminalTheme.pixelFamily,
                                        fontSize: 48,
                                        height: 1.1,
                                        color: TerminalTheme.fgOf(context),
                                        fontFeatures: [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      '${(_totalForKind - _remaining) ~/ 60 + (_totalForKind - _remaining) % 60 ~/ 60} '
                                      'de ${_totalForKind ~/ 60} min',
                                      style: TextStyle(
                                        fontFamily:
                                            TerminalTheme.monoFamily,
                                        fontSize: 12,
                                        color:
                                            TerminalTheme.mutedOf(context),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              // ── Stats ───────────────────────────────────
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: TerminalTheme.panelOf(context),
                  border: Border.all(color: TerminalTheme.lineOf(context)),
                ),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  alignment: WrapAlignment.spaceEvenly,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _Stat(
                      icon: Icons.local_fire_department_outlined,
                      label: 'Hoy',
                      value: '${ref.watch(pomodoroStatsProvider).today}',
                      color: TerminalTheme.accentOf(context),
                    ),
                    _Stat(
                      icon: Icons.bolt_outlined,
                      label: 'Racha',
                      value: '${ref.watch(pomodoroStatsProvider.notifier).currentStreak()}d',
                      color: TerminalTheme.buildingOf(context),
                    ),
                    _Stat(
                      icon: Icons.timer_outlined,
                      label: 'Preset',
                      value: _preset.label,
                      color: TerminalTheme.fgOf(context),
                    ),
                    _Stat(
                      icon: Icons.loop,
                      label: 'Ciclo',
                      value:
                          '${_cycleIndex.clamp(0, _preset.cyclesBeforeLong)}/${_preset.cyclesBeforeLong}',
                      color: accent,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Action row ──────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _SquareAction(
                    icon: Icons.refresh,
                    tooltip: 'Reiniciar',
                    onPressed: _reset,
                  ),
                  _PlayPauseButton(
                    running: _running,
                    accent: accent,
                    enabled: _selectedTask != null,
                    onPressed: _toggle,
                    onDisabledTap: _pickTask,
                  ),
                  _SquareAction(
                    icon: Icons.skip_next,
                    tooltip: 'Saltar',
                    onPressed: _skip,
                  ),
                ],
              ),
              // Paquete C: chip "+N min" sólo mientras corre, para
              // extender la sesión actual sin tener que esperar a que
              // termine (caso típico: "necesito un poco más"). El valor
              // viene de `pomodoroIncrementProvider` y el user lo
              // configura desde el overlay de preset (default 5).
              if (_running)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: ActionChip(
                    avatar: Icon(Icons.add, size: 16, color: accent),
                    label: Text(
                      '+${ref.watch(pomodoroIncrementProvider)} min',
                    ),
                    labelStyle: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w600,
                    ),
                    side: BorderSide(color: accent.withValues(alpha: 0.4)),
                    backgroundColor: accent.withValues(alpha: 0.08),
                    onPressed: _extendSession,
                  ),
                ),
              const SizedBox(height: 8),

              // ── Pick task ───────────────────────────────
              // Cuando no hay tarea: CTA prominente (FilledButton) — es
              // prerrequisito para arrancar. Cuando ya hay: cambio sutil.
              if (_selectedTask == null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: FilledButton.icon(
                    onPressed: _running ? null : _pickTask,
                    icon: const Icon(Icons.task_alt),
                    label: const Text('Elegí una tarea para empezar'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                    ),
                  ),
                )
              else
                TextButton.icon(
                  onPressed: _running ? null : _pickTask,
                  icon: const Icon(Icons.swap_horiz),
                  label: Text('Cambiar de tarea'),
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.primary,
                  ),
                ),
                ],
              ),
            ),
            // ── Overlays in-screen ────────────────────────────
            // Ver nota arriba sobre por qué NO usamos showModalBottomSheet.
            if (_pickerOpen)
              Positioned.fill(
                child: _TaskPickerOverlay(
                  tasks: _pickerTasks,
                  categories: _pickerCategories,
                  current: _selectedTask,
                  onResult: _onPickerResult,
                ),
              ),
            if (_presetOpen)
              Positioned.fill(
                child: _PresetOverlay(
                  preset: _preset,
                  autoComplete: ref.watch(pomodoroStatsProvider).autoComplete,
                  onResult: _onPresetResult,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CycleDots extends StatelessWidget {
  const _CycleDots({
    required this.total,
    required this.done,
    required this.isBreak,
  });
  final int total;
  final int done;
  final bool isBreak;

  @override
  Widget build(BuildContext context) {
    final accent = TerminalTheme.accentOf(context);
    final line = TerminalTheme.lineOf(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < total; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              // Cuadraditos: los completos llenos, el activo a media
              // tinta, los futuros en color de línea. Cero redondeos.
              width: i == done && isBreak ? 22 : 10,
              height: 10,
              decoration: BoxDecoration(
                color: i < done
                    ? accent
                    : (i == done
                        ? accent.withValues(alpha: 0.4)
                        : line),
              ),
            ),
          ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontFamily: TerminalTheme.monoFamily,
                    fontSize: 11,
                    letterSpacing: 0.6,
                    color: TerminalTheme.mutedOf(context),
                    fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                fontFamily: TerminalTheme.pixelFamily,
                fontSize: 15,
                color: color,
                fontWeight: FontWeight.w400)),
      ],
    );
  }
}

/// Acción secundaria cuadrada: panel con borde 1px, sin relleno
/// alrededor. Cero redondeos, cero sombras.
class _SquareAction extends StatelessWidget {
  const _SquareAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: TerminalTheme.panelOf(context),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        child: InkWell(
          onTap: onPressed,
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              border: Border.all(color: TerminalTheme.lineOf(context)),
            ),
            child: Icon(
              icon,
              color: TerminalTheme.fgOf(context),
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({
    required this.running,
    required this.accent,
    required this.onPressed,
    required this.enabled,
    this.onDisabledTap,
  });
  final bool running;
  final Color accent;
  final VoidCallback onPressed;
  final bool enabled;
  // Se llama cuando el botón está deshabilitado y el usuario lo toca.
  // Útil para abrir el picker de tarea automáticamente cuando falta.
  final VoidCallback? onDisabledTap;

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? accent
        : TerminalTheme.lineOf(context);
    final iconColor = enabled
        ? (Theme.of(context).brightness == Brightness.dark
            ? TerminalTheme.nightBg
            : TerminalTheme.dayBg)
        : TerminalTheme.mutedOf(context);
    return Tooltip(
      message: enabled
          ? (running ? 'Pausar' : 'Iniciar')
          : 'Elegí una tarea primero',
      child: SizedBox(
        width: 80,
        height: 80,
        child: Material(
          color: color,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          elevation: 0,
          child: InkWell(
            onTap: enabled ? onPressed : onDisabledTap,
            child: Icon(
              running ? Icons.pause : Icons.play_arrow,
              color: iconColor,
              size: 44,
            ),
          ),
        ),
      ),
    );
  }
}

/// Overlay in-screen para elegir la tarea. NO usa showModalBottomSheet
/// (ese quedaba en el tope del Navigator y sobrevivía al cambio de tab).
/// Renderiza un sheet con backdrop scrim al tope de la pantalla. Cuando
/// el State del Pomodoro se dispone (porque GoRouter reemplazó la ruta
/// interna al cambiar de tab), el overlay se va con él automáticamente.
class _TaskPickerOverlay extends ConsumerStatefulWidget {
  const _TaskPickerOverlay({
    required this.tasks,
    required this.categories,
    required this.current,
    required this.onResult,
  });
  final List<Task> tasks;
  final List<Category> categories;
  final Task? current;
  final void Function(_TaskPickResult) onResult;

  @override
  ConsumerState<_TaskPickerOverlay> createState() => _TaskPickerOverlayState();
}

class _TaskPickerOverlayState extends ConsumerState<_TaskPickerOverlay> {
  String _filter = '';
  bool _creating = false;

  /// Abre un mini diálogo para crear una tarea rápida (sólo título +
  /// categoría). Devuelve la Task creada o null si el user canceló.
  Future<Task?> _quickCreate() async {
    setState(() => _creating = true);
    final created = await showDialog<Task>(
      context: context,
      builder: (_) => _QuickCreateTaskDialog(
        categories: widget.categories,
      ),
    );
    if (!mounted) return null;
    setState(() => _creating = false);
    return created;
  }

  Future<void> _onCreatePressed() async {
    final created = await _quickCreate();
    if (!mounted || created == null) return;
    // Invalidar el stream para que el provider refresque y la nueva
    // tarea aparezca si la UI está observando.
    ref.invalidate(tasksStreamProvider);
    widget.onResult(_TaskPickResult.task(created));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final catById = {for (final c in widget.categories) c.id: c};
    final filtered = widget.tasks
        .where((t) =>
            _filter.isEmpty ||
            t.title.toLowerCase().contains(_filter.toLowerCase()))
        .toList();

    return Stack(
      children: [
        // Backdrop: tap dismiss
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onResult(const _TaskPickResult()),
            child: Container(color: Colors.black.withValues(alpha: 0.5)),
          ),
        ),
        // Sheet anclado abajo
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Material(
                color: Theme.of(context).scaffoldBackgroundColor,
                elevation: 8,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: scheme.outline.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Cerrar',
                            onPressed: () => widget.onResult(
                                const _TaskPickResult()),
                            icon: const Icon(Icons.close),
                          ),
                          const Expanded(
                            child: Center(
                              child: Text('Enfocate en',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ),
                          const SizedBox(width: 48),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        autofocus: false,
                        decoration: InputDecoration(
                          hintText: 'Buscar tarea...',
                          prefixIcon: const Icon(Icons.search),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.zero,
                          ),
                        ),
                        onChanged: (v) => setState(() => _filter = v),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.5,
                      ),
                      child: filtered.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    widget.tasks.isEmpty
                                        ? 'No hay tareas pendientes'
                                        : 'Sin coincidencias',
                                    style: TextStyle(
                                        color: scheme.onSurfaceVariant),
                                  ),
                                  if (widget.tasks.isEmpty) ...[
                                    const SizedBox(height: 12),
                                    FilledButton.icon(
                                      onPressed:
                                          _creating ? null : _onCreatePressed,
                                      icon: _creating
                                          ? const SizedBox(
                                              width: 14,
                                              height: 14,
                                              child:
                                                  CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(Icons.add),
                                      label: const Text(
                                          'Crear tarea rápida'),
                                    ),
                                  ],
                                ],
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: filtered.length +
                                  (widget.current == null ? 0 : 1),
                              itemBuilder: (_, i) {
                                if (widget.current != null && i == 0) {
                                  return ListTile(
                                    leading: Icon(Icons.clear,
                                        color: scheme.onSurfaceVariant),
                                    title: Text('Quitar selección',
                                        style: TextStyle(
                                            color:
                                                scheme.onSurfaceVariant)),
                                    onTap: () => widget.onResult(
                                        _TaskPickResult.cleared()),
                                  );
                                }
                                final t = filtered[widget.current == null
                                    ? i
                                    : i - 1];
                                final cat = catById[t.categoryId];
                                final selected =
                                    widget.current?.id == t.id;
                                return ListTile(
                                  selected: selected,
                                  selectedTileColor: scheme.primaryContainer
                                      .withValues(alpha: 0.3),
                                  leading: cat != null
                                      ? CircleAvatar(
                                          radius: 8,
                                          backgroundColor:
                                              _parseColor(cat.color),
                                        )
                                      : const CircleAvatar(
                                          radius: 8,
                                          child: SizedBox.shrink()),
                                  title: Text(t.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  subtitle: t.hasSubtasks
                                      ? Text(
                                          '${t.subtaskCount} subtareas')
                                      : null,
                                  trailing: selected
                                      ? Icon(Icons.check,
                                          color: scheme.primary)
                                      : null,
                                  onTap: () => widget.onResult(
                                      _TaskPickResult.task(t)),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Resultado del picker de tarea. Tres estados:
/// - `_TaskPickResult(task: null, cleared: false)` (empty) → usuario
///   descartó (X, drag, tap afuera) → NO se modifica `_selectedTask`.
/// - `_TaskPickResult.cleared()` → opción "Quitar selección" →
///   `_selectedTask` pasa a null.
/// - `_TaskPickResult.task(t)` → eligió una tarea.
class _TaskPickResult {
  const _TaskPickResult({this.task, this.cleared = false});
  const _TaskPickResult.task(Task t) : this(task: t);
  const _TaskPickResult.cleared() : this(cleared: true);
  final Task? task;
  final bool cleared;
}

/// Resultado del sheet de preset. Cualquiera de los campos puede haber
/// cambiado (o ninguno, si fue dismiss). El handler aplica sólo lo
/// que vino cambiado.
class _PresetPickResult {
  const _PresetPickResult({this.preset, this.autoComplete, this.incrementMinutes});
  final PomodoroPreset? preset;
  final bool? autoComplete;
  final int? incrementMinutes;
}

/// Paquete A: opciones cuando la tarea seleccionada se marca como
/// completada mientras corre un pomodoro.
enum _MidSessionChoice { keep, change, stop }

/// Paquete B: opciones del diálogo de recuperar sesión al reabrir la app.
enum _RestoreChoice { restore, discard }

/// Paquete C: opciones del diálogo post-pomodoro cuando se completa
/// un trabajo. `complete` = marcar la tarea hecha. `continueBreak` =
/// tomar el descanso corto/largo correspondiente. `skipBreak` =
/// saltar al próximo trabajo sin break.
enum _PostWorkChoice { complete, continueBreak, skipBreak }

/// Overlay in-screen de configuración del Pomodoro (preset + toggle
/// auto-completar). Misma justificación que _TaskPickerOverlay: no usa
/// showModalBottomSheet para que se cierre al cambiar de tab.
class _PresetOverlay extends ConsumerStatefulWidget {
  const _PresetOverlay({
    required this.preset,
    required this.autoComplete,
    required this.onResult,
  });
  final PomodoroPreset preset;
  final bool autoComplete;
  final void Function(_PresetPickResult) onResult;

  @override
  ConsumerState<_PresetOverlay> createState() => _PresetOverlayState();
}

class _PresetOverlayState extends ConsumerState<_PresetOverlay> {
  late PomodoroPreset _selected = widget.preset;
  late bool _auto = widget.autoComplete;
  late int _increment;
  late TextEditingController _workCtrl;
  late TextEditingController _shortCtrl;
  late TextEditingController _longCtrl;
  late TextEditingController _cyclesCtrl;

  /// Opciones válidas para el chip "+N min". Cada paso es razonable
  /// para extender un pomodoro (1 min casi no se nota, 10 ya es bastante).
  static const _incrementOptions = [1, 2, 5, 10];

  @override
  void initState() {
    super.initState();
    // Hidratamos desde el provider (puede aún no tener datos).
    final cfg = ref.read(pomodoroCustomProvider);
    final storedIncrement = ref.read(pomodoroIncrementProvider);
    _increment = _incrementOptions.contains(storedIncrement)
        ? storedIncrement
        : 5;
    // Si el preset actual es el custom sentinel, lo mantenemos seleccionado
    // con los valores del provider.
    _workCtrl = TextEditingController(text: cfg.work.toString());
    _shortCtrl = TextEditingController(text: cfg.shortBreak.toString());
    _longCtrl = TextEditingController(text: cfg.longBreak.toString());
    _cyclesCtrl = TextEditingController(text: cfg.cyclesBeforeLong.toString());
  }

  @override
  void dispose() {
    _workCtrl.dispose();
    _shortCtrl.dispose();
    _longCtrl.dispose();
    _cyclesCtrl.dispose();
    super.dispose();
  }

  void _selectCustom() {
    setState(() {
      _selected = PomodoroPreset.customSentinel;
    });
  }

  void _apply() {
    final isCustom = _selected.isCustom;
    if (isCustom) {
      final work = int.tryParse(_workCtrl.text) ?? 30;
      final shortBreak = int.tryParse(_shortCtrl.text) ?? 5;
      final longBreak = int.tryParse(_longCtrl.text) ?? 15;
      final cycles = int.tryParse(_cyclesCtrl.text) ?? 4;
      final config = PomodoroCustomConfig(
        work: work.clamp(1, 180),
        shortBreak: shortBreak.clamp(1, 60),
        longBreak: longBreak.clamp(1, 90),
        cyclesBeforeLong: cycles.clamp(2, 10),
      );
      // Persistir y construir el preset con los valores ya saneados.
      ref.read(pomodoroCustomProvider.notifier).save(config);
      widget.onResult(_PresetPickResult(
        preset: PomodoroPreset(
          'Personalizado',
          config.work,
          config.shortBreak,
          config.longBreak,
          config.cyclesBeforeLong,
        ),
        autoComplete: _auto,
        incrementMinutes: _increment,
      ));
    } else {
      widget.onResult(_PresetPickResult(
        preset: _selected,
        autoComplete: _auto,
        incrementMinutes: _increment,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onResult(const _PresetPickResult()),
            child: Container(color: Colors.black.withValues(alpha: 0.5)),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            child: Material(
              color: Theme.of(context).scaffoldBackgroundColor,
              elevation: 8,
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24)),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: scheme.outline.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text('Configuración',
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600)),
                          ),
                          IconButton(
                            tooltip: 'Cerrar',
                            onPressed: () => widget.onResult(
                                const _PresetPickResult()),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    for (final p in PomodoroPreset.builtIn)
                      RadioListTile<PomodoroPreset>(
                        title: Text(p.label),
                        subtitle: Text(
                            '${p.work}min trabajo · ${p.shortBreak}min descanso · ${p.longBreak}min largo'),
                        value: p,
                        groupValue:
                            _selected.isCustom ? null : _selected,
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _selected = v);
                        },
                      ),
                    RadioListTile<PomodoroPreset>(
                      title: const Text('Personalizado'),
                      subtitle: Text(
                        _selected.isCustom
                            ? 'Configurá las duraciones abajo'
                            : 'Configurar manualmente',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                      secondary: Icon(Icons.tune, color: scheme.primary),
                      value: PomodoroPreset.customSentinel,
                      groupValue: _selected.isCustom
                          ? PomodoroPreset.customSentinel
                          : _selected,
                      onChanged: (_) => _selectCustom(),
                    ),
                    if (_selected.isCustom) _CustomFields(
                      workCtrl: _workCtrl,
                      shortCtrl: _shortCtrl,
                      longCtrl: _longCtrl,
                      cyclesCtrl: _cyclesCtrl,
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text('Auto-completar tarea'),
                      subtitle: const Text(
                          'Marca la tarea como hecha al terminar el pomodoro'),
                      value: _auto,
                      onChanged: (v) => setState(() => _auto = v),
                    ),
                    // Incremento configurable del chip "+N min". Chips
                    // segmentados: 1 / 2 / 5 / 10 min. Default 5.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Extender sesión',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Cuánto suma el botón "+N min" cuando necesitás un poco más',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              for (final n in _incrementOptions)
                                ChoiceChip(
                                  label: Text('+$n min'),
                                  selected: _increment == n,
                                  onSelected: (_) =>
                                      setState(() => _increment = n),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: FilledButton(
                        onPressed: _apply,
                        child: const Text('Aplicar'),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

Color _parseColor(String h) =>
    Color(int.parse(h.replaceFirst('#', '0xFF')));

/// Campos editables del preset Personalizado: trabajo, descanso corto,
/// descanso largo, ciclos antes del descanso largo. Validación
/// soft (clamp) en _apply del _PresetOverlayState.
class _CustomFields extends StatelessWidget {
  const _CustomFields({
    required this.workCtrl,
    required this.shortCtrl,
    required this.longCtrl,
    required this.cyclesCtrl,
  });
  final TextEditingController workCtrl;
  final TextEditingController shortCtrl;
  final TextEditingController longCtrl;    final TextEditingController cyclesCtrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    InputDecoration deco(String label, String hint) => InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
          ),
          suffixText: 'min',
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: TerminalTheme.panelOf(context),
          border: Border.all(color: TerminalTheme.lineOf(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: workCtrl,
                    keyboardType: TextInputType.number,
                    decoration: deco('Trabajo', '25'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: shortCtrl,
                    keyboardType: TextInputType.number,
                    decoration: deco('Descanso', '5'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: longCtrl,
                    keyboardType: TextInputType.number,
                    decoration: deco('Descanso largo', '15'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: cyclesCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Ciclos',
                      hintText: '4',
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Trabajo/descanso en minutos. Ciclos: pomodoros entre descansos largos.',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paquete A: mini-diálogo para crear una tarea rápida desde el picker
/// del Pomodoro cuando no hay tareas pendientes. Sólo pide título y
/// categoría. La tarea queda creada y se devuelve al caller para que
/// la use como `_selectedTask`.
class _QuickCreateTaskDialog extends ConsumerStatefulWidget {
  const _QuickCreateTaskDialog({required this.categories});
  final List<Category> categories;

  @override
  ConsumerState<_QuickCreateTaskDialog> createState() =>
      _QuickCreateTaskDialogState();
}

class _QuickCreateTaskDialogState
    extends ConsumerState<_QuickCreateTaskDialog> {
  final _ctrl = TextEditingController();
  String? _categoryId;
  bool _saving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _ctrl.text.trim();
    if (title.isEmpty) return;
    final catId =
        (_categoryId == null || _categoryId!.isEmpty) ? null : _categoryId;
    setState(() => _saving = true);
    try {
      final created = await ref.read(taskRepositoryProvider).create(
            title: title,
            categoryId: catId,
          );
      if (created.isLocal) {
        await ref.read(taskRepositoryProvider).upsertLocal(created);
      }
      ref.invalidate(tasksStreamProvider);
      ref.invalidate(cachedTasksStreamProvider);
      ref.invalidate(categoriesStreamProvider);
      if (mounted) Navigator.of(context).pop(created);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cats = widget.categories;
    return AlertDialog(
      title: const Text('Tarea rápida'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _ctrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Título'),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _categoryId ?? '',
            decoration:
                const InputDecoration(labelText: 'Categoría (opcional)'),
            items: [
              const DropdownMenuItem(
                value: '',
                child: Text('Sin categoría',
                    style: TextStyle(fontStyle: FontStyle.italic)),
              ),
              for (final c in cats)
                DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: (v) => setState(() => _categoryId = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Crear'),
        ),
      ],
    );
  }
}