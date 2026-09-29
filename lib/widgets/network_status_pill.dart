import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/terminal_theme.dart';
import '../data/sync/sync_service.dart';
import '../data/sync/sync_state.dart';

/// Banda de estado de red estilo terminal que se muestra arriba de la
/// app cuando hay cambios de conectividad. Equivalente al
/// `NetworkStatusPill` de Slay-Desktop.
///
/// En vez de colores pastel rellenos (estilo viejo), usa el patrón de
/// la casa: panel con borde 1px inferior, texto monoespaciado y un
/// cuadradito de estado con el color semántico de cada estado.
///
/// Estados:
/// - **offline** → cuadradito rojo (heart), ícono `wifi_off`.
/// - **syncing** → cuadradito ámbar (building), ícono `sync` rotando.
/// - **synced** (2s) → cuadradito verde (ok), ícono `cloud_done`.
/// - **error** → cuadradito naranja (accent), ícono `cloud_off` +
///   "N ops pendientes".
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

    Color dotColor;
    IconData icon = Icons.cloud_done;
    String text = '';
    bool spinning = false;

    if (!status.isOnline) {
      dotColor = TerminalTheme.heartOf(context);
      icon = Icons.wifi_off;
      text = status.pendingCount > 0
          ? 'sin internet · ${status.pendingCount} pendientes'
          : 'sin internet';
    } else if (status.state == SyncState.syncing) {
      dotColor = TerminalTheme.buildingOf(context);
      icon = Icons.sync;
      text = 'sincronizando…';
      spinning = true;
    } else if (status.state == SyncState.synced) {
      dotColor = TerminalTheme.okOf(context);
      icon = Icons.cloud_done;
      text = 'sincronizado';
    } else if (status.state == SyncState.error) {
      dotColor = TerminalTheme.accentOf(context);
      icon = Icons.cloud_off;
      text = '${status.pendingCount} pendientes';
    } else {
      // idle → oculto.
      return const SizedBox.shrink(key: ValueKey('hidden'));
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, anim) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
            .animate(anim),
        child: FadeTransition(opacity: anim, child: child),
      ),
      child: SafeArea(
        key: ValueKey('$dotColor-$text'),
        bottom: false,
        child: Container(
          width: double.infinity,
          // Panel de la casa con borde inferior de 1px: banda plana,
          // sin relleno de color ni sombras. El color va dentro del
          // BoxDecoration (Container no acepta color + decoration).
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 16),
          decoration: BoxDecoration(
            color: TerminalTheme.panelOf(context),
            border: Border(
              bottom: BorderSide(color: TerminalTheme.lineOf(context)),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Cuadradito de estado, igual que los labels del login.
              Container(width: 7, height: 7, color: dotColor),
              const SizedBox(width: 8),
              spinning
                  ? _SpinningIcon(icon: icon)
                  : Icon(icon, size: 14, color: TerminalTheme.mutedOf(context)),
              const SizedBox(width: 8),
              Text(
                text,
                style: TextStyle(
                  fontFamily: TerminalTheme.monoFamily,
                  color: TerminalTheme.fgOf(context),
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                  letterSpacing: 0.3,
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
      child: Icon(widget.icon, size: 14, color: TerminalTheme.mutedOf(context)),
    );
  }
}
