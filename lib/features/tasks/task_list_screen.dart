import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

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
              floatingActionButton: FloatingActionButton(
                onPressed: () => _addTask(context, ref, cat),
                child: const Icon(Icons.add),
              ),
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
                          onToggle: () => ref.read(taskRepositoryProvider)
                              .toggleComplete(list[i].id, !list[i].isCompleted),
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

  void _addTask(BuildContext context, WidgetRef ref, Category cat) {
    final ctrl = TextEditingController();
    DateTime? reminder;
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(builder: (ctx, setState) {
        return AlertDialog(
          title: Text('Nueva tarea en ${cat.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: ctrl, autofocus: true,
                decoration: const InputDecoration(labelText: 'Título')),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(reminder == null
                        ? 'Sin recordatorio'
                        : 'Recordatorio: ${DateFormat('dd/MM/yyyy HH:mm').format(reminder!)}'),
                  ),
                  TextButton(
                    onPressed: () async {
                      final now = DateTime.now();
                      final d = await showDatePicker(
                        context: ctx, firstDate: now,
                        lastDate: now.add(const Duration(days: 365)),
                        initialDate: now,
                      );
                      if (d == null) return;
                      if (!ctx.mounted) return;
                      final t = await showTimePicker(
                        context: ctx, initialTime: TimeOfDay.now());
                      if (t == null) return;
                      setState(() => reminder = DateTime(
                          d.year, d.month, d.day, t.hour, t.minute));
                    },
                    child: const Text('Elegir'),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                if (ctrl.text.trim().isEmpty) return;
                await ref.read(taskRepositoryProvider).create(
                  title: ctrl.text.trim(),
                  categoryId: cat.id,
                  reminder: reminder,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                ref.invalidate(tasksStreamProvider);
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      }),
    );
  }

}
