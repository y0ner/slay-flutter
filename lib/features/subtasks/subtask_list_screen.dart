import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/task.dart';
import '../../data/repositories/task_repository.dart';

/// Stream reactivo de subtareas de una tarea.
final subtasksStreamProvider =
    StreamProvider.family<List<SubTask>, String>((ref, taskId) {
  return ref.watch(taskRepositoryProvider).watchSubtasks(taskId);
});

class SubTaskListScreen extends ConsumerWidget {
  const SubTaskListScreen({super.key, required this.taskId});
  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subs = ref.watch(subtasksStreamProvider(taskId));
    final tasksAsync = ref.watch(tasksStreamProvider);

    final title = tasksAsync.maybeWhen(
      data: (all) => all.where((t) => t.id == taskId).firstOrNull?.title,
      orElse: () => 'Subtareas',
    );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(title ?? 'Subtareas', overflow: TextOverflow.ellipsis),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _add(context, ref),
        child: const Icon(Icons.add),
      ),
      body: subs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) => list.isEmpty
            ? const Center(child: Text('Sin subtareas'))
            : ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final s = list[i];
                  return CheckboxListTile(
                    title: Text(s.title,
                        style: TextStyle(
                          decoration: s.isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                        )),
                    value: s.isCompleted,
                    onChanged: (v) => ref.read(taskRepositoryProvider)
                        .toggleSubtaskComplete(s.id, v ?? false),
                    secondary: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => ref
                          .read(taskRepositoryProvider)
                          .deleteSubtask(s.id),
                    ),
                  );
                },
              ),
      ),
    );
  }

  void _add(BuildContext context, WidgetRef ref) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nueva subtarea'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              if (ctrl.text.trim().isEmpty) return;
              await ref.read(taskRepositoryProvider).createSubtask(
                taskId: taskId,
                title: ctrl.text.trim(),
              );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}
