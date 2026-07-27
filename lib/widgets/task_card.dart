import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/local/pomodoro_stats.dart';
import '../data/models/category.dart';
import '../data/models/task.dart';

/// Tarjeta visual de una tarea. Equivalente directo al `TaskCard`
/// de Slay-Desktop pero con la API idiomática de Flutter.
///
/// Gestos y acciones:
/// - **Swipe derecha** (`startToEnd`) → marca como completada/pendiente.
/// - **Swipe izquierda** (`endToStart`) → abre el diálogo de edición
///   (vía `onEdit`).
/// - **Botón Timer** → `onSendToFocus` (lleva a Pomodoro).
/// - **Botón Copiar** → copia el título al portapapeles, muestra
///   feedback de check verde durante 1.5s.
/// - **Botón Delete** → `onDelete`.
///
/// Badges:
/// - Categoría (color de fondo de la categoría al 15% de opacity).
/// - Fecha / recordatorio con ícono de calendario o campana.
/// - Subtasks (contador en color primary, solo si tiene).
class TaskCard extends ConsumerStatefulWidget {
  const TaskCard({
    super.key,
    required this.task,
    required this.onTap,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    this.onSendToFocus,
    this.category,
  });

  final Task task;
  final Category? category;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onSendToFocus;

  @override
  ConsumerState<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends ConsumerState<TaskCard> {
  bool _justCopied = false;

  Color _parseColor(String h) =>
      Color(int.parse(h.replaceFirst('#', '0xFF')));

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.task.title));
    if (!mounted) return;
    setState(() => _justCopied = true);
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    setState(() => _justCopied = false);
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final cat = widget.category;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final catColor = cat != null
        ? _parseColor(cat.color)
        : Theme.of(context).colorScheme.primary;

    final subtle = Theme.of(context).colorScheme.onSurfaceVariant;
    final dateChipColor = Theme.of(context).colorScheme.surface;

    // Pomodoros invertidos en esta tarea (sólo si > 0, sino ni se muestra).
    final pomodoroCount = ref.watch(pomodoroStatsProvider
        .select((s) => s.perTask[task.id] ?? 0));
    // Tiempo total invertido (en minutos) usando el preset estándar
    // como aproximación. El caller puede refinar si quiere exactitud
    // por preset persistido por sesión (futuro enhancement).
    final totalMinutes = pomodoroCount * 25;
    // Última sesión (hace cuánto se trabajó en esta tarea).
    final lastSession = ref.watch(pomodoroStatsProvider
        .select((s) => s.perTaskHistory[task.id]?.lastOrNull));

    return Dismissible(
      key: ValueKey('task-${task.id}'),
      // Solo permitimos swipe horizontal.
      direction: DismissDirection.horizontal,
      // Necesitamos confirmDismiss para no "destruir" la tarjeta: en
      // ambos casos la swipe sólo dispara el callback y reseteamos.
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          widget.onToggle();
        } else if (dir == DismissDirection.endToStart) {
          widget.onEdit();
        }
        return false;
      },
      background: _SwipeBg(
        alignment: Alignment.centerLeft,
        color: task.isCompleted ? Colors.grey : Colors.green.shade600,
        icon: Icons.check_box,
      ),
      secondaryBackground: _SwipeBg(
        alignment: Alignment.centerRight,
        color: Theme.of(context).colorScheme.secondary,
        icon: Icons.edit,
      ),
      child: Card(
        elevation: isDark ? 0 : 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: subtle.withValues(alpha: 0.15), width: 1),
        ),
        color: Theme.of(context).colorScheme.surface,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    decoration: task.isCompleted
                        ? TextDecoration.lineThrough
                        : null,
                    color: task.isCompleted ? subtle : null,
                  ),
                ),
                if (pomodoroCount > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    '⏱ ${_formatMinutes(totalMinutes)}${_agoLabel(lastSession)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: subtle,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                if (task.hasSubtasks) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${task.subtaskCount} subtareas',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Divider(height: 1, color: subtle.withValues(alpha: 0.15)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (cat != null) _CategoryChip(name: cat.name, color: catColor),
                    if (cat != null) const SizedBox(width: 6),
                    _DateChip(task: task, bg: dateChipColor, color: subtle),
                    if (pomodoroCount > 0) ...[
                      const SizedBox(width: 6),
                      _PomodoroChip(count: pomodoroCount),
                    ],
                    const Spacer(),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.onSendToFocus != null && !task.isCompleted)
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Enviar a Focus',
                            onPressed: widget.onSendToFocus,
                            icon: const Icon(
                              Icons.timer,
                              color: Color(0xFF10B981),
                              size: 18,
                            ),
                          ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Copiar',
                          onPressed: _copy,
                          icon: Icon(
                            _justCopied ? Icons.check : Icons.content_copy,
                            color: _justCopied
                                ? const Color(0xFF10B981)
                                : Theme.of(context).colorScheme.primary,
                            size: 18,
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Eliminar',
                          onPressed: widget.onDelete,
                          icon: Icon(
                            Icons.delete_outline,
                            color: Theme.of(context).colorScheme.error,
                            size: 18,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PomodoroChip extends StatelessWidget {
  const _PomodoroChip({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    const tomato = Color(0xFFEF4444); // mismo rojo del emoji 🍅
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: tomato.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🍅', style: TextStyle(fontSize: 11)),
          const SizedBox(width: 3),
          Text(
            '$count',
            style: const TextStyle(
              fontSize: 11,
              color: tomato,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.name, required this.color});
  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        name,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({required this.task, required this.bg, required this.color});
  final Task task;
  final Color bg;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final d = task.reminder ?? task.date;
    if (d == null) return const SizedBox.shrink();
    final hasTime = d.hour != 0 || d.minute != 0;
    final isReminder = task.reminder != null;
    final icon =
        isReminder ? Icons.notifications_active : Icons.calendar_today;
    final datePart = DateFormat('dd/MM/yyyy').format(d);
    final text = hasTime ? '$datePart ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}' : datePart;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(fontSize: 11, color: color),
          ),
        ],
      ),
    );
  }
}

class _SwipeBg extends StatelessWidget {
  const _SwipeBg({
    required this.alignment,
    required this.color,
    required this.icon,
  });
  final Alignment alignment;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Icon(icon, color: Colors.white, size: 28),
    );
  }
}

/// Formatea minutos como "1h 15m" o "45m". Para 0 → "0m".
String _formatMinutes(int minutes) {
  if (minutes < 60) return '${minutes}m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}

/// Etiqueta corta de "hace cuánto" para la última sesión de pomodoro.
/// null si nunca se trabajó. Compacto: "hoy", "ayer", "hace 3d".
String _agoLabel(DateTime? last) {
  if (last == null) return '';
  final diff = DateTime.now().difference(last);
  if (diff.inMinutes < 1) return ' · ahora';
  if (diff.inMinutes < 60) return ' · hace ${diff.inMinutes}m';
  if (diff.inHours < 24 && last.day == DateTime.now().day) {
    return ' · hoy';
  }
  final yesterday = DateTime.now().subtract(const Duration(days: 1));
  if (last.year == yesterday.year &&
      last.month == yesterday.month &&
      last.day == yesterday.day) {
    return ' · ayer';
  }
  if (diff.inDays < 7) return ' · hace ${diff.inDays}d';
  if (diff.inDays < 30) return ' · hace ${diff.inDays ~/ 7}sem';
  return ' · hace ${diff.inDays ~/ 30}m';
}
