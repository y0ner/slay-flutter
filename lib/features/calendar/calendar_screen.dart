import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
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

  /// Devuelve la lista de tareas del día, agrupando por date/reminder.
  Map<DateTime, List<Task>> _groupByDay(List<Task> all) {
    final byDay = <DateTime, List<Task>>{};
    for (final t in all) {
      final d = t.date ?? t.reminder;
      if (d == null) continue;
      final day = DateTime(d.year, d.month, d.day);
      byDay.putIfAbsent(day, () => []).add(t);
    }
    return byDay;
  }

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(tasksStreamProvider);
    final categoriesAsync = ref.watch(categoriesStreamProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: tasksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (all) {
          final byDay = _groupByDay(all);
          final categories = categoriesAsync.maybeWhen(
            data: (c) => c,
            orElse: () => <Category>[],
          );
          final catById = {for (final c in categories) c.id: c};
          final selKey = _selected == null
              ? null
              : DateTime(_selected!.year, _selected!.month, _selected!.day);
          final selectedTasks =
              selKey == null ? <Task>[] : (byDay[selKey] ?? const <Task>[]);
          final today = DateTime.now();
          final isOnToday = isSameDay(_selected, today);

          return Column(
            children: [
              _CalendarHeader(
                focused: _focused,
                format: _format,
                onPrev: () => setState(() {
                  _focused = _shiftMonth(_focused, -1);
                }),
                onNext: () => setState(() {
                  _focused = _shiftMonth(_focused, 1);
                }),
                onFormatChanged: (f) => setState(() => _format = f),
                onToday: () => setState(() {
                  _focused = DateTime.now();
                  _selected = DateTime.now();
                }),
                hideToday: isOnToday,
              ),
              TableCalendar<Task>(
                firstDay: DateTime.utc(2020, 1, 1),
                lastDay: DateTime.utc(2035, 12, 31),
                focusedDay: _focused,
                rowHeight: 44,
                daysOfWeekHeight: 20,
                selectedDayPredicate: (d) => isSameDay(d, _selected),
                eventLoader: (d) =>
                    byDay[DateTime(d.year, d.month, d.day)] ?? const [],
                calendarFormat: _format,
                startingDayOfWeek: StartingDayOfWeek.monday,
                locale: 'es_ES',
                // Sin header del paquete: el nuestro (con Mes/Semana/Día +
                // chevrones + Hoy) está arriba como `_CalendarHeader`.
                headerVisible: false,
                onFormatChanged: (f) => setState(() => _format = f),
                onPageChanged: (d) => _focused = d,
                onDaySelected: (sel, foc) => setState(() {
                  _selected = sel;
                  _focused = foc;
                }),
                daysOfWeekStyle: DaysOfWeekStyle(
                  weekdayStyle: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                  weekendStyle: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                calendarStyle: CalendarStyle(
                  outsideDaysVisible: false,
                  cellMargin: const EdgeInsets.all(4),
                  defaultTextStyle: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 14,
                  ),
                  weekendTextStyle: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 14,
                  ),
                  outsideTextStyle: TextStyle(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.35),
                    fontSize: 14,
                  ),
                  todayDecoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.primary, width: 1.5),
                  ),
                  todayTextStyle: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  selectedDecoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                  ),
                  selectedTextStyle: TextStyle(
                    color: scheme.onPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                calendarBuilders: CalendarBuilders<Task>(
                  markerBuilder: (context, day, events) {
                    if (events.isEmpty) return const SizedBox.shrink();
                    // Mezcla única de colores (categoría de la primera
                    // tarea de cada categoría). Hasta 3 dots.
                    final colors = <Color>[];
                    final fallback = scheme.primary;
                    for (final t in events) {
                      final c = catById[t.categoryId];
                      final col = c != null
                          ? _parseColor(c.color)
                          : fallback;
                      if (!colors.contains(col)) colors.add(col);
                      if (colors.length >= 3) break;
                    }
                    return Positioned(
                      bottom: 2,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < colors.length; i++) ...[
                            if (i > 0) const SizedBox(width: 2),
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: colors[i],
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 4),
              _SelectedDayHeader(date: _selected, count: selectedTasks.length),
              const SizedBox(height: 4),
              Expanded(
                child: selectedTasks.isEmpty
                    ? const _EmptyDay()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                        itemCount: selectedTasks.length,
                        itemBuilder: (_, i) {
                          final t = selectedTasks[i];
                          final cat = catById[t.categoryId];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: TaskCard(
                              task: t,
                              category: cat,
                              onTap: () => context.push('/subtasks/${t.id}'),
                              onToggle: () async {
                                await ref
                                    .read(taskRepositoryProvider)
                                    .toggleComplete(t.id, !t.isCompleted);
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
      ),
    );
  }
}

Color _parseColor(String h) =>
    Color(int.parse(h.replaceFirst('#', '0xFF')));

DateTime _shiftMonth(DateTime d, int delta) {
  final m = d.month + delta;
  if (m > 12) return DateTime(d.year + 1, 1, d.day);
  if (m < 1) return DateTime(d.year - 1, 12, d.day);
  return DateTime(d.year, m, d.day);
}

/// Header custom: mes/año grande, chevrones, segmented Mes/Semana/Día,
/// y botón "Hoy" cuando el usuario se alejó del día actual.
class _CalendarHeader extends StatelessWidget {
  const _CalendarHeader({
    required this.focused,
    required this.format,
    required this.onPrev,
    required this.onNext,
    required this.onFormatChanged,
    required this.onToday,
    required this.hideToday,
  });

  final DateTime focused;
  final CalendarFormat format;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ValueChanged<CalendarFormat> onFormatChanged;
  final VoidCallback onToday;
  final bool hideToday;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final monthYear =
        DateFormat('MMMM y', 'es_ES').format(focused).toUpperCase();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  monthYear,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Mes anterior',
                onPressed: onPrev,
                icon: Icon(Icons.chevron_left, color: scheme.primary),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Mes siguiente',
                onPressed: onNext,
                icon: Icon(Icons.chevron_right, color: scheme.primary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SegmentedButton<CalendarFormat>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
                segments: const [
                  ButtonSegment(
                      value: CalendarFormat.month,
                      label: Text('Mes'),
                      icon: Icon(Icons.calendar_view_month, size: 16)),
                  ButtonSegment(
                      value: CalendarFormat.twoWeeks,
                      label: Text('2 sem'),
                      icon: Icon(Icons.calendar_view_week, size: 16)),
                  ButtonSegment(
                      value: CalendarFormat.week,
                      label: Text('Sem'),
                      icon: Icon(Icons.calendar_view_day, size: 16)),
                ],
                selected: {format},
                onSelectionChanged: (s) => onFormatChanged(s.first),
              ),
              const Spacer(),
              if (!hideToday)
                TextButton.icon(
                  onPressed: onToday,
                  icon: const Icon(Icons.today, size: 16),
                  label: const Text('Hoy'),
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.primary,
                    textStyle: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Subtítulo bajo el calendario: nombre del día seleccionado + contador.
class _SelectedDayHeader extends StatelessWidget {
  const _SelectedDayHeader({required this.date, required this.count});
  final DateTime? date;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final d = date;
    if (d == null) return const SizedBox.shrink();
    final isToday = isSameDay(d, DateTime.now());
    final label =
        DateFormat('EEEE d \'de\' MMMM', 'es_ES').format(d);
    final capitalized = label[0].toUpperCase() + label.substring(1);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          if (isToday) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'HOY',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              capitalized,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ),
          Text(
            count == 0
                ? 'Sin tareas'
                : '$count ${count == 1 ? "tarea" : "tareas"}',
            style: TextStyle(
              fontSize: 13,
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyDay extends StatelessWidget {
  const _EmptyDay();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event_busy,
              size: 48, color: scheme.onSurfaceVariant.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text(
            'Nada pendiente este día',
            style: TextStyle(
              fontSize: 15,
              color: scheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tocá una fecha para ver sus tareas',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}