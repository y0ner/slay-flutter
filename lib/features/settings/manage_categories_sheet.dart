import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/category_repository.dart';
import '../tasks/category_editor_dialog.dart';

class ManageCategoriesScreen extends ConsumerWidget {
  const ManageCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cats = ref.watch(categoriesStreamProvider);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Categorías')),
      floatingActionButton: FloatingActionButton(
        // Mismo FAB contextual que en Tareas: acá es para crear
        // categoría. La edición/eliminación se hace en línea
        // (swipe / long-press) sobre cada item de la lista.
        onPressed: () => showDialog(
          context: context,
          builder: (_) => const CategoryEditorDialog(),
        ),
        child: const Icon(Icons.add),
      ),
      body: cats.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          Future<void> move(int oldIndex, int newIndex) async {
            // ReorderableListView pasa newIndex "desfasado" cuando se mueve
            // hacia abajo (mismo contrato que `onReorder`).
            if (newIndex > oldIndex) newIndex -= 1;
            if (oldIndex == newIndex) return;
            final newList = [...list];
            final item = newList.removeAt(oldIndex);
            newList.insert(newIndex, item);
            await ref.read(categoryRepositoryProvider).reorder(newList);
            ref.invalidate(categoriesStreamProvider);
          }

          return ReorderableListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: list.length,
            onReorder: (oldIndex, newIndex) => move(oldIndex, newIndex),
            itemBuilder: (_, i) {
              final c = list[i];
              final canUp = i > 0;
              final canDown = i < list.length - 1;
              return ListTile(
                key: ValueKey(c.id),
                leading: CircleAvatar(
                  backgroundColor: Color(int.parse(c.color.replaceFirst('#', '0xFF'))),
                  radius: 12,
                ),
                title: Text(c.name),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_up),
                      tooltip: 'Subir',
                      onPressed: canUp ? () => move(i, i - 1) : null,
                    ),
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down),
                      tooltip: 'Bajar',
                      onPressed: canDown ? () => move(i, i + 2) : null,
                    ),
                    ReorderableDragStartListener(
                      index: i,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(Icons.drag_handle),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
