import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/terminal_theme.dart';
import '../../data/models/category.dart' show Category;
import '../../widgets/square_progress_border.dart';
import '../../data/models/task.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/task_repository.dart';
import 'focus_controller.dart';
import 'focus_history.dart';
import 'focus_model.dart';

/// Pomodoro v2 — "Foco" orientado a UNA tarea.
///
/// Flujo:
/// 1. Elegir tarea (obligatorio).
/// 2. Wizard: ¿cuánto creés que te lleva? (manual o atajos 5/15/30)
///    → ¿en cuántos intervalos lo dividís? → ¿cuánto descanso entre
///    intervalos?
/// 3. Run: cambia de fase solo (wall-clock), notifica cada transición
///    y corre en segundo plano con foreground service en Android.
/// 4. Wrap-up al terminar el último intervalo: ¿terminaste?
///    - Sí → completa la tarea.
///    - No → ¿cuánto más? (extiende el tiempo, mismos intervalos).
///    - "No hice nada" → reinicia todo.
/// 5. Detener mid-run → vuelve al wizard (todo se reconfigura), el
///    tiempo trabajado queda en el historial.
class PomodoroScreen extends ConsumerStatefulWidget {
  const PomodoroScreen({super.key});

  @override
  ConsumerState<PomodoroScreen> createState() => _PomodoroScreenState();
}

enum _PomoStage { pickTask, wizard, running, wrapUp }

class _PomodoroScreenState extends ConsumerState<PomodoroScreen> {
  _PomoStage _stage = _PomoStage.pickTask;

