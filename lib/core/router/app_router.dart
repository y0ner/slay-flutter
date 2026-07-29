import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/about/about_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/calendar/calendar_screen.dart';
import '../../features/home/home_shell.dart';
import '../../features/my_day/my_day_screen.dart';
import '../../features/pomodoro/pomodoro_screen.dart';
import '../../features/settings/completed_tasks_screen.dart';
import '../../features/settings/manage_categories_sheet.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/subtasks/subtask_list_screen.dart';
import '../../features/tasks/category_list_screen.dart';
import '../../features/tasks/task_list_screen.dart';

/// Proveedor del cliente de Supabase (es un singleton provisto por el paquete,
/// pero lo envolvemos para que los consumers no importen directamente).
final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

/// Stream de cambios de sesión. Se reconstruye el router ante cambios.
final authStateChangesProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(supabaseClientProvider).auth.onAuthStateChange,
);

/// Usuario actual (o null si no hay sesión).
final currentUserProvider = Provider<User?>((ref) {
  ref.watch(authStateChangesProvider);
  return ref.watch(supabaseClientProvider).auth.currentUser;
});

/// Estado de auth simplificado para guards.
final isAuthenticatedProvider = Provider<bool>(
  (ref) => ref.watch(currentUserProvider) != null,
);

/// Router de la aplicación. Redirige a /login si no hay sesión.
final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(supabaseClientProvider).auth;

  return GoRouter(
    initialLocation: '/',
    refreshListenable: _AuthListenable(ref),
    redirect: (context, state) {
      final session = auth.currentSession;
      final loggingIn = state.matchedLocation == '/login';
      if (session == null && !loggingIn) return '/login';
      if (session != null && loggingIn) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),

      // ── Shell con BottomNavigationBar ───────────────────
      ShellRoute(
        builder: (context, state, child) =>
            // FIX bug FAB v2: `state.matchedLocation` queda STALE
            // (devuelve el path del padre sin el parámetro) cuando se
            // navega con `context.push` a una sub-ruta del shell. Eso
            // hacía que el FAB en /tasks/:id evaluara `currentLocation
            // == '/tasks'` (igual al padre) y abriera el editor de
            // categorías en vez de QuickAddDialog.
            //
            // `state.uri.path` y `state.fullPath` SÍ se actualizan
            // correctamente con push (test `fab_diag_test.dart` lo
            // confirma). Usamos `state.uri.path` porque es la URI
            // completa normalizada de la ruta activa.
            HomeShell(currentLocation: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (_, __) => const NoTransitionPage(child: MyDayScreen()),
          ),
          GoRoute(
            path: '/tasks',
            pageBuilder: (_, __) => const NoTransitionPage(child: CategoryListScreen()),
          ),
          GoRoute(
            path: '/tasks/:categoryId',
            builder: (_, state) => TaskListScreen(
              categoryId: state.pathParameters['categoryId']!,
            ),
          ),
          GoRoute(
            path: '/pomodoro',
            pageBuilder: (_, __) => const NoTransitionPage(child: PomodoroScreen()),
          ),
          GoRoute(
            path: '/calendar',
            pageBuilder: (_, __) => const NoTransitionPage(child: CalendarScreen()),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (_, __) => const NoTransitionPage(child: SettingsScreen()),
          ),
        ],
      ),

      // ── Pantallas modales (fuera del shell) ────────────
      GoRoute(
        path: '/subtasks/:taskId',
        builder: (_, state) => SubTaskListScreen(
          taskId: state.pathParameters['taskId']!,
        ),
      ),
      GoRoute(path: '/about', builder: (_, __) => const AboutScreen()),
      GoRoute(
        path: '/settings/categories',
        builder: (_, __) => const ManageCategoriesScreen(),
      ),
      GoRoute(
        path: '/settings/completed',
        builder: (_, __) => const CompletedTasksScreen(),
      ),
    ],
  );
});

/// Listenable que notifica al router cada vez que cambia la sesión.
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(Ref ref) {
    ref.listen(authStateChangesProvider, (_, __) => notifyListeners());
  }
}
