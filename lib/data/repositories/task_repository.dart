import 'dart:async';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/router/app_router.dart';
import '../../core/supabase/supabase_retry.dart';
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

  Future<List<Task>> _getCached() async {
    if (db == null) return [];
    try {
      final rows = await db!.allCachedTasks();
      return rows.map((r) => Task(
        id: r.id,
        title: r.title,
        status: r.status,
        categoryId: r.categoryId,
        date: r.date,
        reminder: r.reminder,
        sortOrder: r.sortOrder,
        subtaskCount: r.subtaskCount,
        isLocal: r.isLocal,
      )).toList();
    } catch (_) {
      return [];
    }
  }

  // ── Tareas ────────────────────────────────────────────────

  /// Stream reactivo que emite la lista actual de tareas del usuario
  /// cada vez que cambia algo en la tabla `tasks`.
  Stream<List<Task>> watchTasks() {
    final controller = StreamController<List<Task>>.broadcast();

    // Emisión inmediata de cache local si existe (offline-first / carga instantánea).
    _getCached().then((cached) {
      if (cached.isNotEmpty && !controller.isClosed) {
        controller.add(cached);
      }
    });

    // 1) Emisión y sync inicial
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
      final cached = await _getCached();
      if (cached.isNotEmpty) {
        if (!controller.isClosed) controller.add(cached);
      } else {
        if (!controller.isClosed) controller.addError(e);
      }
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
    return retrySupabaseOperation(() async {
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
    });
  }

  /// Crea una tarea. Devuelve la fila insertada.
  /// Si falla por red y `syncService` está disponible, encola la op
  /// y devuelve un Task local con `isLocal = true` para feedback
  /// optimista en la UI.
  /// [categoryId] es OPCIONAL: null/'' crea una tarea "Sin categoría".
  Future<Task> create({
    required String title,
    String? categoryId,
    int sortOrder = 0,
    DateTime? date,
    DateTime? reminder,
  }) async {
    final catId =
        (categoryId == null || categoryId.isEmpty) ? null : categoryId;
    final payload = <String, dynamic>{
      'title': title,
      'status': TaskStatus.pendiente,
      'date': (reminder ?? date)?.toIso8601String(),
      'reminder': reminder?.toIso8601String(),
      'sort_order': sortOrder,
    };
    if (catId != null) payload['category_id'] = catId;
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
          categoryId: catId,
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

  /// Wrapper único para la UI: (des)completa aplicando la política de
  /// auto-movimiento correspondiente.
  ///
  /// - complete=true  → la tarea va al fondo (ver [sortOrderAfterCheck]).
  /// - complete=false → vuelve al final del bloque pendiente
  ///   (ver [sortOrderAfterUncheck]).
  ///
  /// [allTasks] debe ser la lista GLOBAL del usuario (ver funciones
  /// puras más abajo). Si la lista viene vacía (stream no cargado)
  /// igual (des)completa, sólo no mueve.
  Future<void> toggleWithReorder(
      String taskId, bool complete, List<Task> allTasks) async {
    if (complete) {
      await checkWithReorder(taskId, allTasks);
    } else {
      await uncheckWithReorder(taskId, allTasks);
    }
  }

  /// Actualiza sólo el `sort_order` de una tarea (con soporte offline).
  Future<void> _updateSortOrder(String taskId, int sortOrder) async {
    try {
      await _client
          .from('tasks')
          .update({'sort_order': sortOrder}).eq('id', taskId);
    } catch (e) {
      if (_isNetwork(e)) {
        await syncService?.enqueue(
          op: 'update',
          tableName: 'tasks',
          payload: {'id': taskId, 'sort_order': sortOrder},
        );
        return;
      }
      rethrow;
    }
  }

  /// Completa [taskId] Y la mueve al final del orden (sortOrder = máximo
  /// de [allTasks] + 1).
  ///
  /// Por qué: con listas largas (100+ tareas), si las completadas
  /// conservan su posición el usuario tiene que deslizar mucho para
  /// encontrar lo que falta. Al chuletear, la tarea cede su puesto y
  /// lo pendiente queda siempre arriba.
  ///
  /// Devuelve true si además de completar se movió.
  Future<bool> checkWithReorder(String taskId, List<Task> allTasks) async {
    await toggleComplete(taskId, true);
    final matches = allTasks.where((t) => t.id == taskId);
    if (matches.isEmpty) return false;
    final target = sortOrderAfterCheck(allTasks, matches.first);
    if (target == null) return false; // ya era la última: nada que mover
    await _updateSortOrder(taskId, target);
    return true;
  }

  /// Descompleta [taskId] Y la devuelve al final del bloque de tareas
  /// pendientes (con el sortOrder de la última pendiente), para que no
  /// quede perdida entre las completadas del fondo.
  ///
  /// Si la tarea ya estaba dentro del bloque de pendientes NO se
  /// mueve: se respeta la posición que le dio el usuario con drag.
  ///
  /// Devuelve true si además de descompletar se movió.
  Future<bool> uncheckWithReorder(String taskId, List<Task> allTasks) async {
    await toggleComplete(taskId, false);
    final matches = allTasks.where((t) => t.id == taskId);
    if (matches.isEmpty) return false;
    final target = sortOrderAfterUncheck(allTasks, matches.first);
    if (target == null) return false; // ya está entre pendientes
    await _updateSortOrder(taskId, target);
    return true;
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
  ///
  /// Renumera `sortOrder = 0..N-1` y dispara las updates en paralelo.
  /// El consumidor debe armar la lista en el orden final deseado
  /// (después de un drag-and-drop del usuario).
  ///
  /// Optimistic UI: invalida `tasksStreamProvider` para que la UI
  /// re-emita con el nuevo orden. Si Supabase rechaza, la excepción
  /// se propaga y la UI debería revertir + mostrar snackbar.
  ///
  /// NOTA: los callers pasan la lista YA renumerada
  /// (`copyWith(sortOrder: i)`), así que NO se puede "saltear" updates
  /// comparando `task.sortOrder == i` — esa comparación es siempre
  /// verdadera por construcción y volvía al método entero un no-op:
  /// el drag no persistía nada y al recargar el stream las tareas
  /// volvían a su orden original.
  Future<void> reorder(List<Task> ordered) async {
    if (ordered.isEmpty) return;
    await Future.wait([
      for (var i = 0; i < ordered.length; i++)
        _client
            .from('tasks')
            .update({'sort_order': i}).eq('id', ordered[i].id),
    ]);
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
    return retrySupabaseOperation(() async {
      final res = await _client
          .from('subtasks')
          .select()
          .eq('task_id', taskId)
          .order('sort_order');
      return (res as List).map((e) => SubTask.fromJson(Map<String, dynamic>.from(e))).toList();
    });
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

// ═══════════════════════════════════════════════════════════════
// Política de orden al (des)completar — funciones puras, testeables
// sin Supabase.
// ═══════════════════════════════════════════════════════════════

/// Posición (sortOrder) que debe recibir [task] al ser COMPLETADA:
/// al fondo de todo (máximo + 1). Devuelve null si ya está al fondo
/// (nada que mover).
///
/// [allTasks] debe ser la lista GLOBAL del usuario (todas las
/// categorías), no un subconjunto filtrado — así "al fondo" es
/// realmente el fondo y no chocamos con tareas fuera del filtro.
int? sortOrderAfterCheck(List<Task> allTasks, Task task) {
  final maxSort =
      allTasks.fold<int>(0, (m, t) => t.sortOrder > m ? t.sortOrder : m);
  if (task.sortOrder >= maxSort) return null;
  return maxSort + 1;
}

/// Posición (sortOrder) que debe recibir [task] al DESCOMPLETAR:
/// la de la última tarea pendiente (queda al final del bloque
/// pendiente). Devuelve null si no hay pendientes o si la tarea ya
/// está dentro del bloque pendiente (su sortOrder no supera el
/// anchor), respetando el orden que dio el usuario con drag.
int? sortOrderAfterUncheck(List<Task> allTasks, Task task) {
  final pending = allTasks
      .where((t) => !t.isCompleted && t.id != task.id)
      .toList()
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  if (pending.isEmpty) return null;
  final anchor = pending.last.sortOrder;
  if (task.sortOrder <= anchor) return null;
  return anchor;
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
