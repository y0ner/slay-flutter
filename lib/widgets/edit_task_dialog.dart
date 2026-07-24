import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/models/task.dart';
import '../data/repositories/task_repository.dart';

/// Diálogo reusado por My Day, Tareas y Calendario para editar
/// el título y el recordatorio de una tarea existente.
class EditTaskDialog extends ConsumerStatefulWidget {
  const EditTaskDialog({super.key, required this.task});
  final Task task;

  @override
  ConsumerState<EditTaskDialog> createState() => _EditTaskDialogState();
}

class _EditTaskDialogState extends ConsumerState<EditTaskDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.task.title);
  late DateTime? _reminder;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _reminder = widget.task.reminder;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reminderText = _reminder == null
        ? 'Sin recordatorio'
        : 'Recordatorio: ${DateFormat('dd/MM/yyyy HH:mm').format(_reminder!)}';
    return AlertDialog(
      title: const Text('Editar tarea'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _ctrl,
            decoration: const InputDecoration(labelText: 'Título'),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: Text(reminderText)),
              if (_reminder != null)
                TextButton(
                  onPressed: () => setState(() => _reminder = null),
                  child: const Text('Quitar'),
                ),
              TextButton(
                onPressed: () async {
                  final now = DateTime.now();
                  final d = await showDatePicker(
                    context: context,
                    firstDate: now,
                    lastDate: now.add(const Duration(days: 365)),
                    initialDate: _reminder ?? now,
                  );
                  if (d == null) return;
                  if (!context.mounted) return;
                  final t = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(_reminder ?? now),
                  );
                  if (t == null) return;
                  setState(() => _reminder =
                      DateTime(d.year, d.month, d.day, t.hour, t.minute));
                },
                child: const Text('Elegir'),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: _saving
              ? null
              : () async {
                  if (_ctrl.text.trim().isEmpty) return;
                  setState(() => _saving = true);
                  try {
                    await ref.read(taskRepositoryProvider).update(
                          widget.task.id,
                          title: _ctrl.text.trim(),
                          reminder: _reminder,
                        );
                    if (mounted) Navigator.pop(context);
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  } finally {
                    if (mounted) setState(() => _saving = false);
                  }
                },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
