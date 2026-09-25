import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:slay_flutter/core/router/app_router.dart';
import 'package:slay_flutter/core/state/logging_out_provider.dart';
import 'package:slay_flutter/features/auth/login_screen.dart';
import 'package:slay_flutter/features/home/home_shell.dart';
import 'package:slay_flutter/features/settings/settings_screen.dart';
import 'package:slay_flutter/widgets/logout_overlay.dart';
import 'package:slay_flutter/widgets/network_status_pill.dart';
import 'package:slay_flutter/data/sync/sync_service.dart';
import 'package:slay_flutter/data/sync/sync_state.dart';

void main() {
  testWidgets('Simulate exact app router logout flow with HomeShell', (tester) async {
    final authStreamCtrl = StreamController<AuthState>.broadcast();
    bool isLoggedIn = true;

    final router = GoRouter(
      initialLocation: '/settings',
      redirect: (context, state) {
        final loggingIn = state.matchedLocation == '/login';
        if (!isLoggedIn && !loggingIn) return '/login';
        if (isLoggedIn && loggingIn) return '/';
        return null;
      },
      routes: [
        GoRoute(
          path: '/login',
          builder: (_, __) => const LoginScreen(),
        ),
        ShellRoute(
          builder: (context, state, child) =>
              HomeShell(currentLocation: state.uri.path, child: child),
          routes: [
            GoRoute(
              path: '/settings',
              pageBuilder: (_, __) => const NoTransitionPage(child: SettingsScreen()),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateChangesProvider.overrideWith((ref) => authStreamCtrl.stream),
          syncStatusProvider.overrideWith((ref) => Stream.value(
            const SyncStatus(isOnline: true, state: SyncState.idle, pendingCount: 0),
          )),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            final loggingOut = ref.watch(loggingOutProvider);
            return MaterialApp.router(
              routerConfig: router,
              builder: (context, child) => Stack(
                children: [
                  child ?? const SizedBox.shrink(),
                  const Positioned(top: 0, left: 0, right: 0, child: NetworkStatusPill()),
                  if (loggingOut) const Positioned.fill(child: LogoutOverlay()),
                ],
              ),
            );
          },
        ),
      ),
    );

    await tester.pump();
    expect(find.text('Cerrar sesión'), findsOneWidget);

    // Tap Cerrar Sesión
    await tester.tap(find.text('Cerrar sesión'));
    await tester.pump();

    // Dialog appears: "¿Estás seguro?"
    expect(find.text('¿Estás seguro?'), findsOneWidget);
    expect(find.text('Salir'), findsOneWidget);

    // Tap Salir
    await tester.tap(find.text('Salir'));
    await tester.pump();

    // Simulate auth sign out & router redirect
    isLoggedIn = false;
    router.refresh();

    // Pump frames
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
