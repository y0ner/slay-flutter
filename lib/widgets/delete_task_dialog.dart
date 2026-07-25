import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/task.dart';
import '../data/repositories/task_repository.dart';

/// Diálogo de confirmación para borrar una tarea. Reusado por
/// My Day, Tareas y Calendario.
class DeleteTaskDialog extends ConsumerWidget {
  const DeleteTaskDialog({super.key, required this.task});
  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AlertDialog(
      title: const Text('Eliminar tarea'),
      content: Text('¿Eliminar "${task.title}"?'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton.tonal(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () async {
            await ref.read(taskRepositoryProvider).delete(task.id);
            ref.invalidate(tasksStreamProvider);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Eliminar'),
        ),
      ],
    );
  }
}
