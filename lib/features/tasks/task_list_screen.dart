import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/category.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/task_repository.dart';
import '../../widgets/delete_task_dialog.dart';
import '../../widgets/edit_task_dialog.dart';
import '../../widgets/task_card.dart';

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
          orElse: () => Category(id: categoryId, name: '?', color: '#888888', sortOrder: 0),
        );
        return tasksAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (allTasks) {
            final list = allTasks
                .where((t) => t.categoryId == categoryId)
                .toList()
              ..sort((a, b) {
                if (a.isCompleted != b.isCompleted) {
                  return a.isCompleted ? 1 : -1;
                }
                return a.sortOrder.compareTo(b.sortOrder);
              });
            return Scaffold(
              backgroundColor: Colors.transparent,
              appBar: AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => context.pop(),
                ),
                title: Text(cat.name),
              ),
              // FAB contextual lo provee HomeShell (ruta /tasks/:id →
              // "Nueva tarea en esta categoría" con el categoryId
              // pre-seleccionado).
              body: list.isEmpty
                  ? const Center(child: Text('Sin tareas en esta categoría'))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      itemCount: list.length,
                      itemBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TaskCard(
                          task: list[i],
                          category: cat,
                          onTap: () => context.push('/subtasks/${list[i].id}'),
                          onToggle: () async {
                            await ref.read(taskRepositoryProvider)
                                .toggleComplete(list[i].id, !list[i].isCompleted);
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
                          onSendToFocus: () => context.go('/pomodoro?task=${list[i].id}'),
                        ),
                      ),
                    ),
            );
          },
        );
      },
    );
  }
}
