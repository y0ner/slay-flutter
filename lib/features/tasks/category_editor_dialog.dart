import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/category.dart';
import '../../data/repositories/category_repository.dart';

/// Diálogo de crear/editar categoría.
///
/// Reusado por:
/// - `CategoryListScreen` (Tareas) — para crear y editar categorías
///   (long-press sobre una card). El botón "Eliminar" se muestra
///   sólo cuando se pasa `onDelete`.
/// - `ManageCategoriesScreen` (Ajustes) — sólo para crear (la edición
///   y eliminación viven en línea dentro del reorderable list).
class CategoryEditorDialog extends ConsumerStatefulWidget {
  const CategoryEditorDialog({super.key, this.existing, this.onDelete});

  final Category? existing;

  /// Si se provee, se muestra el botón "Eliminar" en el diálogo.
  /// Útil cuando el llamador quiere permitir borrar la categoría
  /// (caso: edición desde la lista de Tareas).
  final Future<void> Function()? onDelete;

  @override
  ConsumerState<CategoryEditorDialog> createState() =>
      _CategoryEditorDialogState();
}

class _CategoryEditorDialogState extends ConsumerState<CategoryEditorDialog> {
  late final _ctrl =
      TextEditingController(text: widget.existing?.name ?? '');
  late String _color = widget.existing?.color ?? '#4CAF50';

  static const _colors = [
    '#4CAF50', '#2196F3', '#9C27B0', '#F44336',
    '#FF9800', '#795548', '#607D8B', '#E91E63',
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color _parse(String h) {
    final v = int.parse(h.replaceFirst('#', '0xFF'));
    return Color(v);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
    return AlertDialog(
      title: Text(isEditing ? 'Editar categoría' : 'Nueva categoría'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _ctrl,
            decoration: const InputDecoration(labelText: 'Nombre'),
            autofocus: true,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              for (final c in _colors)
                GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _parse(c),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _color == c ? Colors.white : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      actions: [
        if (widget.onDelete != null)
          TextButton(
            onPressed: () async {
              await widget.onDelete!();
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Eliminar'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () async {
            final repo = ref.read(categoryRepositoryProvider);
            if (!isEditing) {
              await repo.create(name: _ctrl.text.trim(), color: _color);
            } else {
              await repo.update(
                widget.existing!.id,
                name: _ctrl.text.trim(),
                color: _color,
              );
            }
            if (mounted) Navigator.pop(context);
            ref.invalidate(categoriesStreamProvider);
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}