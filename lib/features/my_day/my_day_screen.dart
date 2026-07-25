import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/models/category.dart';
import '../../data/models/task.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/task_repository.dart';
import '../../widgets/delete_task_dialog.dart';
import '../../widgets/edit_task_dialog.dart';
import '../../widgets/task_card.dart';

/// Pantalla "Mi Día": muestra las tareas cuya `date` (o `reminder`)
/// cae en el día de hoy, ordenadas por sort_order.
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
    final todayTasks = allTasks.where((t) {
      if (t.reminder != null) {
        return DateFormat('yyyy-MM-dd').format(t.reminder!) == today;
      }
      if (t.date != null) {
        return DateFormat('yyyy-MM-dd').format(t.date!) == today;
      }
      return false;
    }).toList()
      ..sort((a, b) {
        if (a.isCompleted != b.isCompleted) {
          return a.isCompleted ? 1 : -1;
        }
        return a.sortOrder.compareTo(b.sortOrder);
      });

    return RefreshIndicator(
      onRefresh: () => ref.refresh(tasksStreamProvider.future),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 96),
        itemCount: todayTasks.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Mi Día',
                      style: Theme.of(context).textTheme.displaySmall),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('EEEE, d MMMM', 'es_ES')
                        .format(DateTime.now())
                        .replaceFirstMapped(RegExp(r'^\w'), (m) => m[0]!.toUpperCase()),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            );
          }
          final t = todayTasks[i - 1];
          final cat = categories.where((c) => c.id == t.categoryId).firstOrNull;
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: TaskCard(
              task: t,
              category: cat,
              onTap: () => context.push('/subtasks/${t.id}'),
              onToggle: () async {
                    await ref.read(taskRepositoryProvider).toggleComplete(
                        t.id, !t.isCompleted);
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
}
