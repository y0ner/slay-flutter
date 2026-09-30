import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_calendar/device_calendar.dart';

import '../../core/state/logging_out_provider.dart';
import '../../core/theme/terminal_theme.dart';
import '../../core/theme/theme_controller.dart';
import '../../data/repositories/auth_repository.dart';
import '../../notifications/calendar_service.dart';
import '../../widgets/shimmer_loader.dart';

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
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
          child: Text('APARIENCIA',
              style: TextStyle(
                  fontFamily: TerminalTheme.monoFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: TerminalTheme.mutedOf(context))),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
          child: Text('ORGANIZACIÓN',
              style: TextStyle(
                  fontFamily: TerminalTheme.monoFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: TerminalTheme.mutedOf(context))),
        ),
        ListTile(
          leading: const Icon(Icons.check_circle_outline),
          title: const Text('Tareas completadas'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/settings/completed'),
        ),
        const Divider(),

        // ── Calendario & Recordatorios ───────────────────
        // device_calendar sólo tiene implementación en Android/iOS;
        // en desktop la sección no funcionaría (permisos que nunca
        // existen), así que la ocultamos.
        if (!kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.android ||
                defaultTargetPlatform == TargetPlatform.iOS)) ...[
          const _CalendarSyncSection(),

          const Divider(),
        ],

        // ── Información ──────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
          child: Text('INFORMACIÓN',
              style: TextStyle(
                  fontFamily: TerminalTheme.monoFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: TerminalTheme.mutedOf(context))),
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
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Estás seguro?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
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
      // Timeout defensivo de 2s para evitar que una red lenta o caída
      // de Supabase congele la UI indefinidamente.
      await ref
          .read(authRepositoryProvider)
          .signOut()
          .timeout(const Duration(seconds: 2), onTimeout: () {});
    } catch (_) {
      // Si falla la revocación remota en Supabase, garantizamos que el
      // usuario pueda salir igual hacia /login.
    } finally {
      // El ref puede estar invalidado si el redirect de GoRouter ya
      // destruyó este widget. Lo protegemos con try-catch; la red de
      // seguridad en _SlayAppState (authStateChangesProvider listener)
      // se encarga de resetear loggingOutProvider en ese caso.
      try {
        ref.read(loggingOutProvider.notifier).state = false;
      } catch (_) {}
      if (mounted) {
        setState(() => _loading = false);
        context.go('/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return ListTile(
      leading: _loading
          ? ShimmerLoader(size: 24, strokeWidth: 2.5, color: error)
          : Icon(Icons.logout, color: error),
      title: Text('Cerrar sesión', style: TextStyle(color: error)),
      enabled: !_loading,
      onTap: _loading ? null : _confirmAndSignOut,
    );
  }
}

/// Sección de configuración y sincronización con Google Calendar.
class _CalendarSyncSection extends StatefulWidget {
  const _CalendarSyncSection();

  @override
  State<_CalendarSyncSection> createState() => _CalendarSyncSectionState();
}

class _CalendarSyncSectionState extends State<_CalendarSyncSection> {
  bool _syncEnabled = false;
  String? _calendarName;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final enabled = await CalendarService.instance.isSyncEnabled();
    final name = await CalendarService.instance.getSelectedCalendarName();
    if (mounted) {
      setState(() {
        _syncEnabled = enabled;
        _calendarName = name;
      });
    }
  }

  Future<void> _toggleSync(bool value) async {
    if (value) {
      setState(() => _loading = true);
      // 1) Permiso de calendario en runtime. En Android el plugin no
      // dispara el diálogo del SO si el manifest no declara
      // READ/WRITE_CALENDAR — en ese caso aparece "denegado para
      // siempre" y hay que mandar al usuario a Ajustes del sistema.
      final granted = await CalendarService.instance.requestPermissions();
      if (!granted) {
        if (!mounted) return;
        setState(() => _loading = false);
        // El plugin no distingue "denegado una vez" de "denegado para
        // siempre", así que damos la ruta manual en ambos casos.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Se necesita el permiso de calendario. Concedelo en Ajustes del sistema → Apps → Slay → Permisos y volvé a intentar.'),
            duration: Duration(seconds: 5),
          ),
        );
        return;
      }
      // 2) Buscar calendario automáticamente. Si no hay ninguno
      // editable, avisar en vez de activar a ciegas.
      final calendar = await CalendarService.instance.getActiveCalendar();
      if (calendar == null) {
        if (!mounted) return;
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se encontró un calendario editable en el dispositivo. Creá una cuenta de calendario (ej. Google) e intentá de nuevo.'),
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }
      await CalendarService.instance.setSyncEnabled(true);
      if (mounted) {
        setState(() {
          _syncEnabled = true;
          _calendarName = calendar.name;
          _loading = false;
        });
      }
    } else {
      await CalendarService.instance.setSyncEnabled(false);
      if (mounted) {
        setState(() => _syncEnabled = false);
      }
    }
  }

  Future<void> _selectCalendar() async {
    setState(() => _loading = true);
    final calendars = await CalendarService.instance.getAvailableCalendars();
    if (!mounted) return;
    setState(() => _loading = false);

    if (calendars.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se encontraron calendarios editables.')),
      );
      return;
    }

    final selected = await showModalBottomSheet<Calendar>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Seleccionar calendario',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
            for (final cal in calendars)
              ListTile(
                leading: const Icon(Icons.calendar_today),
                title: Text(cal.name ?? 'Sin nombre'),
                subtitle: Text(cal.accountName ?? ''),
                onTap: () => Navigator.pop(context, cal),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (selected != null && selected.id != null) {
      await CalendarService.instance.setSelectedCalendar(
        selected.id!,
        selected.name ?? 'Calendario',
      );
      if (mounted) {
        setState(() => _calendarName = selected.name);
      }
    }
  }

  Future<void> _testReminder() async {
    setState(() => _loading = true);
    final success = await CalendarService.instance.createTestReminder();
    if (mounted) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? 'Recordatorio de prueba creado. Revisa tu calendario en 2 minutos.'
              : 'Error al crear recordatorio de prueba.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 8, 24, 4),
          child: Text('CALENDARIO & RECORDATORIOS',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey)),
        ),
        SwitchListTile(
          secondary: _loading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.calendar_month_outlined),
          title: const Text('Sincronizar con Google Calendar'),
          subtitle: Text(_syncEnabled
              ? (_calendarName ?? 'Calendario seleccionado')
              : 'Enviar recordatorios al calendario del dispositivo'),
          value: _syncEnabled,
          onChanged: _loading ? null : _toggleSync,
        ),
        if (_syncEnabled) ...[
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: const Text('Cambiar calendario'),
            subtitle: Text(_calendarName ?? 'No seleccionado'),
            onTap: _loading ? null : _selectCalendar,
          ),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('Probar recordatorio'),
            subtitle: const Text('Crea un evento de prueba en 2 minutos'),
            onTap: _loading ? null : _testReminder,
          ),
        ],
      ],
    );
  }
}

/// Helper de SharedPreferences que se puede llamar en init.
Future<SharedPreferences> initPrefs() => SharedPreferences.getInstance();