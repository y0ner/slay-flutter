import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/slay_theme.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/task_repository.dart';
import '../../data/sync/sync_service.dart';

/// Shell que contiene el BottomNavigationBar. El `child` que recibe
/// es la pantalla actual (gestionada por GoRouter).
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key, required this.child, required this.currentLocation});

  final Widget child;
  final String currentLocation;

  static const _tabs = <_TabSpec>[
    _TabSpec('/',          Icons.wb_sunny_outlined,    Icons.wb_sunny,    'Mi Día'),
    _TabSpec('/tasks',     Icons.list_alt_outlined,    Icons.list_alt,    'Tareas'),
    _TabSpec('/pomodoro',  Icons.timer_outlined,       Icons.timer,       'Pomodoro'),
    _TabSpec('/calendar',  Icons.calendar_month_outlined, Icons.calendar_month, 'Calendario'),
    _TabSpec('/settings',  Icons.settings_outlined,    Icons.settings,    'Ajustes'),
  ];

  /// Iteramos en orden inverso: como `_tabs[0].path == '/'`, ese path es
  /// prefijo de TODAS las ubicaciones. Si iteráramos de menor a mayor,
  /// `'/tasks'.startsWith('/')` matchearía primero y el indicador quedaría
  /// siempre en Mi Día (índice 0) sin importar a dónde naveguemos.
  int get _currentIndex {
    for (var i = _tabs.length - 1; i >= 0; i--) {
      if (currentLocation.startsWith(_tabs[i].path)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: slayBackgroundGradient(context)),
        child: child,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => context.go(_tabs[i].path),
        destinations: [
          for (final t in _tabs)
            NavigationDestination(
              icon: Icon(t.icon),
              selectedIcon: Icon(t.iconSelected),
              label: t.label,
            ),
        ],
      ),
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton(
              onPressed: () => _quickAdd(context, ref),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  void _quickAdd(BuildContext context, WidgetRef ref) {
    // Si estamos en Mi Día, pre-cargamos el recordatorio a hoy para que
    // la tarea aparezca automáticamente en la lista. El usuario puede
    // cambiarlo o limpiarlo desde el diálogo.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    showDialog(
      context: context,
      builder: (_) => _QuickAddDialog(initialReminder: today),
    );
  }
}

class _TabSpec {
  final String path;
  final IconData icon;
  final IconData iconSelected;
  final String label;
  const _TabSpec(this.path, this.icon, this.iconSelected, this.label);
}

class _QuickAddDialog extends ConsumerStatefulWidget {
  const _QuickAddDialog({this.initialReminder});
  final DateTime? initialReminder;
  @override
  ConsumerState<_QuickAddDialog> createState() => _QuickAddDialogState();
}

class _QuickAddDialogState extends ConsumerState<_QuickAddDialog> {
  final _ctrl = TextEditingController();
  String? _categoryId;
  late DateTime? _reminder;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _reminder = widget.initialReminder;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_ctrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(taskRepositoryProvider);
      // Leer categorías del cache local — antes hacía `cats.getAll()`
      // directo contra Supabase, lo que fallaba offline ANTES de encolar.
      final cachedCats = ref.read(cachedCategoriesStreamProvider);
      final list = cachedCats.value ?? const [];
      final catId = _categoryId ?? (list.isNotEmpty ? list.first.id : '');
      if (catId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Crea primero una categoría')),
          );
        }
        return;
      }
      final created = await repo.create(
        title: _ctrl.text.trim(),
        categoryId: catId,
        reminder: _reminder,
      );
      // Refrescar UI: realtime puede tardar ms, esto asegura feedback
      // inmediato (cache local + lista visible).
      ref.invalidate(tasksStreamProvider);
      ref.invalidate(cachedTasksStreamProvider);
      // Si la tarea quedó con id local (no se pudo subir a Supabase),
      // persistir en cache para feedback inmediato en la UI.
      if (created.isLocal) {
        await repo.upsertLocal(created);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Guardada — pendiente de sincronizar'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        // Si fue un error de red, igualmente creamos la tarea local
        // (create() ya la encoló). Mostramos feedback claro.
        if (SyncService.isNetworkError(e)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Guardada — pendiente de sincronizar'),
              duration: Duration(seconds: 2),
            ),
          );
          if (mounted) Navigator.of(context).pop();
        } else {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catsAsync = ref.watch(cachedCategoriesStreamProvider);
    final list = catsAsync.maybeWhen(
      data: (l) => l,
      orElse: () => const [],
    );
    return AlertDialog(
      title: const Text('Nueva tarea'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _ctrl,
              decoration: const InputDecoration(labelText: 'Título'),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            if (list.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Crea primero una categoría'),
              )
            else
              DropdownButtonFormField<String>(
                value: _categoryId ?? list.first.id,
                decoration: const InputDecoration(labelText: 'Categoría'),
                items: [
                  for (final c in list)
                    DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) => setState(() => _categoryId = v),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(_reminder == null
                      ? 'Sin recordatorio (no aparece en Mi Día)'
                      : 'Recordatorio: ${_reminder!.day}/${_reminder!.month}/${_reminder!.year} ${_reminder!.hour.toString().padLeft(2, '0')}:${_reminder!.minute.toString().padLeft(2, '0')}'),
                ),
                if (_reminder != null)
                  TextButton(
                    onPressed: () => setState(() => _reminder = null),
                    child: const Text('Quitar'),
                  ),
                TextButton(
                  onPressed: () async {
                    final now = DateTime.now();
                    final d = await showDatePicker(
                      context: context,
                      firstDate: now,
                      lastDate: now.add(const Duration(days: 365)),
                      initialDate: _reminder ?? now,
                    );
                    if (d == null) return;
                    if (!context.mounted) return;
                    final t = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(_reminder ?? now),
                    );
                    if (t == null) return;
                    setState(() => _reminder = DateTime(
                          d.year, d.month, d.day, t.hour, t.minute,
                        ));
                  },
                  child: const Text('Elegir'),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
