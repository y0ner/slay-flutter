import 'dart:async';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/router/app_router.dart';
import '../local/app_database.dart';
import '../models/category.dart' show TaskStatus;
import '../models/task.dart';
import '../sync/sync_service.dart';

/// Repositorio de tareas y subtareas. Encapsula todas las queries
/// a Supabase para que las pantallas no importen Supabase directamente.
///
/// **Modo offline**: si `syncService` está presente y una operación
/// contra Supabase falla por red (no por validación), la encolamos
/// para reintento automático. La excepción se sigue propagando
/// para que la UI muestre feedback al usuario.
class TaskRepository {
  TaskRepository(this._client, {this.syncService, this.db});
  final SupabaseClient _client;
  final SyncService? syncService;
  final AppDatabase? db;

  // ── Tareas ────────────────────────────────────────────────

  /// Stream reactivo que emite la lista actual de tareas del usuario
  /// cada vez que cambia algo en la tabla `tasks`.
  Stream<List<Task>> watchTasks() {
    final controller = StreamController<List<Task>>.broadcast();

    // 1) Emisión inicial
    _refresh(controller);

    // 2) Re-emitir cuando cambia la tabla
    final channel = _client
        .channel('public:tasks')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'tasks',
          callback: (_) => _refresh(controller),
        )
        .subscribe();

