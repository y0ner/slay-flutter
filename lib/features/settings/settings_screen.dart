import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

        ListTile(
          leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
          title: Text('Cerrar sesión',
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
          onTap: () async {
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
            if (ok == true) {
              await ref.read(authRepositoryProvider).signOut();
              if (context.mounted) context.go('/login');
            }
          },
        ),
      ],
    );
  }

  String _label(AppThemeMode m) => switch (m) {
        AppThemeMode.system => 'Sigue al sistema',
        AppThemeMode.light => 'Claro',
        AppThemeMode.dark => 'Oscuro',
      };
}

/// Helper de SharedPreferences que se puede llamar en init.
Future<SharedPreferences> initPrefs() => SharedPreferences.getInstance();