  // Wizard state.
  Task? _pickedTask;
  int _totalMinutes = 25;
  int _intervals = 4;
  int _breakMinutes = 5;
  final _totalCtrl = TextEditingController(text: '25');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Run activo (en curso o restaurado de prefs) → pantalla de run.
      if (ref.read(focusRunProvider) != null) {
        setState(() => _stage = _PomoStage.running);
        return;
      }
      // ⏱ "Enviar a foco" llegó antes de que esta pantalla existiera.
      _consumePendingFocusTask();
    });
  }

  @override
  void dispose() {
    _totalCtrl.dispose();
    super.dispose();
  }

  // ── Acciones ──────────────────────────────────────────────

  /// Carga la tarea [taskId] del repo y salta directo al wizard.
  ///
  /// `getById` es offline-first (cache local primero): antes usaba
  /// `getAll()` (red directa) y si Supabase fallaba el error moría
  /// callado acá — la pantalla quedaba en "elegir tarea" sin
  /// preseleccionar nada, aunque las listas mostraran las tareas
  /// desde el cache.
  Future<void> _pickTaskById(String taskId) async {
    final match = await ref.read(taskRepositoryProvider).getById(taskId);
    if (!mounted) return;
    if (match == null || match.isCompleted) {
      _openPicker();
      return;
    }
    setState(() {
      _pickedTask = match;
      _stage = _PomoStage.wizard;
    });
  }

  Future<void> _openPicker() async {
    List<Task> tasks;
    List<Category> categories;
    try {
      tasks = await ref.read(taskRepositoryProvider).getAll();
      categories = await ref.read(categoryRepositoryProvider).getAll();
    } catch (_) {
      // Sin red (o Supabase caído): caer al cache local — la misma
      // data que ven las listas de tareas. Antes el picker moría en
      // silencio con la misma falla que rompía el preselect.
      tasks = await ref.read(taskRepositoryProvider).getCached();
      categories = await ref.read(categoryRepositoryProvider).getCached();
    }
    if (!mounted) return;
    final pending = tasks.where((t) => !t.isCompleted).toList();
    final picked = await showModalBottomSheet<Task>(
      context: context,
      isScrollControlled: true,
      backgroundColor: TerminalTheme.panelOf(context),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (_) => _TaskPickerSheet(
        tasks: pending,
        categories: categories,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _pickedTask = picked;
      _stage = _PomoStage.wizard;
    });
  }

  Future<void> _startRun() async {
    final task = _pickedTask;
    if (task == null) return;
    final config = FocusConfig(
      totalMinutes: _totalMinutes,
      intervalCount: _intervals,
      breakMinutes: _breakMinutes,
    );
    if (!config.isValid) return;
    await ref.read(focusRunProvider.notifier).start(
          taskId: task.id,
          taskTitle: task.title,
          config: config,
    );
    if (!mounted) return;
    setState(() => _stage = _PomoStage.running);
  }

  Future<void> _stopAndReconfigure() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Detener y reconfigurar'),
        content: const Text(
            'El tiempo que trabajaste queda en el registro de la tarea, '
            'y volvés al inicio para configurar todo de nuevo.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Seguir')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Detener')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ref.read(focusRunProvider.notifier).reconfigure();
    if (!mounted) return;
    setState(() {
      _stage = _PomoStage.pickTask;
      _pickedTask = null;
    });
  }

  /// Fase terminó (último trabajo) → wrap-up. Detectado por el tick
  /// del controller: cuando remaining==0 && última fase de trabajo.
  void _checkWrapUp(FocusRunState? s) {
    if (s == null) return;
    final finished = !s.running &&
        s.remainingSeconds == 0 &&
        s.isLastWork &&
        s.workedSecondsTotal > 0;
    if (finished && _stage != _PomoStage.wrapUp) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _stage = _PomoStage.wrapUp);
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────

  /// Lee y limpia la señal de "Enviar a foco" si hay una pendiente.
  ///
  /// La señal llega por `pendingFocusTaskProvider` (NO por query
  /// params del router): la escriben las tarjetas con ⏱ y se consume
  /// acá — igual montando la pantalla fresca que volviendo a una ya
  /// viva. Si hay un run en curso, manda el run (no se pisa).
  void _consumePendingFocusTask() {
    final pending = ref.read(pendingFocusTaskProvider);
    if (pending == null || pending.isEmpty) return;
    // Limpiar YA: la señal es de un solo uso.
    ref.read(pendingFocusTaskProvider.notifier).state = null;
    if (ref.read(focusRunProvider) != null) return;
    _pickTaskById(pending);
  }

  @override
  Widget build(BuildContext context) {
    // ⏱ "Enviar a foco" mientras esta pantalla ya está viva (el State
    // sobrevive en el navigator del shell): la señal se procesa igual.
    ref.listen<String?>(pendingFocusTaskProvider, (_, next) {
      if (next != null && next.isNotEmpty) _consumePendingFocusTask();
    });
    final run = ref.watch(focusRunProvider);
    _checkWrapUp(run);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: switch (_stage) {
          _PomoStage.pickTask => _buildPickStage(context),
          _PomoStage.wizard => _buildWizard(context),
          _PomoStage.running => run == null
              ? _buildPickStage(context)
              : _buildRunning(context, run),
          _PomoStage.wrapUp =>
            run == null ? _buildPickStage(context) : _buildWrapUp(context, run),
        },
      ),
    );
  }

  // ── Stage 1: elegir tarea ────────────────────────────────

  Widget _buildPickStage(BuildContext context) {
    final accent = TerminalTheme.accentOf(context);
    final muted = TerminalTheme.mutedOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Foco', style: Theme.of(context).textTheme.displaySmall),
              const Spacer(),
              IconButton(
                tooltip: 'Registro',
                onPressed: () => _openHistorySheet(context, ref),
                icon: const Icon(Icons.receipt_long_outlined),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '> elegí una tarea para concentrarte',
            style: TextStyle(fontFamily: TerminalTheme.monoFamily, fontSize: 13, color: muted),
          ),
          const Spacer(),
          Center(
            child: Column(
              children: [
                _SquareBig(
                  icon: Icons.task_alt,
                  label: 'Elegir tarea',
                  color: accent,
                  onTap: () => _openPicker(),
                ),
              ],
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  // ── Stage 2: wizard de configuración ─────────────────────

  Widget _buildWizard(BuildContext context) {
    final task = _pickedTask;
    if (task == null) {
      return _buildPickStage(context);
    }
    final accent = TerminalTheme.accentOf(context);
    final config = FocusConfig(
      totalMinutes: _totalMinutes,
      intervalCount: _intervals,
      breakMinutes: _breakMinutes,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 96),
      children: [
        Row(
          children: [
            Text('Foco', style: Theme.of(context).textTheme.displaySmall),
            const Spacer(),
            IconButton(
              tooltip: 'Cambiar tarea',
              onPressed: () => _openPicker(),
              icon: const Icon(Icons.swap_horiz),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Tarea elegida.
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: TerminalTheme.panelOf(context),
            border: Border.all(color: TerminalTheme.lineOf(context)),
          ),
          child: Row(
            children: [
              Container(width: 7, height: 7, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  task.title,
                  style: TextStyle(
                    fontFamily: TerminalTheme.monoFamily,
                    fontWeight: FontWeight.w700,
                    color: TerminalTheme.fgOf(context),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // 1) Tiempo total.
        _StepLabel('1 · ¿cuánto creés que te lleva?'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _totalCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: TextStyle(
                  fontFamily: TerminalTheme.pixelFamily,
                  fontSize: 22,
                  color: TerminalTheme.fgOf(context),
                ),
                decoration: const InputDecoration(
                  labelText: 'minutos totales',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) =>
                    setState(() => _totalMinutes = int.tryParse(v) ?? 0),
              ),
            ),
            const SizedBox(width: 8),
            for (final quick in const [5, 15, 30]) ...[
              const SizedBox(width: 6),
              _QuickChip(
                label: '$quick',
                selected: _totalMinutes == quick,
                onTap: () {
                  setState(() {
                    _totalMinutes = quick;
                    _totalCtrl.text = '$quick';
                  });
                },
              ),
            ],
          ],
        ),
        const SizedBox(height: 20),

        // 2) Intervalos.
        _StepLabel('2 · ¿en cuántos intervalos lo dividís?'),
        const SizedBox(height: 8),
        _Counter(
          value: _intervals,
          min: 1,
          max: 12,
          hint:
              '${config.workMinutesPerInterval} min por intervalo',
          onChanged: (v) => setState(() => _intervals = v),
        ),
        const SizedBox(height: 20),

        // 3) Descanso.
        _StepLabel('3 · ¿cuánto descanso entre intervalos?'),
        const SizedBox(height: 8),
        _Counter(
          value: _breakMinutes,
          min: 0,
          max: 30,
          unit: 'min',
          hint: _breakMinutes == 0
              ? 'sin descansos'
              : '${config.breakCount} descansos de ${_breakMinutes} min',
          onChanged: (v) => setState(() => _breakMinutes = v),
        ),
        const SizedBox(height: 24),

        // Resumen estilo consola.
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: TerminalTheme.panelOf(context),
            border: Border.all(color: TerminalTheme.lineOf(context)),
          ),
          child: Text(
            '> ${config.intervalCount} sesiones de '
            '${config.workMinutesPerInterval} min'
            '${config.breakCount > 0 ? ' + ${config.breakCount} descansos de ${config.breakMinutes} min' : ''}'
            ' — total real ${config.realTotalMinutes} min',
            style: TextStyle(
              fontFamily: TerminalTheme.monoFamily,
              fontSize: 12.5,
              color: TerminalTheme.mutedOf(context),
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (!config.isValid)
          Text(
            '> ingresá un tiempo válido (≥1 min)',
            style: TextStyle(
              fontFamily: TerminalTheme.monoFamily,
              fontSize: 12,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        FilledButton(
          onPressed: config.isValid ? _startRun : null,
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            minimumSize: const Size.fromHeight(52),
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          ),
          child: Text(
            'Empezar',
            style: TextStyle(
              fontFamily: TerminalTheme.monoFamily,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).brightness == Brightness.dark
                  ? TerminalTheme.nightBg
                  : TerminalTheme.dayBg,
            ),
          ),
        ),
      ],
    );
  }

  // ── Stage 3: run ──────────────────────────────────────────

  Widget _buildRunning(BuildContext context, FocusRunState s) {
    final accent = s.phase.isWork
        ? TerminalTheme.accentOf(context)
        : (s.phase.index % 2 == 0
            ? TerminalTheme.buildingOf(context)
            : TerminalTheme.okOf(context));
    final total = s.currentPhaseTotalSeconds;
    final progress = total > 0 ? (1 - s.remainingSeconds / total) : 0.0;
    final phaseLabel = s.phase.isWork
        ? 'TRABAJO ${s.phase.index + 1}/${s.config.intervalCount}'
        : 'DESCANSO';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Column(
        children: [
          Row(
            children: [
              Text('Foco', style: Theme.of(context).textTheme.displaySmall),
              const Spacer(),
              IconButton(
                tooltip: 'Registro',
                onPressed: () => _openHistorySheet(context, ref),
                icon: const Icon(Icons.receipt_long_outlined),
              ),
              IconButton(
                tooltip: 'Detener y reconfigurar',
                onPressed: _stopAndReconfigure,
                icon: const Icon(Icons.stop_circle_outlined),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            s.taskTitle,
            style: TextStyle(
              fontFamily: TerminalTheme.monoFamily,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: TerminalTheme.mutedOf(context),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),

          // Dots de intervalos.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < s.config.intervalCount; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Container(
                    width: 10,
                    height: 10,
                    color: i < s.phase.index
                        ? accent
                        : (i == s.phase.index && s.phase.isWork
                            ? accent.withValues(alpha: 0.45)
                            : TerminalTheme.lineOf(context)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Progreso: borde CUADRADO que se dibuja alrededor del
          // cuadro del tiempo (el círculo no iba con la app).
          // El tamaño total sale del hijo (232) + padding del borde;
          // se limita con FittedBox para no desbordar en pantallas
          // chicas (el Expanded absorbe el resto del alto).
          Expanded(
            child: Center(
              child: FittedBox(
                child: SquareProgressBorder(
                  progress: progress.clamp(0.0, 1.0),
                  color: accent,
                  trackColor: TerminalTheme.lineOf(context),
                  // El gap visual entre el borde y el cuadro del reloj
                  // es el `padding` (el trazo se compensa solo). 4px =
                  // bien pegado, decisión del usuario.
                  strokeWidth: 8,
                  padding: 4,
                  child: Container(
                    width: 232,
                    height: 232,
                  decoration: BoxDecoration(
                    color: TerminalTheme.panelOf(context),
                    border: Border.all(color: TerminalTheme.lineOf(context)),
                  ),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 7, height: 7, color: accent),
                          const SizedBox(width: 7),
                          Text(
                            phaseLabel,
                            style: TextStyle(
                              fontFamily: TerminalTheme.monoFamily,
                              fontSize: 11.5,
                              letterSpacing: 1.2,
                              color: accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _fmt(s.remainingSeconds),
                        style: TextStyle(
                          fontFamily: TerminalTheme.pixelFamily,
                          fontSize: 44,
                          height: 1.1,
                          color: TerminalTheme.fgOf(context),
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        s.running
                            ? 'corriendo'
                            : 'en pausa — ${_fmt(s.remainingSeconds)} restantes',
                        style: TextStyle(
                          fontFamily: TerminalTheme.monoFamily,
                          fontSize: 11.5,
                          color: TerminalTheme.mutedOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
                ),
              ),
            ),
          ),

          // Trabajado acumulado.
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'trabajado: ${_fmt(s.workedSecondsTotal)} · '
              'pausas: ${s.pauseCount}',
              style: TextStyle(
                fontFamily: TerminalTheme.monoFamily,
                fontSize: 12,
                color: TerminalTheme.mutedOf(context),
              ),
            ),
          ),

          // Controles.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              if (s.phase.isBreak)
                _SquareAction(
                  icon: Icons.skip_next,
                  tooltip: 'Saltar descanso',
                  onPressed: () =>
                      ref.read(focusRunProvider.notifier).skipBreak(),
                ),
              _SquareAction(
                icon: s.running ? Icons.pause : Icons.play_arrow,
                tooltip: s.running ? 'Pausar' : 'Reanudar',
                accent: accent,
                onPressed: () => s.running
                    ? ref.read(focusRunProvider.notifier).pause()
                    : ref.read(focusRunProvider.notifier).resume(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Stage 4: wrap-up ─────────────────────────────────────

  Widget _buildWrapUp(BuildContext context, FocusRunState s) {
    final accent = TerminalTheme.accentOf(context);
    final ok = TerminalTheme.okOf(context);
    final minutes = s.workedSecondsTotal ~/ 60;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('> sesión completa',
              style: TextStyle(
                  fontFamily: TerminalTheme.pixelFamily,
                  fontSize: 18,
                  color: ok)),
          const SizedBox(height: 8),
          Text(
            'Trabajaste $minutes min en "${s.taskTitle}".',
            style: TextStyle(
              fontFamily: TerminalTheme.monoFamily,
              fontSize: 14,
              color: TerminalTheme.fgOf(context),
              height: 1.5,
            ),
          ),
          const Spacer(),
          FilledButton(
            onPressed: () async {
              await ref.read(focusRunProvider.notifier).completeTaskAndFinish();
              if (mounted) setState(() => _stage = _PomoStage.pickTask);
            },
            style: FilledButton.styleFrom(
              backgroundColor: ok,
              minimumSize: const Size.fromHeight(52),
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero),
            ),
            child: Text(
              'Sí, terminé — tachar la tarea',
              style: TextStyle(
                fontFamily: TerminalTheme.monoFamily,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).brightness == Brightness.dark
                    ? TerminalTheme.nightBg
                    : TerminalTheme.dayBg,
              ),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => _askExtend(context, s),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              side: BorderSide(color: accent),
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero),
            ),
            child: Text(
              'No terminé — necesito más tiempo',
              style: TextStyle(
                fontFamily: TerminalTheme.monoFamily,
                color: accent,
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () async {
              await ref.read(focusRunProvider.notifier).abandon();
              if (mounted) setState(() => _stage = _PomoStage.pickTask);
            },
            child: Text(
              'No hice nada — reiniciar todo',
              style: TextStyle(
                fontFamily: TerminalTheme.monoFamily,
                color: TerminalTheme.mutedOf(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _askExtend(BuildContext context, FocusRunState s) async {
    final ctrl = TextEditingController(text: '15');
    bool wantsBreaks = s.config.breakMinutes > 0;
    final result = await showDialog<(int, bool)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('¿Cuánto más te falta?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Es tiempo NUEVO para terminar — lo ya trabajado no se repite.'),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                autofocus: true,
                onChanged: (_) => setDialogState(() {}),
                decoration: const InputDecoration(labelText: 'minutos extra'),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Con descansos (${s.config.breakMinutes} min)',
                  style: const TextStyle(fontSize: 14),
                ),
                value: wantsBreaks,
                onChanged: s.config.breakMinutes > 0
                    ? (v) => setDialogState(() => wantsBreaks = v)
                    : null,
              ),
              const SizedBox(height: 4),
              Text(
                _extendPreview(
                  s,
                  int.tryParse(ctrl.text) ?? 0,
                  wantsBreaks,
                ),
                style: TextStyle(
                  fontFamily: TerminalTheme.monoFamily,
                  fontSize: 12,
                  color: TerminalTheme.mutedOf(context),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            FilledButton(
              onPressed: () => Navigator.pop(
                  ctx, (int.tryParse(ctrl.text) ?? 0, wantsBreaks)),
              child: const Text('Extender'),
            ),
          ],
        ),
      ),
    );
    if (result == null || result.$1 <= 0 || !mounted) return;
    await ref.read(focusRunProvider.notifier).extendAndRestart(
          extraMinutes: result.$1,
          wantsBreaks: result.$2,
        );
    if (mounted) setState(() => _stage = _PomoStage.running);
  }
}

// ═══════════════════════════════════════════════════════════════
// Widgets de apoyo
// ═══════════════════════════════════════════════════════════════

/// Vista previa del run extendido para el diálogo "¿Cuánto más te
/// falta?": cuántos intervalos y descansos REALES va a tener el
/// tiempo extra.
///
/// REGRESIÓN: el switch "Con descansos" quedaba encendido sin efecto
/// visible — un run de N intervalos tiene N-1 descansos, así que si
/// el extra entra en 1 solo intervalo (≤ minutos por intervalo) no
/// hay ningún descanso y el usuario no entendía por qué.
String _extendPreview(FocusRunState s, int extra, bool wantsBreaks) {
  if (extra <= 0) return '> elegí cuántos minutos extra';
  if (!wantsBreaks) {
    return '> $extra min en 1 solo intervalo (sin descansos)';
  }
  final per = s.config.workMinutesPerInterval;
  final n = (extra / per).ceil();
  final breaks = n - 1;
  if (breaks <= 0) {
    return '> $extra min entra en 1 intervalo (≤ $per min) — sin descansos';
  }
  return '> $extra min → $n intervalos + $breaks descansos '
      'de ${s.config.breakMinutes} min';
}

String _fmt(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  if (h > 0) {
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

class _StepLabel extends StatelessWidget {
  const _StepLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontFamily: TerminalTheme.monoFamily,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.0,
        color: TerminalTheme.accentOf(context),
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = TerminalTheme.accentOf(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(
              color: selected ? accent : TerminalTheme.lineOf(context)),
          color: selected ? accent.withValues(alpha: 0.12) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: TerminalTheme.monoFamily,
            fontWeight: FontWeight.w700,
            color: selected ? accent : TerminalTheme.mutedOf(context),
          ),
        ),
      ),
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.unit = '',
    this.hint = '',
  });
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final String unit;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            _SquareAction(
              icon: Icons.remove,
              tooltip: 'Menos',
              onPressed:
                  value > min ? () => onChanged(value - 1) : null,
            ),
            Expanded(
              child: Container(
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: TerminalTheme.lineOf(context)),
                    right: BorderSide(color: TerminalTheme.lineOf(context)),
                  ),
                ),
                child: Text(
                  '$value${unit.isNotEmpty ? ' $unit' : ''}',
                  style: TextStyle(
                    fontFamily: TerminalTheme.pixelFamily,
                    fontSize: 22,
                    color: TerminalTheme.fgOf(context),
                  ),
                ),
              ),
            ),
            _SquareAction(
              icon: Icons.add,
              tooltip: 'Más',
              onPressed:
                  value < max ? () => onChanged(value + 1) : null,
            ),
          ],
        ),
        if (hint.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              hint,
              style: TextStyle(
                fontFamily: TerminalTheme.monoFamily,
                fontSize: 12,
                color: TerminalTheme.mutedOf(context),
              ),
            ),
          ),
      ],
    );
  }
}

class _SquareAction extends StatelessWidget {
  const _SquareAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.accent,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? TerminalTheme.fgOf(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: TerminalTheme.panelOf(context),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        child: InkWell(
          onTap: onPressed,
          child: Container(
            width: 56,
            height: 52,
            decoration: BoxDecoration(
              border: Border.all(color: TerminalTheme.lineOf(context)),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
        ),
      ),
    );
  }
}

class _SquareBig extends StatelessWidget {
  const _SquareBig({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 200,
        height: 120,
        decoration: BoxDecoration(
          color: TerminalTheme.panelOf(context),
          border: Border.all(color: color),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 34),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontFamily: TerminalTheme.monoFamily,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Picker de tareas (bottom sheet estilo terminal)
// ═══════════════════════════════════════════════════════════════

class _TaskPickerSheet extends StatelessWidget {
  const _TaskPickerSheet({
    required this.tasks,
    required this.categories,
  });
  final List<Task> tasks;
  final List<Category> categories;

  @override
  Widget build(BuildContext context) {
    final accent = TerminalTheme.accentOf(context);
    final catById = {for (final c in categories) c.id: c};
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            Text(
              '> ENFOCATE EN',
              style: TextStyle(
                fontFamily: TerminalTheme.monoFamily,
                fontSize: 12,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: tasks.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        '> no hay tareas pendientes',
                        style: TextStyle(
                          fontFamily: TerminalTheme.monoFamily,
                          color: TerminalTheme.mutedOf(context),
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: tasks.length,
                      itemBuilder: (context, i) {
                        final t = tasks[i];
                        final cat = catById[t.categoryId];
                        return ListTile(
                          leading: Container(
                            width: 14,
                            height: 14,
                            color: cat != null
                                ? Color(int.parse(
                                    cat.color.replaceFirst('#', '0xFF')))
                                : accent,
                          ),
                          title: Text(
                            t.title,
                            style: TextStyle(
                              fontFamily: TerminalTheme.monoFamily,
                              color: TerminalTheme.fgOf(context),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: cat != null
                              ? Text(cat.name,
                                  style: TextStyle(
                                    fontFamily: TerminalTheme.monoFamily,
                                    fontSize: 11.5,
                                    color: TerminalTheme.mutedOf(context),
                                  ))
                              : null,
                          onTap: () => Navigator.pop(context, t),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Registro / historial
// ═══════════════════════════════════════════════════════════════

void _openHistorySheet(BuildContext context, WidgetRef ref) {
  // PopupRoute (dialog a pantalla completa) y NO bottom sheet: los
  // showModalBottomSheet viven en el Navigator raíz y SOBREVIVEN al
  // cambio de tab de GoRouter (el usuario veía el registro flotando
  // sobre Mi Día). Un PopupRoute se cierra con la navegación.
  Navigator.of(context, rootNavigator: false).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black54,
      pageBuilder: (_, __, ___) => const _HistorySheet(),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

/// Registro de foco AGRUPADO POR TAREA: una fila por tarea con el
/// tiempo TOTAL trabajado (todos los intentos suman, incluidos los
/// reconfigurados/detenidos). Tocar la fila abre el detalle con cada
/// intento.
class _HistorySheet extends ConsumerWidget {
  const _HistorySheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(focusHistoryProvider);
    final accent = TerminalTheme.accentOf(context);

    // Agrupar por tarea preservando orden (más reciente primero).
    final groups = <String, List<FocusSessionEntry>>{};
    for (final e in sessions) {
      groups.putIfAbsent(e.taskId, () => []).add(e);
    }
    final totalMin =
        sessions.fold<int>(0, (m, e) => m + e.workedSeconds) ~/ 60;

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 560,
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: Container(
            margin: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: TerminalTheme.panelOf(context),
              border: Border.all(color: TerminalTheme.lineOf(context)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
                  child: Row(
                    children: [
                      Text(
                        '> REGISTRO DE FOCO',
                        style: TextStyle(
                          fontFamily: TerminalTheme.monoFamily,
                          fontSize: 12,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Cerrar',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, size: 20),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '${groups.length} tareas · $totalMin min trabajados',
                    style: TextStyle(
                      fontFamily: TerminalTheme.monoFamily,
                      fontSize: 12,
                      color: TerminalTheme.mutedOf(context),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: groups.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            '> todavía no hay registros',
                            style: TextStyle(
                              fontFamily: TerminalTheme.monoFamily,
                              color: TerminalTheme.mutedOf(context),
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: groups.length,
                          itemBuilder: (context, i) {
                            final entries = groups.values.elementAt(i);
                            return _HistoryGroupTile(entries: entries);
                          },
                        ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Fila agrupada de una tarea: total trabajado + estado global.
class _HistoryGroupTile extends StatelessWidget {
  const _HistoryGroupTile({required this.entries});
  final List<FocusSessionEntry> entries;

  @override
  Widget build(BuildContext context) {
    final muted = TerminalTheme.mutedOf(context);
    final ok = TerminalTheme.okOf(context);
    final accent = TerminalTheme.accentOf(context);

    // Entradas ya vienen más nuevas primero. La "terminada" define el
    // estado del grupo; si hay un run en curso, ese manda.
    final running = entries.where((e) => e.isRunning).firstOrNull;
    final finished = entries.where((e) => e.completedTask).firstOrNull;
    final totalSec = entries.fold<int>(0, (m, e) => m + e.workedSeconds);
    final last = entries.first;

    final statusLabel = running != null
        ? 'en curso'
        : finished != null
            ? 'terminada'
            : 'sin terminar';
    final statusColor = running != null
        ? accent
        : finished != null
            ? ok
            : muted;

    // Fecha a mostrar: el inicio del intento más reciente.
    final started = DateTime.fromMillisecondsSinceEpoch(last.startedAtMs);
    final dateLabel =
        '${started.day}/${started.month} ${started.hour.toString().padLeft(2, '0')}:${started.minute.toString().padLeft(2, '0')}';

    return InkWell(
      onTap: () => _openDetailDialog(context, entries),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: TerminalTheme.lineOf(context)),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(width: 7, height: 7, color: statusColor),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    last.taskTitle,
                    style: TextStyle(
                      fontFamily: TerminalTheme.monoFamily,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: TerminalTheme.fgOf(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$dateLabel · total ${_fmtDuration(totalSec)} trabajados'
                    ' · ${entries.length} intento${entries.length == 1 ? '' : 's'}'
                    ' · $statusLabel',
                    style: TextStyle(
                      fontFamily: TerminalTheme.monoFamily,
                      fontSize: 11.5,
                      color: muted,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: muted),
          ],
        ),
      ),
    );
  }

  void _openDetailDialog(BuildContext context, List<FocusSessionEntry> entries) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _SessionDetailDialog(entries: entries),
    );
  }
}

/// Modal flotante con el detalle de todos los intentos de una tarea.
class _SessionDetailDialog extends StatelessWidget {
  const _SessionDetailDialog({required this.entries});

  final List<FocusSessionEntry> entries;

  @override
  Widget build(BuildContext context) {
    final accent = TerminalTheme.accentOf(context);
    final muted = TerminalTheme.mutedOf(context);
    final totalSec = entries.fold<int>(0, (m, e) => m + e.workedSeconds);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Container(
          decoration: BoxDecoration(
            color: TerminalTheme.panelOf(context),
            border: Border.all(color: TerminalTheme.lineOf(context)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        entries.first.taskTitle,
                        style: TextStyle(
                          fontFamily: TerminalTheme.monoFamily,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: TerminalTheme.fgOf(context),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, size: 20),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '> TOTAL: ${_fmtDuration(totalSec)} en ${entries.length} intento${entries.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontFamily: TerminalTheme.monoFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final e in entries) _AttemptTile(entry: e),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Toca fuera del recuadro para cerrar.',
                  style: TextStyle(
                    fontFamily: TerminalTheme.monoFamily,
                    fontSize: 10.5,
                    color: muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Detalle de un intento individual.
class _AttemptTile extends StatelessWidget {
  const _AttemptTile({required this.entry});
  final FocusSessionEntry entry;

  @override
  Widget build(BuildContext context) {
    final muted = TerminalTheme.mutedOf(context);
    final accent = TerminalTheme.accentOf(context);
    final ok = TerminalTheme.okOf(context);

    final started = DateTime.fromMillisecondsSinceEpoch(entry.startedAtMs);
    final dateLabel =
        '${started.day}/${started.month} ${started.hour.toString().padLeft(2, '0')}:${started.minute.toString().padLeft(2, '0')}';
    final statusLabel = switch (entry.status) {
      'finished' => entry.completedTask ? 'terminada ✓' : 'completa',
      'stopped' => 'detenida',
      'reconfigured' => 'reconfigurada',
      _ => 'en curso',
    };
    final statusColor = entry.completedTask
        ? ok
        : (entry.isRunning ? accent : muted);

    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: TerminalTheme.lineOf(context)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(width: 7, height: 7, color: statusColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$dateLabel · ${_fmtDuration(entry.workedSeconds)}'
              ' · plan ${entry.plannedTotalMinutes} min en ${entry.intervalCount}'
              '${entry.breakMinutes > 0 ? ' + ${entry.breakMinutes} desc' : ''}'
              '${entry.pauseCount > 0 ? ' · ${entry.pauseCount} pausa${entry.pauseCount == 1 ? '' : 's'}' : ''}'
              ' · $statusLabel',
              style: TextStyle(
                fontFamily: TerminalTheme.monoFamily,
                fontSize: 11.5,
                color: muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Formato de duración legible: "1 h 05 min" / "12 min" / "45 seg".
String _fmtDuration(int seconds) {
  if (seconds < 60) return '$seconds seg';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (h > 0) {
    return m > 0 ? '$h h ${m.toString().padLeft(2, '0')} min' : '$h h';
  }
  return '$m min';
}
