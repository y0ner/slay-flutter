import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

/// Tabla de operaciones pendientes. Cada vez que una operación contra
/// Supabase falla por red, la encolamos acá para reintentarla al
/// reconectarse.
class PendingOps extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get op => text()();
  TextColumn get targetTable => text()();
  TextColumn get payload => text()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
}

/// Mirror local de categorías para que la UI pueda mostrar datos
/// aún sin internet. Se hidrata desde el stream de Supabase.
/// `isLocal = true` indica que la fila todavía no se subió a Supabase
/// (queda en `pending_ops`).
class CachedCategories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get color => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get taskCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get isLocal => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Mirror local de tareas. `isLocal = true` indica que la fila todavía
/// no se subió a Supabase (se subió está en pending_ops).
class CachedTasks extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get status => text()();
  TextColumn get categoryId => text().nullable()();
  DateTimeColumn get date => dateTime().nullable()();
  DateTimeColumn get reminder => dateTime().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get subtaskCount => integer().withDefault(const Constant(0))();
  BoolColumn get isLocal => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [PendingOps, CachedCategories, CachedTasks])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        // Fase 0: agregamos `isLocal` a `CachedCategories`. Como la app
        // todavía no hidrata el cache de forma estable, lo más simple es
        // borrar todo y recrear las tablas con el schema nuevo.
        onUpgrade: (m, from, to) async {
          await m.deleteTable('pending_ops');
          await m.deleteTable('cached_categories');
          await m.deleteTable('cached_tasks');
          await m.createAll();
        },
        // Cold start (instalación nueva) — crear todo desde cero.
        onCreate: (m) async => m.createAll(),
      );

  // ── Pending ops ──────────────────────────────────────────

  Future<int> enqueueOp(PendingOpsCompanion op) =>
      into(pendingOps).insert(op);

  Future<List<PendingOp>> allPendingOps() =>
      (select(pendingOps)..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).get();

  Future<int> deleteOp(int id) =>
      (delete(pendingOps)..where((t) => t.id.equals(id))).go();

  Future<int> bumpAttempts(int id, String error) =>
      (update(pendingOps)..where((t) => t.id.equals(id))).write(
        PendingOpsCompanion(
          attempts: const Value.absent(),
          lastError: Value(error),
        ),
      )..toString();

  // ── Cached tasks ───────────────────────────────────────

  Future<List<CachedTask>> allCachedTasks() => select(cachedTasks).get();
  Stream<List<CachedTask>> watchCachedTasks() => select(cachedTasks).watch();
  Future<void> upsertTask(CachedTasksCompanion t) =>
      into(cachedTasks).insertOnConflictUpdate(t);
  Future<void> upsertManyTasks(List<CachedTasksCompanion> list) =>
      batch((b) => b.insertAllOnConflictUpdate(cachedTasks, list));
  Future<void> deleteCachedTask(String id) =>
      (delete(cachedTasks)..where((t) => t.id.equals(id))).go();
  Future<void> clearTasks() => delete(cachedTasks).go();

  /// Reemplaza la PK de un task cacheado (id local → id server).
  /// Como `id` es PK, hay que borrar y re-insertar.
  /// Si no existía la fila local, no hace nada.
  Future<void> renameCachedTaskId(String oldId, String newId) async {
    final existing =
        await (select(cachedTasks)..where((t) => t.id.equals(oldId))).getSingleOrNull();
    if (existing == null) return;
    await deleteCachedTask(oldId);
    await upsertTask(CachedTasksCompanion.insert(
      id: newId,
      title: existing.title,
      status: existing.status,
      categoryId: Value(existing.categoryId),
      date: Value(existing.date),
      reminder: Value(existing.reminder),
      sortOrder: Value(existing.sortOrder),
      subtaskCount: Value(existing.subtaskCount),
      isLocal: const Value(false),
      updatedAt: existing.updatedAt,
    ));
  }

  // ── Cached categories ──────────────────────────────────

  Future<List<CachedCategory>> allCachedCategories() =>
      select(cachedCategories).get();
  Stream<List<CachedCategory>> watchCachedCategories() =>
      select(cachedCategories).watch();
  Future<void> upsertCategory(CachedCategoriesCompanion c) =>
      into(cachedCategories).insertOnConflictUpdate(c);
  Future<void> upsertManyCategories(List<CachedCategoriesCompanion> list) =>
      batch((b) => b.insertAllOnConflictUpdate(cachedCategories, list));
  Future<void> deleteCachedCategory(String id) =>
      (delete(cachedCategories)..where((t) => t.id.equals(id))).go();
  Future<void> clearCategories() => delete(cachedCategories).go();

  /// Idem `renameCachedTaskId` para categorías.
  Future<void> renameCachedCategoryId(String oldId, String newId) async {
    final existing = await (select(cachedCategories)
          ..where((t) => t.id.equals(oldId)))
        .getSingleOrNull();
    if (existing == null) return;
    await deleteCachedCategory(oldId);
    await upsertCategory(CachedCategoriesCompanion.insert(
      id: newId,
      name: existing.name,
      color: existing.color,
      sortOrder: Value(existing.sortOrder),
      taskCount: Value(existing.taskCount),
      isLocal: const Value(false),
      updatedAt: existing.updatedAt,
    ));
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'slay.db'));
    return NativeDatabase.createInBackground(file);
  });
}

/// Provider global de la DB local. Se inicializa una sola vez.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
