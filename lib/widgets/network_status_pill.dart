import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/sync/sync_service.dart';
import '../data/sync/sync_state.dart';

/// Píldora animada que se muestra arriba de la app cuando hay
/// cambios de conectividad. Equivalente al `NetworkStatusPill`
/// de Slay-Desktop (kotlin `SlayApp.kt` línea 274).
///
/// Estados:
/// - **offline** → rojo claro, ícono `wifi_off`.
/// - **syncing** → celeste, ícono `sync` rotando.
/// - **synced** (2s) → verde, ícono `cloud_done`.
/// - **error** → naranja, ícono `cloud_off` + texto "N ops pendientes".
/// - **idle** → oculto.
class NetworkStatusPill extends ConsumerWidget {
  const NetworkStatusPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(syncStatusProvider);
    final status = async.maybeWhen(
      data: (s) => s,
      orElse: () => const SyncStatus(
        isOnline: true,
        state: SyncState.idle,
        pendingCount: 0,
      ),
    );

    Color? bg;
    IconData icon = Icons.cloud_done;
    String text = '';
    bool spinning = false;

    if (!status.isOnline) {
      bg = const Color(0xFFE57373);
      icon = Icons.wifi_off;
      text = status.pendingCount > 0
          ? 'Sin internet · ${status.pendingCount} pendientes'
          : 'Sin internet';
    } else if (status.state == SyncState.syncing) {
      bg = const Color(0xFF64B5F6);
      icon = Icons.sync;
      text = 'Sincronizando…';
      spinning = true;
    } else if (status.state == SyncState.synced) {
      bg = const Color(0xFF81C784);
      icon = Icons.cloud_done;
      text = 'Sincronizado';
    } else if (status.state == SyncState.error) {
      bg = const Color(0xFFFFB74D);
      icon = Icons.cloud_off;
      text = '${status.pendingCount} pendientes';
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, anim) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
            .animate(anim),
        child: FadeTransition(opacity: anim, child: child),
      ),
      child: bg == null
          ? const SizedBox.shrink(key: ValueKey('hidden'))
          : SafeArea(
              key: ValueKey('$bg-$text'),
              child: Container(
                width: double.infinity,
                color: bg,
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    spinning
                        ? _SpinningIcon(icon: icon)
                        : Icon(icon, color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      text,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _SpinningIcon extends StatefulWidget {
  const _SpinningIcon({required this.icon});
  final IconData icon;

  @override
  State<_SpinningIcon> createState() => _SpinningIconState();
}

class _SpinningIconState extends State<_SpinningIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(seconds: 1))
        ..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _ctrl,
      child: Icon(widget.icon, color: Colors.white, size: 16),
    );
  }
}
