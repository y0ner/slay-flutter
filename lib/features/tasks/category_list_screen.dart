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
  /// Modo edición: oculta FAB + handler de crear; tap y long-press
  /// deshabilitados en cada card; cada tile se vuelve draggable.
  /// Sale con el botón ✓ del AppBar.
  bool _editMode = false;

  void _toggleEdit() => setState(() => _editMode = !_editMode);

  /// Aplica el reorder: actualiza el array local optimistamente, lo
  /// persiste en Supabase (`sort_order` 0..N-1) e invalida el stream.
  ///
  /// FIX: `reorderable_grid_view` (como `ReorderableListView`) devuelve
  /// `newIndex` con la semántica estándar de Flutter: si arrastrás un
  /// item hacia ABAJO (oldIndex < newIndex), el newIndex incluye el
  /// hueco del item que se removió, así que hay que restar 1 para
  /// obtener la posición real destino. El código anterior tenía la
  /// corrección invertida, lo que causaba que las categorías se
  /// duplicaran en vez de intercambiarse.
  void _onReorder(List<Category> list, int oldIndex, int newIndex) {
    // Ajuste estándar de Flutter: cuando el item se mueve hacia abajo,
    // newIndex viene desplazado +1 por el hueco del item removido.
    if (oldIndex < newIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;
    final updated = [...list];
    final moved = updated.removeAt(oldIndex);
    updated.insert(newIndex, moved);
    // Persistimos el nuevo orden con sort_order 0..N-1.
    ref.read(categoryRepositoryProvider).reorder(updated).then((_) {
      ref.invalidate(categoriesStreamProvider);
    });
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
