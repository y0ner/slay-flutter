import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models/category.dart';
import '../../data/models/task.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/task_repository.dart';

/// Lista histórica de tareas con `isCompleted == true`.
///
/// A diferencia de Mi Día / Tareas, esta pantalla es de "limpieza":
/// la operación primaria es **reactivar** (volver a pendiente) o
/// **eliminar** definitivamente. No hay edición de título/reminder.
///
/// **Modo offline**: si Supabase falla por red, cae al cache local
/// (mismo patrón que `MyDayScreen`).
class CompletedTasksScreen extends ConsumerWidget {
  const CompletedTasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(tasksStreamProvider);
    final cachedTasksAsync = ref.watch(cachedTasksStreamProvider);
    final categoriesAsync = ref.watch(categoriesStreamProvider);
    final cachedCategoriesAsync = ref.watch(cachedCategoriesStreamProvider);

    // Fallback offline: si Supabase falla o está vacío, usamos cache.
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

    // Filtrar completadas y ordenar: las más recientes primero.
    // Sin `completed_at`, usamos `date` (fecha de Mi Día) y luego
    // `sortOrder` desc como fallback.
    final completed = allTasks.where((t) => t.isCompleted).toList()
      ..sort((a, b) {
        if (a.date != null && b.date != null) {
          return b.date!.compareTo(a.date!);
        }
        if (a.date != null) return -1;
        if (b.date != null) return 1;
        return b.sortOrder.compareTo(a.sortOrder);
      });

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Tareas completadas'),
      ),
      body: completed.isEmpty
          ? const _EmptyState()
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: completed.length,
              itemBuilder: (_, i) {
                final t = completed[i];
                final cat = categories
                    .where((c) => c.id == t.categoryId)
                    .firstOrNull;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _CompletedTaskTile(task: t, category: cat),
                );
              },
            ),
    );
  }
}

class _CompletedTaskTile extends ConsumerWidget {
  const _CompletedTaskTile({required this.task, required this.category});

  final Task task;
  final Category? category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateLabel = _formatDate(task.date);
    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(
          Icons.check_circle,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: Text(
          task.title,
          style: const TextStyle(decoration: TextDecoration.lineThrough),
        ),
        subtitle: Text(
          [
            if (category != null) category!.name,
            if (dateLabel != null) dateLabel,
          ].join(' · '),
        ),
        trailing: PopupMenuButton<_Action>(
          tooltip: 'Acciones',
          onSelected: (a) => _handle(context, ref, a),
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: _Action.reactivate,
              child: ListTile(
                leading: Icon(Icons.restart_alt),
                title: Text('Reactivar'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: _Action.delete,
              child: ListTile(
                leading: Icon(Icons.delete_outline),
                title: Text('Eliminar'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handle(BuildContext context, WidgetRef ref, _Action a) async {
    switch (a) {
      case _Action.reactivate:
        await ref.read(taskRepositoryProvider).toggleComplete(task.id, false);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Tarea reactivada'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      case _Action.delete:
        final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('¿Eliminar tarea?'),
            content: Text('"${task.title}" se borrará para siempre.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Eliminar'),
              ),
            ],
          ),
        );
        if (ok == true) {
          await ref.read(taskRepositoryProvider).delete(task.id);
        }
    }
  }

  String? _formatDate(DateTime? d) {
    if (d == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final taskDay = DateTime(d.year, d.month, d.day);
    final diff = today.difference(taskDay).inDays;
    if (diff == 0) return 'hoy';
    if (diff == 1) return 'ayer';
    if (diff < 7) return 'hace $diff días';
    return DateFormat('d MMM', 'es_ES').format(d);
  }
}

enum _Action { reactivate, delete }

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 56,
            color: Theme.of(context).hintColor,
          ),
          const SizedBox(height: 16),
          const Text('Sin tareas completadas'),
          const SizedBox(height: 8),
          Text(
            'Las tareas que completes aparecerán acá',
            style: TextStyle(color: Theme.of(context).hintColor),
          ),
        ],
      ),
    );
  }
}