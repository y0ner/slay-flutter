import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/pomodoro_stats.dart';
import '../../data/models/category.dart';
import '../../data/models/task.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/task_repository.dart';

/// Preset configurable de duración. Las duraciones están en minutos.
class PomodoroPreset {
  const PomodoroPreset(this.label, this.work, this.shortBreak, this.longBreak,
      this.cyclesBeforeLong);
  final String label;
  final int work;
  final int shortBreak;
  final int longBreak;
  final int cyclesBeforeLong;

  static const standard =
      PomodoroPreset('Estándar', 25, 5, 15, 4);
  static const short = PomodoroPreset('Corto', 15, 3, 10, 4);
  static const long = PomodoroPreset('Largo', 50, 10, 20, 4);

  static const all = [standard, short, long];
}

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

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  int get _totalForKind => switch (_kind) {
        SessionKind.work => _preset.work * 60,
        SessionKind.shortBreak => _preset.shortBreak * 60,
        SessionKind.longBreak => _preset.longBreak * 60,
      };

  Color get _accentForKind {
    final scheme = Theme.of(context).colorScheme;
    return switch (_kind) {
      SessionKind.work => scheme.primary,
      SessionKind.shortBreak => const Color(0xFFFB923C), // orange-400
      SessionKind.longBreak => const Color(0xFF60A5FA), // blue-400
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

  void _toggle() {
    HapticFeedback.selectionClick();
    setState(() => _running = !_running);
    _timer?.cancel();
    if (_running) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {
          _remaining -= 1;
          if (_remaining <= 0) _finishSession();
        });
      });
    }
  }

  void _reset() {
    HapticFeedback.lightImpact();
    _timer?.cancel();
    setState(() {
      _running = false;
      _remaining = _totalForKind;
    });
  }

  /// Salta al siguiente estado del ciclo (sin contar como completado).
  void _skip() {
    HapticFeedback.lightImpact();
    setState(() {
      _running = false;
      _timer?.cancel();
      _advanceKind(completed: false);
      _remaining = _totalForKind;
    });
  }

  void _finishSession() {
    _timer?.cancel();
    HapticFeedback.heavyImpact();
    final wasWork = _kind == SessionKind.work;
    final taskAtFinish = _selectedTask;
    _advanceKind(completed: wasWork);
    setState(() {
      _running = false;
      _remaining = _totalForKind;
    });
    if (wasWork) {
      // Stats: hoy + por tarea (si había seleccionada). Fire-and-forget:
      // los métodos son async pero actualizan `state` (ref.watch lo ve).
      ref.read(pomodoroStatsProvider.notifier).incrementToday();
      if (taskAtFinish != null) {
        ref.read(pomodoroStatsProvider.notifier).incrementTask(taskAtFinish.id);
      }
      // Ofrecer completar la tarea (si hay y no está ya completa).
      if (taskAtFinish != null && !taskAtFinish.isCompleted && mounted) {
        _maybeOfferComplete(taskAtFinish);
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
  }

  Future<void> _maybeOfferComplete(Task task) async {
    final stats = ref.read(pomodoroStatsProvider);
    final shouldComplete = stats.autoComplete
        ? true
        : await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              icon: Icon(Icons.task_alt,
                  color: Theme.of(context).colorScheme.primary),
              title: const Text('¡Pomodoro terminado!'),
              content: Text('¿Marcar "${task.title}" como completada?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Seguir'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Completar'),
                ),
              ],
            ),
          ) ??
            false;
    if (!shouldComplete || !mounted) return;
    await ref.read(taskRepositoryProvider).toggleComplete(task.id, true);
    ref.invalidate(tasksStreamProvider);
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
    }
    if (result.autoComplete != null) {
      ref.read(pomodoroStatsProvider.notifier).setAutoComplete(
          result.autoComplete!);
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
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      )),
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
                                  strokeCap: StrokeCap.round,
                                  backgroundColor:
                                      scheme.surfaceContainerHighest,
                                  valueColor: AlwaysStoppedAnimation(accent),
                                ),
                              ),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(_iconForKind,
                                          color: accent, size: 18),
                                      const SizedBox(width: 6),
                                      Text(
                                        _labelForKind,
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                          color: accent,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _format(_remaining),
                                    style: const TextStyle(
                                      fontSize: 64,
                                      fontWeight: FontWeight.w700,
                                      fontFeatures: [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${(_totalForKind - _remaining) ~/ 60 + (_totalForKind - _remaining) % 60 ~/ 60} '
                                    'de ${_totalForKind ~/ 60} min',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
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
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _Stat(
                      icon: Icons.local_fire_department_outlined,
                      label: 'Hoy',
                      value: '${ref.watch(pomodoroStatsProvider).today}',
                      color: const Color(0xFFFB923C),
                    ),
                    Container(
                        width: 1,
                        height: 28,
                        color: scheme.outline.withValues(alpha: 0.2)),
                    _Stat(
                      icon: Icons.timer_outlined,
                      label: 'Preset',
                      value: _preset.label,
                      color: scheme.primary,
                    ),
                    Container(
                        width: 1,
                        height: 28,
                        color: scheme.outline.withValues(alpha: 0.2)),
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
                  _CircleAction(
                    icon: Icons.refresh,
                    tooltip: 'Reiniciar',
                    color: scheme.surfaceContainerHighest,
                    iconColor: scheme.onSurface,
                    onPressed: _reset,
                  ),
                  _PlayPauseButton(
                    running: _running,
                    accent: accent,
                    onPressed: _toggle,
                  ),
                  _CircleAction(
                    icon: Icons.skip_next,
                    tooltip: 'Saltar',
                    color: scheme.surfaceContainerHighest,
                    iconColor: scheme.onSurface,
                    onPressed: _skip,
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // ── Pick task ───────────────────────────────
              TextButton.icon(
                onPressed: _running ? null : _pickTask,
                icon: const Icon(Icons.task_alt),
                label: Text(_selectedTask == null
                    ? 'Elegir tarea para enfocarte'
                    : 'Cambiar tarea'),
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
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < total; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: i == done && isBreak ? 22 : 10,
              height: 10,
              decoration: BoxDecoration(
                color: i < done
                    ? scheme.primary
                    : (i == done
                        ? scheme.primary.withValues(alpha: 0.4)
                        : scheme.outline.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(5),
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
    final scheme = Theme.of(context).colorScheme;
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
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500)),
          ],
        ),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                fontSize: 14,
                color: scheme.onSurface,
                fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.iconColor,
    required this.onPressed,
  });
  final IconData icon;
  final String tooltip;
  final Color color;
  final Color iconColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 52,
            height: 52,
            child: Icon(icon, color: iconColor, size: 26),
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
  });
  final bool running;
  final Color accent;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      height: 80,
      child: Material(
        color: accent,
        shape: const CircleBorder(),
        elevation: 6,
        shadowColor: accent.withValues(alpha: 0.5),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Icon(
            running ? Icons.pause : Icons.play_arrow,
            color: Colors.white,
            size: 44,
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
class _TaskPickerOverlay extends StatefulWidget {
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
  State<_TaskPickerOverlay> createState() => _TaskPickerOverlayState();
}

class _TaskPickerOverlayState extends State<_TaskPickerOverlay> {
  String _filter = '';

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
                            borderRadius: BorderRadius.circular(12),
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
                              child: Text(
                                widget.tasks.isEmpty
                                    ? 'No hay tareas pendientes'
                                    : 'Sin coincidencias',
                                style: TextStyle(
                                    color: scheme.onSurfaceVariant),
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

/// Resultado del sheet de preset. Cualquiera de los dos campos puede
/// haber cambiado (o ninguno, si fue dismiss). El handler aplica sólo
/// lo que vino cambiado.
class _PresetPickResult {
  const _PresetPickResult({this.preset, this.autoComplete});
  final PomodoroPreset? preset;
  final bool? autoComplete;
}

/// Overlay in-screen de configuración del Pomodoro (preset + toggle
/// auto-completar). Misma justificación que _TaskPickerOverlay: no usa
/// showModalBottomSheet para que se cierre al cambiar de tab.
class _PresetOverlay extends StatefulWidget {
  const _PresetOverlay({
    required this.preset,
    required this.autoComplete,
    required this.onResult,
  });
  final PomodoroPreset preset;
  final bool autoComplete;
  final void Function(_PresetPickResult) onResult;

  @override
  State<_PresetOverlay> createState() => _PresetOverlayState();
}

class _PresetOverlayState extends State<_PresetOverlay> {
  late PomodoroPreset _selected = widget.preset;
  late bool _auto = widget.autoComplete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
              child: Padding(
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
                    for (final p in PomodoroPreset.all)
                      RadioListTile<PomodoroPreset>(
                        title: Text(p.label),
                        subtitle: Text(
                            '${p.work}min trabajo · ${p.shortBreak}min descanso · ${p.longBreak}min largo'),
                        value: p,
                        groupValue: _selected,
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _selected = v);
                        },
                      ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text('Auto-completar tarea'),
                      subtitle: const Text(
                          'Marca la tarea como hecha al terminar el pomodoro'),
                      value: _auto,
                      onChanged: (v) => setState(() => _auto = v),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: FilledButton(
                        onPressed: () => widget.onResult(_PresetPickResult(
                          preset: _selected,
                          autoComplete: _auto,
                        )),
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