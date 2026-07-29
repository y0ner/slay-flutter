/// Diagnóstico del bug ShellRoute + push (documentación).
///
/// Imprime las propiedades del state que recibe el ShellRoute
/// en cada rebuild. Confirma que `state.matchedLocation` queda
/// STALE con `context.push` mientras que `state.uri.path` SÍ se
/// actualiza correctamente.
///
/// Output esperado:
///   [TEST] ShellRoute: matchedLocation="/tasks" fullPath="/tasks" uri="/tasks" pathParams={}
///   ====== TAP PUSH ======
///   [TEST] ShellRoute: matchedLocation="/tasks" fullPath="/tasks/:categoryId" uri="/tasks/personal-uuid" pathParams={categoryId: personal-uuid}
///
/// Ver: `fab_fix_test.dart` (regression test que valida el fix).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets(
    'Diagnóstico: qué state recibe el ShellRoute tras push',
    (tester) async {
      final router = GoRouter(
        initialLocation: '/tasks',
        routes: [
          ShellRoute(
            builder: (context, state, child) {
              // ignore: avoid_print
              print('[TEST] ShellRoute: '
                  'matchedLocation="${state.matchedLocation}" '
                  'fullPath="${state.fullPath}" '
                  'uri="${state.uri}" '
                  'pathParams=${{...state.pathParameters}}');
              return _TestShell(
                currentLocation: state.matchedLocation,
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
                        child: const Text('go-personal-push'),
                      ),
                    ],
                  );
                }),
              ),
              GoRoute(
                path: '/tasks/:categoryId',
                builder: (_, state) => Column(
                  children: [
                    Text('tasks-${state.pathParameters['categoryId']}'),
                  ],
                ),
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      // ignore: avoid_print
      print('====== TAP PUSH ======');
      await tester.tap(find.text('go-personal-push'));
      await tester.pumpAndSettle();
    },
  );
}

class _TestShell extends StatelessWidget {
  const _TestShell({required this.currentLocation, required this.child});
  final String currentLocation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Leemos directamente del routerDelegate la URI actual
    final router = GoRouter.of(context);
    final actualUri = router.routeInformationProvider.value.uri.path;
    return Scaffold(
      body: Column(
        children: [
          Container(
            color: Colors.amber,
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                Text('shell.currentLocation="$currentLocation"'),
                Text('router.uri="$actualUri"'),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
