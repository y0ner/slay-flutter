import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/state/logging_out_provider.dart';
import '../../core/theme/theme_controller.dart';
import '../../data/repositories/auth_repository.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeControllerProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 32, 0, 96),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text('Ajustes',
              style: Theme.of(context).textTheme.displaySmall),
        ),
        const SizedBox(height: 24),

        // ── Apariencia ───────────────────────────────────
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 8, 24, 4),
          child: Text('APARIENCIA',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey)),
        ),
        ListTile(
          leading: const Icon(Icons.brightness_6_outlined),
          title: const Text('Tema'),
          subtitle: Text(_label(themeMode)),
          onTap: () async {
            final selected = await showModalBottomSheet<AppThemeMode>(
              context: context,
              builder: (_) => SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    for (final m in AppThemeMode.values)
                      RadioListTile<AppThemeMode>(
                        title: Text(_label(m)),
                        value: m,
                        groupValue: themeMode,
                        onChanged: (v) => Navigator.pop(context, v),
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
            if (selected != null) {
              await ref.read(themeControllerProvider.notifier).set(selected);
            }
          },
        ),
        const Divider(),

        // ── Organización ─────────────────────────────────
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 8, 24, 4),
          child: Text('ORGANIZACIÓN',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey)),
        ),
        ListTile(
          leading: const Icon(Icons.category_outlined),
          title: const Text('Gestionar categorías'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/settings/categories'),
        ),
        ListTile(
          leading: const Icon(Icons.check_circle_outline),
          title: const Text('Tareas completadas'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/settings/completed'),
        ),
        const Divider(),

        // ── Información ──────────────────────────────────
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 8, 24, 4),
          child: Text('INFORMACIÓN',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey)),
        ),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('Acerca de Slay'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/about'),
        ),
        const Divider(),

        // ListTile con estado propio para mostrar loading durante
        // signOut y evitar la sensación de "pantalla en negro".
        // El router redirect (app_router.dart) se encarga de llevar
        // al usuario a /login al detectar `currentSession == null`,
        // así que acá NO llamamos `context.go('/login')` a mano
        // (competía con el redirect y dejaba parpadeo).
        const _LogoutTile(),
      ],
    );
  }

  String _label(AppThemeMode m) => switch (m) {
        AppThemeMode.system => 'Sigue al sistema',
        AppThemeMode.light => 'Claro',
        AppThemeMode.dark => 'Oscuro',
      };
}

/// Tile de "Cerrar sesión" aislado en un ConsumerStatefulWidget para
/// manejar el spinner de loading sin convertir toda la pantalla.
class _LogoutTile extends ConsumerStatefulWidget {
  const _LogoutTile();

  @override
  ConsumerState<_LogoutTile> createState() => _LogoutTileState();
}

class _LogoutTileState extends ConsumerState<_LogoutTile> {
  bool _loading = false;

  Future<void> _confirmAndSignOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Estás seguro?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Salir')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    // Bug #11 (v2): el signOut + redirect dejaba 1-2 frames de "pantalla
    // en negro" en dark mode (scaffoldBackgroundColor = #121212) antes
    // de que el LoginScreen terminara de construir.
    //
    // El intento anterior usaba `showDialog` sobre el rootNavigator, pero
    // ese Navigator **es el de GoRouter** en MaterialApp.router, así que
    // cuando el redirect reemplaza `/settings` → `/login`, ese Navigator
    // se reconstruye y se lleva el dialog consigo.
    //
    // Fix correcto: el overlay se monta en `MaterialApp.router.builder`
    // (POR ENCIMA del Navigator de GoRouter), así que sobrevive al
    // redirect. Lo activamos seteando el provider ANTES del signOut,
    // para que cuando se dispare el rebuild post-signOut el overlay ya
    // esté en pantalla.
    setState(() => _loading = true);
    ref.read(loggingOutProvider.notifier).state = true;
    try {
      await ref.read(authRepositoryProvider).signOut();
      // El router redirect se encarga de navegar a /login cuando
      // currentSession == null. Dejamos el overlay activo durante un
      // momento para tapar la transición post-redirect; el timer lo
      // apaga cuando ya estamos en /login.
      Future.delayed(const Duration(milliseconds: 600), () {
        if (ref.read(loggingOutProvider)) {
          ref.read(loggingOutProvider.notifier).state = false;
        }
      });
    } catch (e) {
      if (!mounted) return;
      ref.read(loggingOutProvider.notifier).state = false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cerrar sesión: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return ListTile(
      leading: _loading
          ? SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: error),
            )
          : Icon(Icons.logout, color: error),
      title: Text('Cerrar sesión', style: TextStyle(color: error)),
      enabled: !_loading,
      onTap: _loading ? null : _confirmAndSignOut,
    );
  }
}

/// Helper de SharedPreferences que se puede llamar en init.
Future<SharedPreferences> initPrefs() => SharedPreferences.getInstance();