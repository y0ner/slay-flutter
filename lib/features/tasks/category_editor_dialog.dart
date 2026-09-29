import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/terminal_theme.dart';
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
  late String _color = widget.existing?.color ?? '#C2410C';

  // Paleta cálida de la casa + colores planos que armonizan con
  // la rampa papel/tinta del tema terminal.
  static const _colors = [
    '#C2410C', '#2F7A3B', '#8A5A00', '#B91C3C',
    '#795548', '#607D8B', '#9C27B0', '#2196F3',
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
          // Swatches cuadrados: los colores son planos y el seleccionado
          // se marca con borde naranja de la casa.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in _colors)
                GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _parse(c),
                      border: Border.all(
                        color: _color == c
                            ? TerminalTheme.accentOf(context)
                            : TerminalTheme.lineOf(context),
                        width: _color == c ? 2.4 : 1,
                      ),
                    ),
                    child: _color == c
                        ? const Icon(Icons.check,
                            size: 16, color: Colors.white)
                        : null,
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