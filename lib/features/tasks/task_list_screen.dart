import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/category.dart';
import '../../data/models/task.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/task_repository.dart';
import '../../widgets/delete_task_dialog.dart';
import '../../widgets/edit_task_dialog.dart';
import '../../widgets/task_card.dart';

/// Pantalla de tareas de UNA categoría. Reordenable: el usuario puede
/// arrastrar (long-press sobre el handle a la derecha de cada card)
/// para cambiar la prioridad. La posición en la lista ES la
/// prioridad — la #1 es la más importante.
///
/// Decisión de diseño (vs. Slay-Desktop):
/// - **El número de orden se muestra a la izquierda** de cada card,
///   siempre, así el usuario ve la prioridad de un vistazo sin
///   entrar en modo "reordenar".
/// - **NO auto-sink de completadas al fondo**: la prioridad del
///   usuario es sagrada. Completar la tarea no la "desordena", sólo
///   se tacha. Misma lógica en Mi Día (consistente).
/// - **Optimistic UI** en el drag: reordenamos localmente y
///   persistimos en paralelo. Si Supabase falla, revertimos + snackbar.
class TaskListScreen extends ConsumerWidget {
  const TaskListScreen({super.key, required this.categoryId});
  final String categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesStreamProvider);
    final tasksAsync = ref.watch(tasksStreamProvider);

    return categoriesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (cats) {
        final cat = cats.firstWhere(
          (c) => c.id == categoryId,
          orElse: () => Category(
              id: categoryId,
              name: '?',
              color: '#888888',
              sortOrder: 0),
        );
        return tasksAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (allTasks) {
            // Ordenamos SOLO por sortOrder. Las completadas conservan
            // su posición (con line-through). El número que se muestra
            // a la izquierda es 1-based y refleja la posición visual.
            final list = allTasks
                .where((t) => t.categoryId == categoryId)
                .toList()
              ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
            return Scaffold(
              backgroundColor: Colors.transparent,
              appBar: AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => context.pop(),
                ),
                title: Text(cat.name),
                actions: [
                  IconButton(
                    tooltip: 'Reordenar',
                    icon: const Icon(Icons.help_outline),
                    onPressed: () => _showReorderHelp(context),
                  ),
                ],
              ),
              // FAB contextual lo provee HomeShell (ruta /tasks/:id →
              // "Nueva tarea en esta categoría" con el categoryId
              // pre-seleccionado).
              body: list.isEmpty
                  ? const Center(child: Text('Sin tareas en esta categoría'))
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      itemCount: list.length,
                      // Drag sin proxy fantasma: el "elevation" de la
                      // card se mantiene durante el drag. El usuario
                      // ve exactamente qué está moviendo.
                      proxyDecorator: (child, index, animation) =>
                          Material(
                        elevation: 6,
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                        child: child,
                      ),
                      onReorder: (oldIndex, newIndex) =>
                          _onReorder(ref, list, oldIndex, newIndex),
                      itemBuilder: (_, i) => Padding(
                        key: ValueKey('task-${list[i].id}'),
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TaskCard(
                          task: list[i],
                          category: cat,
                          // 1-based para el usuario: la #1 es la
                          // "más prioritaria" según su criterio.
                          orderNumber: i + 1,
                          reorderIndex: i,
                          onTap: () =>
                              context.push('/subtasks/${list[i].id}'),
                          onToggle: () async {
                            await ref
                                .read(taskRepositoryProvider)
                                .toggleComplete(
                                    list[i].id, !list[i].isCompleted);
                            ref.invalidate(tasksStreamProvider);
                          },
                          onEdit: () => showDialog(
                            context: context,
                            builder: (_) => EditTaskDialog(task: list[i]),
                          ),
                          onDelete: () => showDialog(
                            context: context,
                            builder: (_) => DeleteTaskDialog(task: list[i]),
                          ),
                          onSendToFocus: () =>
                              context.go('/pomodoro?task=${list[i].id}'),
                        ),
                      ),
                    ),
            );
          },
        );
      },
    );
  }

  /// Maneja el reorder end-to-end:
  /// 1. Reordena la lista en memoria (optimistic).
  /// 2. Persiste en Supabase en paralelo.
  /// 3. Si falla, re-render desde el stream para revertir + snackbar.
  ///
  /// Reutiliza la misma renumeración 0..N-1 que el repository hace
  /// en `reorder()` — el `sortOrder` de cada Task queda igual a su
  /// índice en la lista reordenada.
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
    // Renumeramos 0..N-1 → el sortOrder nuevo de cada Task.
    final renumbered = [
      for (var i = 0; i < reordered.length; i++) reordered[i].copyWith(sortOrder: i),
    ];
    try {
      await ref.read(taskRepositoryProvider).reorder(renumbered);
      // Invalidamos para que la UI re-emita con el order del server.
      ref.invalidate(tasksStreamProvider);
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

  void _showReorderHelp(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cómo reordenar'),
        content: const Text(
          'El número a la izquierda es tu prioridad (#1 = la más '
          'importante). Para cambiar el orden:\n\n'
          '1. Mantené presionado el ícono ☰ a la derecha de la tarea.\n'
          '2. Arrastrá hasta la posición deseada.\n'
          '3. Soltá.\n\n'
          'Las tareas completadas NO se mueven al fondo: tu orden '
          'elegido se mantiene, sólo se tachan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }
}
