import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/terminal_theme.dart';
import '../../data/models/category.dart';
import '../../data/models/task.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/task_repository.dart';
import '../../widgets/delete_task_dialog.dart';
import '../../widgets/edit_task_dialog.dart';
import '../../widgets/task_card.dart';

/// Pantalla "Mi Día" — estilo terminal: titular en pixel font, fecha como
/// salida de consola (prefijo `>` en naranja).
///
/// Reordenable (misma mecánica que TaskListScreen): el usuario puede
/// arrastrar sus tareas del día (long-press sobre el handle ☰) para
/// planificar la secuencia en que las va a hacer. El número a la
/// izquierda es la posición en esa secuencia. Las completadas NO se
/// hunden al fondo: conservan su posición, sólo se tachan.
class MyDayScreen extends ConsumerWidget {
  const MyDayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(tasksStreamProvider);
    final cachedTasksAsync = ref.watch(cachedTasksStreamProvider);
    final categoriesAsync = ref.watch(categoriesStreamProvider);
    final cachedCategoriesAsync = ref.watch(cachedCategoriesStreamProvider);

    // Cuando Supabase responde, usamos su lista (fuente de verdad).
    // Si falla por red o está loading, caemos al cache local — la
    // app sigue siendo usable sin internet.
    List<Task> allTasks = const <Task>[];
    tasksAsync.whenData((l) => allTasks = l);
    if (allTasks.isEmpty) {
      cachedTasksAsync.whenData((l) => allTasks = l);
    }
    List<Category> categories = const <Category>[];
    categoriesAsync.whenData((l) => categories = l);
    if (categories.isEmpty) {
      cachedCategoriesAsync.whenData((l) => categories = l);
    }

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    // Lista GLOBAL (todas las tareas del usuario): es la base para
    // calcular "al fondo" al completar (checkWithReorder), aunque la
    // UI sólo muestre las de hoy.
    // Spread antes de sort: `allTasks` puede ser la const vacía del
    // primer frame (stream cargando) y `List.sort()` muta in-place →
    // "Cannot modify an unmodifiable list" = pantalla roja 1 frame.
    final fullList = [
      ...allTasks,
    ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final todayTasks = allTasks.where((t) {
      if (t.reminder != null) {
        return DateFormat('yyyy-MM-dd').format(t.reminder!) == today;
      }
      if (t.date != null) {
        return DateFormat('yyyy-MM-dd').format(t.date!) == today;
      }
      return false;
    }).toList()
      // Igual que TaskListScreen: ordenamos SOLO por sortOrder. Las
      // completadas quedan al fondo por su sortOrder (cede su puesto
      // al chuletear), no por un comparador que las esconda.
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    final pending = todayTasks.where((t) => !t.isCompleted).length;
    final accent = TerminalTheme.accentOf(context);

    return RefreshIndicator(
      color: accent,
      backgroundColor: TerminalTheme.panelOf(context),
      onRefresh: () => ref.refresh(tasksStreamProvider.future),
      child: ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 28, 16, 96),
        // Header (fecha + titular + contador) como primer elemento
        // no-reordenable del scroll.
        header: _buildHeader(context, pending),
        itemCount: todayTasks.length,
        // Drag sin proxy fantasma: el "elevation" de la card se
        // mantiene durante el drag. El usuario ve exactamente qué
        // está moviendo.
        proxyDecorator: (child, index, animation) => Material(
          elevation: 0,
          color: TerminalTheme.panelOf(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
            side: BorderSide(
              color: TerminalTheme.accentOf(context),
              width: 1.4,
            ),
          ),
          child: child,
        ),
        onReorder: (oldIndex, newIndex) =>
            _onReorder(ref, todayTasks, oldIndex, newIndex),
        itemBuilder: (_, i) {
          final t = todayTasks[i];
          final cat =
              categories.where((c) => c.id == t.categoryId).firstOrNull;
          return Padding(
            key: ValueKey('task-${t.id}'),
            padding: const EdgeInsets.only(bottom: 12),
            child: TaskCard(
              task: t,
              category: cat,
              // 1-based: #1 = la primera tarea de la secuencia del día.
              orderNumber: i + 1,
              reorderIndex: i,
              onTap: () => context.push('/subtasks/${t.id}'),
              onToggle: () async {
                await ref
                    .read(taskRepositoryProvider)
                    .toggleWithReorder(t.id, !t.isCompleted, fullList);
                ref.invalidate(tasksStreamProvider);
              },
              onEdit: () => showDialog(
                context: context,
                builder: (_) => EditTaskDialog(task: t),
              ),
              onDelete: () => showDialog(
                context: context,
                builder: (_) => DeleteTaskDialog(task: t),
              ),
              onSendToFocus: () => context.go('/pomodoro?task=${t.id}'),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context, int pending) {
    final accent = TerminalTheme.accentOf(context);
    final muted = TerminalTheme.mutedOf(context);
    final line = TerminalTheme.lineOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Salida de consola: prompt + fecha de hoy.
          Row(
            children: [
              Text(
                '> ',
                style: TextStyle(
                  fontFamily: TerminalTheme.pixelFamily,
                  fontSize: 16,
                  color: accent,
                ),
              ),
              Text(
                DateFormat('EEEE, d MMMM', 'es_ES')
                    .format(DateTime.now())
                    .replaceFirstMapped(
                        RegExp(r'^\w'), (m) => m[0]!.toUpperCase()),
                style: TextStyle(
                  fontFamily: TerminalTheme.monoFamily,
                  fontSize: 13.5,
                  color: muted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Mi Día',
            style: Theme.of(context).textTheme.displaySmall,
          ),
          const SizedBox(height: 8),
          // Contador estilo terminal: [N] pendientes.
          Text(
            pending == 0
                ? '[0] pendientes — día limpio'
                : '[${pending}] pendiente${pending == 1 ? '' : 's'}',
            style: TextStyle(
              fontFamily: TerminalTheme.monoFamily,
              fontSize: 13,
              color: pending == 0 ? TerminalTheme.okOf(context) : accent,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Divider(color: line, thickness: 1, height: 1),
        ],
      ),
    );
  }

  /// Maneja el reorder end-to-end (misma mecánica que TaskListScreen):
  /// 1. Reordena la lista en memoria (optimistic).
  /// 2. Persiste en Supabase en paralelo.
  /// 3. Si falla, re-render desde el stream para revertir + snackbar.
  ///
  /// Renumeramos 0..N-1 sobre la lista VISIBLE (tareas de hoy) y
  /// persistimos con `reorder`. Las tareas fuera de "hoy" no se
  /// tocan, así el orden global no se pisa con el de Mi Día.
  Future<void> _onReorder(
    WidgetRef ref,
    List<Task> list,
    int oldIndex,
    int newIndex,
  ) async {
    if (oldIndex == newIndex) return;
    HapticFeedback.selectionClick();
    // ReorderableListView quirk: cuando movés un item "hacia abajo",
    // newIndex viene 1-based mientras la lista todavía no incluye el
    // item movido. Ajustamos para que coincida con el índice destino.
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    if (oldIndex == target) return;
    final reordered = [...list];
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(target, moved);
    // Renumeramos la lista visible 0..N-1 (compacta: quedan sin
    // huecos tras mover una tarea al fondo). El resto del universo
    // (otras categorías/fechas) conserva su sortOrder.
    final renumbered = [
      for (var i = 0; i < reordered.length; i++)
        reordered[i].copyWith(sortOrder: i),
    ];
    try {
      await ref.read(taskRepositoryProvider).reorder(renumbered);
      // Invalidamos para que la UI re-emita con el order del server.
      ref.invalidate(tasksStreamProvider);
      ref.invalidate(cachedTasksStreamProvider);
    } catch (e) {
      // Revertir: el stream está viejo, una invalidate fuerza re-sync.
      ref.invalidate(tasksStreamProvider);
      if (ref.context.mounted) {
        ScaffoldMessenger.of(ref.context).showSnackBar(
          SnackBar(content: Text('Error al reordenar: $e')),
        );
      }
    }
  }
}
