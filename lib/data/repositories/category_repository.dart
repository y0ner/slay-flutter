import 'dart:async';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/router/app_router.dart';
import '../local/app_database.dart';
import '../models/category.dart';
import '../sync/sync_service.dart';

class CategoryRepository {
  CategoryRepository(this._client, {this.syncService, this.db});
  final SupabaseClient _client;
  final SyncService? syncService;
  final AppDatabase? db;

  /// Stream reactivo con suscripción realtime a la tabla categories.
  Stream<List<Category>> watchCategories() {
    final controller = StreamController<List<Category>>.broadcast();
    _refresh(controller);

    final channel = _client
        .channel('public:categories')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'categories',
          callback: (_) => _refresh(controller),
        )
        .subscribe();

    controller.onCancel = () async {
      await _client.removeChannel(channel);
      await controller.close();
    };
    return controller.stream;
  }

  Future<void> _refresh(StreamController<List<Category>> controller) async {
    try {
      final list = await getAll();
      if (!controller.isClosed) controller.add(list);
      await _hydrateCache(list);
    } catch (e) {
      if (!controller.isClosed) controller.addError(e);
    }
  }

  /// Idem al de TaskRepository — reemplaza cache local con la lista
  /// recién traída, conservando las filas con `isLocal = true`.
  Future<void> _hydrateCache(List<Category> categories) async {
    if (db == null) return;
    final serverIds = categories.map((c) => c.id).toSet();
    final existing = await db!.allCachedCategories();
    for (final row in existing) {
      if (!row.isLocal && !serverIds.contains(row.id)) {
        await db!.deleteCachedCategory(row.id);
      }
    }
    final companions = <CachedCategoriesCompanion>[];
    for (final c in categories) {
      final localRow = existing.firstWhere(
        (r) => r.id == c.id,
        orElse: () => CachedCategory(
          id: c.id,
          name: '',
          color: '',
          sortOrder: 0,
          taskCount: 0,
          isLocal: false,
          updatedAt: DateTime.now(),
        ),
      );
      companions.add(CachedCategoriesCompanion.insert(
        id: c.id,
        name: c.name,
        color: c.color,
        sortOrder: Value(c.sortOrder),
        taskCount: Value(c.taskCount),
        isLocal: Value(localRow.isLocal),
        updatedAt: DateTime.now(),
      ));
    }
    if (companions.isNotEmpty) {
      await db!.upsertManyCategories(companions);
    }
  }

  /// Inserta (o reemplaza) una categoría en el cache local con
  /// `isLocal = true` — usada para feedback inmediato al crear offline.
  Future<void> upsertLocal(Category category) async {
    if (db == null) return;
    await db!.upsertCategory(CachedCategoriesCompanion.insert(
      id: category.id,
      name: category.name,
      color: category.color,
      sortOrder: Value(category.sortOrder),
      taskCount: const Value(0),
      isLocal: const Value(true),
      updatedAt: DateTime.now(),
    ));
  }

  Future<List<Category>> getAll() async {
    final res = await _client
        .from('categories')
        .select('*, tasks:tasks(count)')
        .order('sort_order');
    return (res as List).map((e) {
      final tasksList = e['tasks'] as List?;
      return Category.fromJson({
        ...Map<String, dynamic>.from(e),
        'task_count': (tasksList != null && tasksList.isNotEmpty)
            ? (tasksList[0]['count'] ?? 0)
            : 0,
      });
    }).toList();
  }

  Future<Category> create({required String name, required String color, int sortOrder = 0}) async {
    final payload = {'name': name, 'color': color, 'sort_order': sortOrder};
    try {
      final res = await _client.from('categories').insert(payload).select().single();
      return Category.fromJson(Map<String, dynamic>.from(res));
    } catch (e) {
      if (_isNetwork(e)) {
        await syncService?.enqueue(
          op: 'create',
          tableName: 'categories',
          payload: payload,
        );
        return Category(
          id: 'local_${DateTime.now().microsecondsSinceEpoch}',
          name: name,
          color: color,
          sortOrder: sortOrder,
        );
      }
      rethrow;
    }
  }

  Future<void> update(String id, {String? name, String? color}) async {
    final patch = <String, dynamic>{};
    if (name != null) patch['name'] = name;
    if (color != null) patch['color'] = color;
    if (patch.isEmpty) return;
    try {
      await _client.from('categories').update(patch).eq('id', id);
    } catch (e) {
      if (_isNetwork(e)) {
        await syncService?.enqueue(
          op: 'update',
          tableName: 'categories',
          payload: {'id': id, ...patch},
        );
        return;
      }
      rethrow;
    }
  }

  Future<void> delete(String id) async {
    try {
      await _client.from('categories').delete().eq('id', id);
    } catch (e) {
      if (_isNetwork(e)) {
        await syncService?.enqueue(
          op: 'delete',
          tableName: 'categories',
          payload: {'id': id},
        );
        return;
      }
      rethrow;
    }
  }

  Future<void> reorder(List<Category> ordered) async {
    for (var i = 0; i < ordered.length; i++) {
      await _client
          .from('categories')
          .update({'sort_order': i}).eq('id', ordered[i].id);
    }
  }

  bool _isNetwork(Object e) => SyncService.isNetworkError(e);
}

final categoryRepositoryProvider = Provider<CategoryRepository>((ref) {
  return CategoryRepository(
    ref.watch(supabaseClientProvider),
    syncService: ref.watch(syncServiceProvider),
    db: ref.watch(appDatabaseProvider),
  );
});

/// Stream reactivo de categorías — también sincroniza entre dispositivos.
final categoriesStreamProvider = StreamProvider<List<Category>>((ref) {
  return ref.watch(categoryRepositoryProvider).watchCategories();
});

/// Stream reactivo de categorías desde la cache local (Drift).
/// Fallback cuando Supabase falla: la UI sigue mostrando la última
/// lista conocida.
final cachedCategoriesStreamProvider = StreamProvider<List<Category>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.watchCachedCategories().map((rows) {
    return rows.map((row) {
      return Category(
        id: row.id,
        name: row.name,
        color: row.color,
        sortOrder: row.sortOrder,
        taskCount: row.taskCount,
      );
    }).toList();
  });
});
