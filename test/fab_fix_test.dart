/// Test de regresión para el fix del FAB v2.
///
/// Verifica que el FAB del shell muestra el icon correcto
/// (Icons.add, no folder+) cuando estamos en /tasks/:categoryId
/// después de un context.push.
///
/// Para que el FAB reciba la location correcta, el ShellRoute.builder
/// debe pasar `state.uri.path` (NO `state.matchedLocation`, que se
/// queda stale con push — ver bug documentado en fab_diag_test.dart).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets(
    'FAB muestra icon add tras context.push a /tasks/:id',
    (tester) async {
      final router = GoRouter(
        initialLocation: '/tasks',
        routes: [
          ShellRoute(
            builder: (context, state, child) {
              // ← FIX: usamos state.uri.path en vez de state.matchedLocation
              return _TestShell(
                currentLocation: state.uri.path,
                child: child,
              );
            },
            routes: [
              GoRoute(
                path: '/',
                builder: (_, __) => const Text('home'),
              ),
              GoRoute(
                path: '/tasks',
                builder: (_, __) => Builder(builder: (innerCtx) {
                  return Column(
                    children: [
                      const Text('categories'),
                      ElevatedButton(
                        onPressed: () =>
                            innerCtx.push('/tasks/personal-uuid'),
                        child: const Text('go-personal'),
                      ),
                    ],
                  );
                }),
              ),
              GoRoute(
                path: '/tasks/:categoryId',
                builder: (_, state) =>
                    Text('tasks-${state.pathParameters['categoryId']}'),
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      // Inicialmente estamos en /tasks → FAB = folder+ icon.
      expect(find.byIcon(Icons.create_new_folder_outlined), findsOneWidget);

      // Push a /tasks/personal-uuid.
      await tester.tap(find.text('go-personal'));
      await tester.pumpAndSettle();

      // Tras el push, el FAB debe haber cambiado a Icons.add.
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.byIcon(Icons.create_new_folder_outlined), findsNothing);
      // Y la pantalla visible es la de tareas de la categoría.
      expect(find.text('tasks-personal-uuid'), findsOneWidget);
    },
  );
}

class _TestShell extends StatelessWidget {
  const _TestShell({required this.currentLocation, required this.child});
  final String currentLocation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final IconData fabIcon;
    if (currentLocation == '/tasks') {
      fabIcon = Icons.create_new_folder_outlined;
    } else if (currentLocation.startsWith('/tasks/')) {
      fabIcon = Icons.add;
    } else {
      fabIcon = Icons.help;
    }
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab-fix-test',
        onPressed: () {},
        child: Icon(fabIcon),
      ),
      body: child,
    );
  }
}
