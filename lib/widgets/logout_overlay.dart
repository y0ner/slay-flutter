import 'package:flutter/material.dart';

import '../core/theme/slay_theme.dart';

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
    final theme = Theme.of(context);
    return Material(
      // Pintamos el fondo completo con el gradiente del theme para que
      // el frame intermedio entre HomeShell dispose y LoginScreen mount
      // no se vea como un pantallazo negro en dark mode.
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          gradient: slayBackgroundGradient(context),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Spinner themed con el primary color (verde emerald).
              SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Cerrando sesión…',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
