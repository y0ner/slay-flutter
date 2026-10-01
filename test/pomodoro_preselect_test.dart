/// Regresión del preselect "Enviar a foco" (⏱ en una tarjeta →
/// `/pomodoro?task=<id>` debe abrir el wizard con la tarea elegida).
///
/// Bug: `_pickTaskById` usaba `getAll()` (red directa a Supabase). Si
/// la llamada fallaba (PGRST303 al arrancar, sin conexión, proyecto
/// pausado), el error moría en silencio y la pantalla de Foco quedaba
/// en "elegir tarea" sin preseleccionar nada — mientras las listas de
/// tareas seguían mostrando datos porque usan el cache local.
///
/// Fix: `TaskRepository.getById` es offline-first (cache local
/// primero, red después, nunca lanza). Y el id ahora viaja por
/// `pendingFocusTaskProvider` (señal Riverpod) en vez de query param.
///
/// Nota: se usa un stub de `AppDatabase` (override de
/// `allCachedTasks`) porque `NativeDatabase` necesita libsqlite3 en
/// el host y el entorno de test no la tiene.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:slay_flutter/data/local/app_database.dart';
import 'package:slay_flutter/data/repositories/task_repository.dart';
import 'package:slay_flutter/features/pomodoro/focus_controller.dart';
import 'package:slay_flutter/features/pomodoro/pomodoro_screen.dart';

/// Cliente apuntando a un puerto cerrado: cualquier llamada de red
/// falla al instante (connection refused), simulando Supabase caído.
///
/// Se construye en `setUpAll` (fuera de la zona fake_async de cada
/// `testWidgets`) porque GoTrueClient crea un timer periódico de
/// auto-refresh que_flutter_test marcaría como timer pendiente al
/// terminar el test.
late final SupabaseClient _deadClient;

/// DB "en memoria" sin SQLite real: sólo sirve `allCachedTasks` desde
/// [rows]; ninguna query toca el executor (drift abre la conexión de
/// forma lazy y acá nunca se consulta de verdad).
class _StubDb extends AppDatabase {
  _StubDb() : super.forTesting(NativeDatabase.memory());

  List<CachedTask> rows = const [];

  @override
  Future<List<CachedTask>> allCachedTasks() async => rows;
}

CachedTask _row({
  String id = 't1',
  String title = 'Preselect',
  String status = 'Pendiente',
}) =>
    CachedTask(
      id: id,
      title: title,
      status: status,
      categoryId: null,
      date: DateTime(2026, 9, 30),
      reminder: null,
      sortOrder: 0,
      subtaskCount: 0,
      isLocal: false,
      updatedAt: DateTime(2026, 9, 30),
    );

void main() {
  setUpAll(() {
    // focusRunProvider hidrata desde SharedPreferences al primer read.
    SharedPreferences.setMockInitialValues({});
    // Silencia el warning de drift por crear varias AppDatabase de test.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    _deadClient = SupabaseClient('http://127.0.0.1:1', 'test-anon-key');
    // El constructor arranca un auto-refresh periódico del token;
    // no lo necesitamos y evita timers colgando.
    try {
      _deadClient.auth.stopAutoRefresh();
    } catch (_) {/* best-effort */}
  });

  test('getById: cache-first encuentra la tarea sin red', () async {
    final db = _StubDb()..rows = [_row()];
    final repo = TaskRepository(_deadClient, db: db);

    final t = await repo.getById('t1');

    expect(t, isNotNull);
    expect(t!.title, 'Preselect');
    expect(t.isCompleted, isFalse);
  });

  test('getById: nunca lanza aunque la red esté caída', () async {
    final db = _StubDb(); // cache vacío → probaría la red (caída)
    final repo = TaskRepository(_deadClient, db: db);

    final t = await repo.getById('no-existe');

    expect(t, isNull);
  });

  testWidgets('⏱ en una tarea abre el wizard con la tarea ya elegida',
      (tester) async {
    final db = _StubDb()..rows = [_row(id: 'task-x', title: 'Escribir informe')];
    final repo = TaskRepository(_deadClient, db: db);
    final container = ProviderContainer(overrides: [
      taskRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PomodoroScreen()),
      ),
    );
    await tester.pump();

    // Sin señal pendiente → pantalla de elegir tarea.
    expect(find.text('Elegir tarea'), findsOneWidget);

    // ⏱: la tarjeta escribe la señal y navega a /pomodoro (URL
    // limpia). La pantalla (ya viva) consume la señal por ref.listen.
    container.read(pendingFocusTaskProvider.notifier).state = 'task-x';
    await tester.pump();
    await tester.pumpAndSettle();

    // La señal se consume (un solo uso)...
    expect(container.read(pendingFocusTaskProvider), isNull);
    // ...y el wizard muestra el título de la tarea preseleccionada.
    expect(find.text('Escribir informe'), findsWidgets);
  });

  testWidgets('señal escrita ANTES de montar la pantalla también funciona',
      (tester) async {
    final db = _StubDb()..rows = [_row(id: 'task-y', title: 'Diseñar logo')];
    final repo = TaskRepository(_deadClient, db: db);
    final container = ProviderContainer(overrides: [
      taskRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);

    // La tarjeta escribe la señal ANTES de navegar: la pantalla no
    // existe todavía, así que la consume el initState (postFrame).
    container.read(pendingFocusTaskProvider.notifier).state = 'task-y';

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PomodoroScreen()),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(container.read(pendingFocusTaskProvider), isNull);
    expect(find.text('Diseñar logo'), findsWidgets);
  });
}
