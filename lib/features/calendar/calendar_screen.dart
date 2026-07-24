import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../data/models/category.dart';
import '../../data/models/task.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/task_repository.dart';
import '../../widgets/delete_task_dialog.dart';
import '../../widgets/edit_task_dialog.dart';
import '../../widgets/task_card.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});
  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  DateTime _focused = DateTime.now();
  DateTime? _selected = DateTime.now();
  CalendarFormat _format = CalendarFormat.week;

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(tasksStreamProvider);
    final categoriesAsync = ref.watch(categoriesStreamProvider);
    return tasksAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (all) {
        // Agrupa tareas por día (date o reminder).
        final byDay = <DateTime, List<Task>>{};
        for (final t in all) {
          final d = t.date ?? t.reminder;
          if (d == null) continue;
          final day = DateTime(d.year, d.month, d.day);
          byDay.putIfAbsent(day, () => []).add(t);
        }
        final selKey = _selected == null
            ? null
            : DateTime(_selected!.year, _selected!.month, _selected!.day);
        final selectedTasks = selKey == null ? <Task>[] : (byDay[selKey] ?? const <Task>[]);
        final categories = categoriesAsync.maybeWhen(
          data: (c) => c,
          orElse: () => <Category>[],
        );

        return Column(
          children: [
            TableCalendar<Task>(
              firstDay: DateTime.utc(2020, 1, 1),
              lastDay: DateTime.utc(2035, 12, 31),
              focusedDay: _focused,
              selectedDayPredicate: (d) => isSameDay(d, _selected),
              eventLoader: (d) => byDay[DateTime(d.year, d.month, d.day)] ?? const [],
              calendarFormat: _format,
              startingDayOfWeek: StartingDayOfWeek.monday,
              locale: 'es_ES',
              onFormatChanged: (f) => setState(() => _format = f),
              onPageChanged: (d) => _focused = d,
              onDaySelected: (sel, foc) {
                setState(() {
                  _selected = sel;
                  _focused = foc;
                });
              },
            ),
            const SizedBox(height: 8),
            Expanded(
              child: selectedTasks.isEmpty
                  ? const Center(child: Text('Sin tareas para este día'))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                      itemCount: selectedTasks.length,
                      itemBuilder: (_, i) {
                        final t = selectedTasks[i];
                        final cat = categories
                            .where((c) => c.id == t.categoryId)
                            .firstOrNull;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: TaskCard(
                            task: t,
                            category: cat,
                            onTap: () => context.push('/subtasks/${t.id}'),
                            onToggle: () => ref
                                .read(taskRepositoryProvider)
                                .toggleComplete(t.id, !t.isCompleted),
                            onEdit: () => showDialog(
                              context: context,
                              builder: (_) => EditTaskDialog(task: t),
                            ),
                            onDelete: () => showDialog(
                              context: context,
                              builder: (_) => DeleteTaskDialog(task: t),
                            ),
                            onSendToFocus: () =>
                                context.go('/pomodoro?task=${t.id}'),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