    controller.onCancel = () async {
      await _client.removeChannel(channel);
      await controller.close();
    };
    return controller.stream;
  }

  Future<void> _refresh(StreamController<List<Task>> controller) async {
    try {
      final list = await getAll();
      if (!controller.isClosed) controller.add(list);
      // Hidratar cache local para que la UI pueda arrancar sin red.
      await _hydrateCache(list);
    } catch (e) {
      if (!controller.isClosed) controller.addError(e);
    }
  }

  /// Reemplaza el contenido de `cached_tasks` con la lista recién
  /// traída de Supabase. No toca filas con `isLocal = true` (las
  /// pendientes de sincronizar); esas siguen en cache hasta que el
  /// `SyncService` las reconcilie.
  Future<void> _hydrateCache(List<Task> tasks) async {
    if (db == null) return;
    final serverIds = tasks.map((t) => t.id).toSet();
    final existing = await db!.allCachedTasks();
    // Borrar sólo filas que ya están sincronizadas (no locales) y
    // que NO aparecen en la lista nueva (fueron borradas en el server).
    for (final row in existing) {
      if (!row.isLocal && !serverIds.contains(row.id)) {
        await db!.deleteCachedTask(row.id);
      }
    }
    final companions = <CachedTasksCompanion>[];
    for (final t in tasks) {
      // Si ya hay una fila local con este id, conservamos isLocal;
      // sólo refrescamos datos del server.
      final localRow = existing.firstWhere(
        (r) => r.id == t.id,
        orElse: () => CachedTask(
          id: t.id,
          title: '',
          status: '',
          categoryId: null,
          date: null,
          reminder: null,
          sortOrder: 0,
          subtaskCount: 0,
          isLocal: false,
          updatedAt: DateTime.now(),
        ),
      );
      companions.add(CachedTasksCompanion.insert(
        id: t.id,
        title: t.title,
        status: t.status,
        categoryId: Value(t.categoryId),
        date: Value(t.date),
        reminder: Value(t.reminder),
        sortOrder: Value(t.sortOrder),
        subtaskCount: Value(t.subtaskCount),
        isLocal: Value(localRow.isLocal),
        updatedAt: DateTime.now(),
      ));
    }
    if (companions.isNotEmpty) {
      await db!.upsertManyTasks(companions);
    }
  }

  /// Inserta (o reemplaza) una tarea en el cache local. Usado por la UI
  /// cuando crea offline para feedback inmediato antes de que el
  /// `SyncService` reconcilie el id.
  Future<void> upsertLocal(Task task) async {
    if (db == null) return;
    await db!.upsertTask(CachedTasksCompanion.insert(
      id: task.id,
      title: task.title,
      status: task.status,
      categoryId: Value(task.categoryId),
      date: Value(task.date),
      reminder: Value(task.reminder),
      sortOrder: Value(task.sortOrder),
      subtaskCount: Value(task.subtaskCount),
      isLocal: const Value(true),
      updatedAt: DateTime.now(),
    ));
  }

  /// Devuelve todas las tareas del usuario actual, ordenadas.
  Future<List<Task>> getAll() async {
    final res = await _client
        .from('tasks')
        .select('*, subtasks:subtasks(count)')
        .order('sort_order');
    final list = res as List<dynamic>;
    return list
        .map((e) => Task.fromJson({
              ...Map<String, dynamic>.from(e),
              'subtask_count': (e['subtasks'] is List && (e['subtasks'] as List).isNotEmpty)
                  ? (e['subtasks'][0]['count'] ?? 0)
                  : 0,
            }))
        .toList();
  }

  /// Crea una tarea. Devuelve la fila insertada.
  /// Si falla por red y `syncService` está disponible, encola la op
  /// y devuelve un Task local con `isLocal = true` para feedback
  /// optimista en la UI.
  Future<Task> create({
    required String title,
    required String categoryId,
    int sortOrder = 0,
    DateTime? date,
    DateTime? reminder,
  }) async {
    final payload = <String, dynamic>{
      'title': title,
      'category_id': categoryId,
      'status': TaskStatus.pendiente,
      'date': (reminder ?? date)?.toIso8601String(),
      'reminder': reminder?.toIso8601String(),
      'sort_order': sortOrder,
    };
    try {
      final res = await _client.from('tasks').insert(payload).select().single();
      return Task.fromJson(Map<String, dynamic>.from(res));
    } catch (e) {
      if (_isNetwork(e)) {
        await syncService?.enqueue(
          op: 'create',
          tableName: 'tasks',
          payload: payload,
        );
        final localId = 'local_${DateTime.now().microsecondsSinceEpoch}';
        return Task(
          id: localId,
          title: title,
          status: TaskStatus.pendiente,
          date: date,
          categoryId: categoryId,
          sortOrder: sortOrder,
          reminder: reminder,
          isLocal: true,
        );
      }
      rethrow;
    }
  }

  /// Cambia el estado pendiente/completado.
  Future<void> toggleComplete(String taskId, bool complete) async {
    final payload = {
      'status': complete ? TaskStatus.completado : TaskStatus.pendiente,
    };
    try {
      await _client.from('tasks').update(payload).eq('id', taskId);
    } catch (e) {
      if (_isNetwork(e)) {
        await syncService?.enqueue(
          op: 'update',
          tableName: 'tasks',
          payload: {'id': taskId, ...payload},
        );
        return;
      }
      rethrow;
    }
  }

  /// Edita título y recordatorio.
  Future<void> update(String taskId, {String? title, DateTime? reminder}) async {
    final patch = <String, dynamic>{};
    if (title != null) patch['title'] = title;
    if (reminder != null) patch['reminder'] = reminder.toIso8601String();
    if (patch.isEmpty) return;
    try {
      await _client.from('tasks').update(patch).eq('id', taskId);
    } catch (e) {
      if (_isNetwork(e)) {
        await syncService?.enqueue(
          op: 'update',
          tableName: 'tasks',
          payload: {'id': taskId, ...patch},
        );
        return;
      }
      rethrow;
    }
  }

  /// Elimina una tarea (y sus subtareas vía cascade).
  Future<void> delete(String taskId) async {
    try {
      await _client.from('tasks').delete().eq('id', taskId);
    } catch (e) {
      if (_isNetwork(e)) {
        await syncService?.enqueue(
          op: 'delete',
          tableName: 'tasks',
          payload: {'id': taskId},
        );
        return;
      }
      rethrow;
    }
  }

  /// Reordena en bloque (recibe una lista ya ordenada).
  Future<void> reorder(List<Task> ordered) async {
    for (var i = 0; i < ordered.length; i++) {
      await _client
          .from('tasks')
          .update({'sort_order': i}).eq('id', ordered[i].id);
    }
  }

  // ── Subtasks ──────────────────────────────────────────────

  /// Stream de subtareas de una tarea, con suscripción a cambios.
  Stream<List<SubTask>> watchSubtasks(String taskId) {
    final controller = StreamController<List<SubTask>>.broadcast();
    _refreshSubs(controller, taskId);

    final channel = _client
        .channel('public:subtasks:$taskId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'subtasks',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'task_id',
            value: taskId,
          ),
          callback: (_) => _refreshSubs(controller, taskId),
        )
        .subscribe();

    controller.onCancel = () async {
      await _client.removeChannel(channel);
      await controller.close();
    };
    return controller.stream;
  }

  Future<void> _refreshSubs(
      StreamController<List<SubTask>> controller, String taskId) async {
    try {
      final list = await getSubtasks(taskId);
      if (!controller.isClosed) controller.add(list);
    } catch (e) {
      if (!controller.isClosed) controller.addError(e);
    }
  }

  Future<List<SubTask>> getSubtasks(String taskId) async {
    final res = await _client
        .from('subtasks')
        .select()
        .eq('task_id', taskId)
        .order('sort_order');
    return (res as List).map((e) => SubTask.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<SubTask> createSubtask({
    required String taskId,
    required String title,
    int sortOrder = 0,
    DateTime? reminder,
  }) async {
    final res = await _client.from('subtasks').insert({
      'task_id': taskId,
      'title': title,
      'status': TaskStatus.pendiente,
      'sort_order': sortOrder,
      'reminder': reminder?.toIso8601String(),
    }).select().single();
    return SubTask.fromJson(Map<String, dynamic>.from(res));
  }

  Future<void> toggleSubtaskComplete(String id, bool complete) async {
    await _client.from('subtasks').update({
      'status': complete ? TaskStatus.completado : TaskStatus.pendiente,
    }).eq('id', id);
  }

  Future<void> updateSubtask(String id, {String? title, DateTime? reminder}) async {
    final patch = <String, dynamic>{};
    if (title != null) patch['title'] = title;
    if (reminder != null) patch['reminder'] = reminder.toIso8601String();
    if (patch.isEmpty) return;
    await _client.from('subtasks').update(patch).eq('id', id);
  }

  Future<void> deleteSubtask(String id) async {
    await _client.from('subtasks').delete().eq('id', id);
  }

  // ── Helpers ───────────────────────────────────────────────

  bool _isNetwork(Object e) => SyncService.isNetworkError(e);
}

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  return TaskRepository(
    ref.watch(supabaseClientProvider),
    syncService: ref.watch(syncServiceProvider),
    db: ref.watch(appDatabaseProvider),
  );
});

/// Stream reactivo de tareas — la app se entera al instante de cualquier
/// cambio hecho desde otro dispositivo (phone, desktop, web).
final tasksStreamProvider = StreamProvider<List<Task>>((ref) {
  return ref.watch(taskRepositoryProvider).watchTasks();
});

/// Stream reactivo de tareas desde la cache local (Drift).
///
/// Se usa como fallback cuando `tasksStreamProvider` falla por red: la
/// UI sigue mostrando la última lista conocida y los items offline-only
/// (los recién creados mientras no había internet).
final cachedTasksStreamProvider = StreamProvider<List<Task>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.watchCachedTasks().map((rows) {
    return rows.map((row) {
      return Task(
        id: row.id,
        title: row.title,
        status: row.status,
        categoryId: row.categoryId,
        date: row.date,
        reminder: row.reminder,
        sortOrder: row.sortOrder,
        subtaskCount: row.subtaskCount,
        isLocal: row.isLocal,
      );
    }).toList();
  });
});
