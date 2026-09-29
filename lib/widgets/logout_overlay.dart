import 'package:flutter/material.dart';

import '../core/theme/terminal_theme.dart';
import 'shimmer_loader.dart';

/// Overlay fullscreen que se muestra mientras se está cerrando la sesión.
/// Tapa el frame de transición (en dark mode se ve negro) y da feedback
/// claro de que la app está trabajando.
///
/// Se monta en `MaterialApp.router.builder` (ver `lib/app.dart`) para
/// sobrevivir al redirect post-logout. Si lo pusiéramos como un
/// `showDialog` sobre el rootNavigator, el Navigator de GoRouter se
/// reconstruiría al cambiar de `/settings` a `/login` y se llevaría
/// el dialog consigo.
class LogoutOverlay extends StatelessWidget {
  const LogoutOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      // Pintamos el fondo completo con el color del theme para que
      // el frame intermedio entre HomeShell dispose y LoginScreen mount
      // no se vea como un pantallazo negro en dark mode.
      color: TerminalTheme.bgOf(context),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Spinner con el acento naranja de la casa.
            ShimmerLoader(
              size: 44,
              strokeWidth: 3,
              color: TerminalTheme.accentOf(context),
            ),
            const SizedBox(height: 20),
            Text(
              '> cerrando sesión…',
              style: TextStyle(
                fontFamily: TerminalTheme.monoFamily,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: TerminalTheme.fgOf(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
