import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/category.dart';
import '../../data/repositories/category_repository.dart';
import '../../widgets/category_card.dart';

class CategoryListScreen extends ConsumerWidget {
  const CategoryListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncCats = ref.watch(categoriesStreamProvider);
    return asyncCats.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (list) => RefreshIndicator(
        onRefresh: () async => ref.invalidate(categoriesStreamProvider),
        child: GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 32, 16, 96),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.05,
          ),
          itemCount: list.length + 1,
          itemBuilder: (context, i) {
            if (i == list.length) {
              return _AddCategoryTile(
                onTap: () => _showAddDialog(context, ref),
              );
            }
            final c = list[i];
            return CategoryCard(
              category: c,
              onTap: () => context.push('/tasks/${c.id}'),
              onLongPress: () => _showEditDialog(context, ref, c),
            );
          },
        ),
      ),
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    showDialog(context: context, builder: (_) => const _CategoryDialog());
  }

  void _showEditDialog(BuildContext context, WidgetRef ref, Category c) {
    showDialog(
      context: context,
      builder: (_) => _CategoryDialog(existing: c),
    );
  }
}

class _AddCategoryTile extends StatelessWidget {
  const _AddCategoryTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Theme.of(context).dividerColor,
            style: BorderStyle.solid,
          ),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 32),
              SizedBox(height: 4),
              Text('Nueva'),
            ],
          ),
        ),
      ),
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
