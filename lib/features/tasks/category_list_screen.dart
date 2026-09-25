import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';

import '../../data/models/category.dart';
import '../../data/repositories/category_repository.dart';
import '../../widgets/category_card.dart';
import 'category_editor_dialog.dart';

class CategoryListScreen extends ConsumerStatefulWidget {
  const CategoryListScreen({super.key});

  @override
  ConsumerState<CategoryListScreen> createState() => _CategoryListScreenState();
}

class _CategoryListScreenState extends ConsumerState<CategoryListScreen> {
  bool _editMode = false;
  bool _saving = false;

  /// Lista local que refleja el orden actual durante la edición.
  /// Se mantiene como fuente de verdad incluso después de salir del
  /// modo edición, hasta que el stream de Supabase confirma el nuevo
  /// orden — así el grid nunca muestra datos viejos.
  List<Category>? _localList;

  void _toggleEdit() {
    if (_editMode) {
      // Guardar el orden actual y salir.
      _saveAndExit();
    } else {
      // Entrar: capturar la lista actual como estado local.
      final asyncCats = ref.read(categoriesStreamProvider);
      final currentList = asyncCats.valueOrNull ?? [];
      setState(() {
        _editMode = true;
        _localList = List<Category>.from(currentList);
      });
    }
  }

  /// Persiste el orden de `_localList` a Supabase. No limpia
  /// `_localList` hasta que el stream confirme el nuevo orden.
  Future<void> _saveAndExit() async {
    final list = _localList;
    if (list == null || list.isEmpty) {
      setState(() => _editMode = false);
      return;
    }
    setState(() => _saving = true);
    try {
      final renumbered = [
        for (var i = 0; i < list.length; i++)
          list[i].copyWith(sortOrder: i),
      ];
      await ref.read(categoryRepositoryProvider).reorder(renumbered);
      ref.invalidate(categoriesStreamProvider);
    } catch (_) {}
    if (mounted) {
      setState(() {
        _saving = false;
        _editMode = false;
        _localList = null; // ← LIMPIAR para que el próximo edit use datos frescos
      });
    }
  }

  /// `reorderable_grid_view` devuelve como `newIndex` la posición
  /// FINAL donde el item debe quedar (no un slot entre items).
  /// Ejemplo oficial del paquete:
  ///   final element = data.removeAt(oldIndex);
  ///   data.insert(newIndex, element);
  void _onReorder(int oldIndex, int newIndex) {
    final list = _localList;
    if (list == null || oldIndex == newIndex) return;
    final updated = [...list];
    final moved = updated.removeAt(oldIndex);
    updated.insert(newIndex, moved);
    setState(() => _localList = updated);
  }

  @override
  Widget build(BuildContext context) {
    final asyncCats = ref.watch(categoriesStreamProvider);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Tareas'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            asyncCats.maybeWhen(
              data: (list) => list.length > 1
                  ? IconButton(
                      tooltip: _editMode ? 'Guardar' : 'Reordenar',
                      icon: Icon(_editMode ? Icons.check : Icons.reorder),
                      onPressed: _toggleEdit,
                    )
                  : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      // FIX: el FAB lo provee el HomeShell (ruta /tasks → "Nueva
      // categoría"). Antes había un FAB hardcodeado ACÁ que se
      // duplicaba con el del shell y generaba dos botones apilados.
      // Peor: como `context.push('/tasks/:id')` deja CategoryListScreen
      // en el Navigator stack, durante el frame intermedio el FAB de
      // esta pantalla seguía visible mientras el shell todavía
      // evaluaba `currentLocation == '/tasks'`, abriendo el editor de
      // categorías en vez del QuickAddDialog. Un único FAB (el del
      // shell) elimina la ambigüedad.
      body: asyncCats.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          // Durante edición usamos _localList (orden local).
          // Fuera de edición usamos el stream (datos de Supabase).
          final displayList =
              _editMode ? (_localList ?? list) : list;
          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(categoriesStreamProvider),
            child: displayList.isEmpty
                ? const _EmptyState()
                : _editMode
                    ? _ReorderGrid(
                        list: displayList,
                        onReorder: _onReorder,
                      )
                    : _BrowseGrid(list: displayList),
          );
        },
      ),
    );
  }
}

/// Grid normal: tap → navegar, long-press → editar.
class _BrowseGrid extends ConsumerWidget {
  const _BrowseGrid({required this.list});
  final List<Category> list;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          onLongPress: () => _showEdit(context, ref, c),
        );
      },
    );
  }

  void _showEdit(BuildContext context, WidgetRef ref, Category c) {
    showDialog(
      context: context,
      builder: (_) => CategoryEditorDialog(
        existing: c,
        onDelete: () => ref.read(categoryRepositoryProvider).delete(c.id),
      ),
    );
  }
}

/// Grid de reorder: cada tile muestra la CategoryCard real.
/// Se arrastra con long-press en cualquier parte del tile (el paquete
/// `reorderable_grid_view` maneja la detección de drag internamente).
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
        return CategoryCard(
          key: ValueKey(c.id),
          category: c,
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
