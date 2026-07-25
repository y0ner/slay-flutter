import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';

import '../../data/models/category.dart';
import '../../data/repositories/category_repository.dart';
import '../../widgets/category_card.dart';

class CategoryListScreen extends ConsumerStatefulWidget {
  const CategoryListScreen({super.key});

  @override
  ConsumerState<CategoryListScreen> createState() => _CategoryListScreenState();
}

class _CategoryListScreenState extends ConsumerState<CategoryListScreen> {
  /// Modo edición: oculta FAB + handler de crear; tap y long-press
  /// deshabilitados en cada card; cada tile se vuelve draggable.
  /// Sale con el botón ✓ del AppBar.
  bool _editMode = false;

  void _toggleEdit() => setState(() => _editMode = !_editMode);

  /// Aplica el reorder: actualiza el array local optimistamente, lo
  /// persiste en Supabase (`sort_order` 0..N-1) e invalida el stream.
  Future<void> _onReorder(List<Category> list, int oldIndex, int newIndex) async {
    // El paquete usa la misma convención que ReorderableListView:
    // si newIndex > oldIndex, hay que restar 1 después de remover.
    final updated = [...list];
    final moved = updated.removeAt(oldIndex);
    updated.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, moved);
    await ref.read(categoryRepositoryProvider).reorder(updated);
    ref.invalidate(categoriesStreamProvider);
  }

  @override
  Widget build(BuildContext context) {
    final asyncCats = ref.watch(categoriesStreamProvider);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Tareas'),
        actions: [
          asyncCats.maybeWhen(
            data: (list) => list.length > 1
                ? IconButton(
                    tooltip: _editMode ? 'Listo' : 'Reordenar',
                    icon: Icon(_editMode ? Icons.check : Icons.reorder),
                    onPressed: _toggleEdit,
                  )
                : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      floatingActionButton: _editMode
          ? null
          : FloatingActionButton(
              onPressed: () => _showAddDialog(context),
              child: const Icon(Icons.add),
            ),
      body: asyncCats.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(categoriesStreamProvider),
          child: list.isEmpty
              ? const _EmptyState()
              : _editMode
                  ? _ReorderGrid(
                      list: list,
                      onReorder: (oldI, newI) => _onReorder(list, oldI, newI),
                    )
                  : _BrowseGrid(list: list),
        ),
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    showDialog(context: context, builder: (_) => const _CategoryDialog());
  }
}

/// Grid normal: tap → navegar, long-press → editar.
class _BrowseGrid extends StatelessWidget {
  const _BrowseGrid({required this.list});
  final List<Category> list;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.05,
      ),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final c = list[i];
        return CategoryCard(
          key: ValueKey(c.id),
          category: c,
          onTap: () => context.push('/tasks/${c.id}'),
          onLongPress: () => _showEdit(context, c),
        );
      },
    );
  }

  void _showEdit(BuildContext context, Category c) {
    showDialog(
      context: context,
      builder: (_) => _CategoryDialog(existing: c),
    );
  }
}

/// Grid de reorder: cada tile muestra la CategoryCard real (con un
/// overlay con handle visible) y se arrastra con long-press.
class _ReorderGrid extends StatelessWidget {
  const _ReorderGrid({required this.list, required this.onReorder});
  final List<Category> list;
  final ReorderCallback onReorder;

  @override
  Widget build(BuildContext context) {
    return ReorderableGridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.05,
      ),
      itemCount: list.length,
      dragEnabled: true,
      onReorder: onReorder,
      itemBuilder: (context, i) {
        final c = list[i];
        return Stack(
          key: ValueKey(c.id),
          children: [
            Positioned.fill(child: CategoryCard(category: c)),
            // Overlay con handle, alineado top-left. Captura el drag.
            Positioned(
              top: 6,
              left: 6,
              child: ReorderableDragStartListener(
                index: i,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.drag_indicator,
                      color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 200),
        Center(
          child: Column(
            children: [
              Icon(Icons.folder_off,
                  size: 56, color: Theme.of(context).dividerColor),
              const SizedBox(height: 16),
              const Text('Sin categorías todavía'),
              const SizedBox(height: 8),
              Text(
                'Tocá el botón + para crear la primera',
                style: TextStyle(color: Theme.of(context).hintColor),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CategoryDialog extends ConsumerStatefulWidget {
  const _CategoryDialog({this.existing});
  final Category? existing;

  @override
  ConsumerState<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends ConsumerState<_CategoryDialog> {
  late final _ctrl =
      TextEditingController(text: widget.existing?.name ?? '');
  String _color = '#4CAF50';

  static const _colors = [
    '#4CAF50', '#2196F3', '#9C27B0', '#F44336',
    '#FF9800', '#795548', '#607D8B', '#E91E63',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) _color = widget.existing!.color;
  }

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
    return AlertDialog(
      title: Text(widget.existing == null ? 'Nueva categoría' : 'Editar'),
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
        if (widget.existing != null)
          TextButton(
            onPressed: () async {
              await ref
                  .read(categoryRepositoryProvider)
                  .delete(widget.existing!.id);
              if (context.mounted) Navigator.pop(context);
              ref.invalidate(categoriesStreamProvider);
            },
            child: const Text('Eliminar'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () async {
            final repo = ref.read(categoryRepositoryProvider);
            if (widget.existing == null) {
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
