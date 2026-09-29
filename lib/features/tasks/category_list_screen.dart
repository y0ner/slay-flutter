import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/terminal_theme.dart';
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
  bool _hasChanged = false;

  /// Lista local: fuente de verdad durante edición y como update
  /// optimista post-save hasta que el stream confirme el nuevo orden.
  List<Category>? _localList;

  // ─── Modo edición ──────────────────────────────────────────

  void _toggleEdit() {
    if (_editMode) {
      _saveAndExit();
    } else {
      final currentList = _localList ??
          ref.read(categoriesStreamProvider).valueOrNull ??
          ref.read(cachedCategoriesStreamProvider).valueOrNull ??
          [];
      setState(() {
        _editMode = true;
        _hasChanged = false;
        _localList = List<Category>.from(currentList);
      });
    }
  }

  Future<void> _saveAndExit() async {
    final list = _localList;
    if (list == null || list.isEmpty) {
      setState(() => _editMode = false);
      return;
    }
    if (!_hasChanged) {
      setState(() {
        _editMode = false;
        _localList = null;
      });
      return;
    }
    setState(() => _saving = true);
    try {
      final renumbered = [
        for (var i = 0; i < list.length; i++)
          list[i].copyWith(sortOrder: i),
      ];
      await ref.read(categoryRepositoryProvider).reorder(renumbered);
      if (mounted) {
        setState(() {
          _localList = renumbered;
          _saving = false;
          _editMode = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Callback de ReorderableListView.onReorderItem (Flutter 3.41+).
  /// A diferencia del viejo onReorder, el newIndex ya viene ajustado
  /// (la posición final después de remover el item).
  void _onReorder(int oldIndex, int newIndex) {
    final list = _localList;
    if (list == null || oldIndex == newIndex) return;
    final updated = [...list];
    final moved = updated.removeAt(oldIndex);
    updated.insert(newIndex, moved);
    setState(() {
      _localList = updated;
      _hasChanged = true;
    });
  }

  // ─── Helpers ───────────────────────────────────────────────

  static bool _orderedIdsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static Color _parseColor(String h) {
    final v = int.parse(h.replaceFirst('#', '0xFF'));
    return Color(v);
  }

  // ─── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final asyncCats = ref.watch(categoriesStreamProvider);
    final cachedCats = ref.watch(cachedCategoriesStreamProvider);

    final displayList = _localList ??
        asyncCats.valueOrNull ??
        cachedCats.valueOrNull ??
        const <Category>[];

    // Update optimista: cuando _localList existe y ya no estamos editando,
    // verificar si el stream confirma el orden para volver al stream como fuente de verdad.
    if (_localList != null && !_editMode && asyncCats.hasValue) {
      final serverList = asyncCats.value!;
      final localIds = _localList!.map((c) => c.id).toList();
      final streamIds = serverList.map((c) => c.id).toList();
      if (_orderedIdsEqual(localIds, streamIds)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _localList = null);
        });
      }
    }

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
            _buildReorderButton(displayList.length),
        ],
      ),
      body: displayList.isNotEmpty
          ? RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(categoriesStreamProvider);
                ref.invalidate(cachedCategoriesStreamProvider);
              },
              child: _editMode
                  ? _buildReorderList(context)
                  : _BrowseGrid(list: displayList),
            )
          : asyncCats.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off_rounded, size: 48, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        'No se pudieron cargar las categorías',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$e',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () => ref.invalidate(categoriesStreamProvider),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reintentar'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (_) => RefreshIndicator(
                onRefresh: () async => ref.invalidate(categoriesStreamProvider),
                child: const _EmptyState(),
              ),
            ),
    );
  }

  Widget _buildReorderButton(int count) {
    if (count <= 1) return const SizedBox.shrink();
    return IconButton(
      tooltip: _editMode ? 'Guardar' : 'Reordenar',
      icon: Icon(_editMode ? Icons.check : Icons.reorder),
      onPressed: _toggleEdit,
    );
  }

  /// Lista reordenable nativa de Flutter. Cada tile tiene un
  /// drag handle (≡) que funciona en mobile y desktop.
  Widget _buildReorderList(BuildContext context) {
    final list = _localList ?? [];
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      proxyDecorator: (child, index, animation) {
        return AnimatedBuilder(
          animation: animation,
          builder: (_, child) => Material(
            color: TerminalTheme.panelOf(context),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
              side: BorderSide(color: TerminalTheme.accentOf(context), width: 1.4),
            ),
            child: child,
          ),
          child: child,
        );
      },
      onReorderItem: _onReorder,
      itemCount: list.length,
      itemBuilder: (context, i) {
        final c = list[i];
        final color = _parseColor(c.color);
        return _ReorderTile(
          key: ValueKey(c.id),
          index: i,
          category: c,
          color: color,
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Widgets internos
// ═══════════════════════════════════════════════════════════════

/// Tile compacto para el modo reorder: icono de carpeta, nombre,
/// count, y drag handle (≡) a la derecha.
class _ReorderTile extends StatelessWidget {
  const _ReorderTile({
    super.key,
    required this.index,
    required this.category,
    required this.color,
  });

  final int index;
  final Category category;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: TerminalTheme.panelOf(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: TerminalTheme.lineOf(context)),
        ),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          // Marcador cuadrado del color de la categoría, como en el grid.
          leading: Container(
            width: 14,
            height: 14,
            color: color,
          ),
          title: Text(
            category.name,
            style: TextStyle(
              fontFamily: TerminalTheme.monoFamily,
              fontWeight: FontWeight.w700,
              color: TerminalTheme.fgOf(context),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${category.taskCount} tareas',
            style: TextStyle(
              fontFamily: TerminalTheme.monoFamily,
              fontSize: 12,
              color: TerminalTheme.mutedOf(context),
            ),
          ),
          trailing: ReorderableDragStartListener(
            index: index,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                Icons.drag_handle,
                color: TerminalTheme.mutedOf(context),
              ),
            ),
          ),
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
              // Salida de consola vacía: prompt + mensaje.
              Text(
                '> sin categorías todavía',
                style: TextStyle(
                  fontFamily: TerminalTheme.pixelFamily,
                  fontSize: 18,
                  color: TerminalTheme.mutedOf(context),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Tocá el botón + para crear la primera',
                style: TextStyle(
                  fontFamily: TerminalTheme.monoFamily,
                  fontSize: 13,
                  color: TerminalTheme.mutedOf(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
