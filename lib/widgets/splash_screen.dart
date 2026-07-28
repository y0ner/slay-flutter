import 'package:flutter/material.dart';

import '../core/theme/slay_theme.dart';

/// Splash screen animado que se muestra al iniciar la app y mientras el
/// GoRouter determina la ruta inicial.
///
/// Por qué existe:
///   - En cold-start hay un frame negro entre el launch screen nativo y
///     el primer frame de Flutter (especialmente en dark mode).
///   - En warm-start, después de un logout, el usuario percibe un
///     "pantallazo" mientras el router reemplaza `/settings` por `/login`.
///   - El init de Supabase + Drift + LocalNotifications puede tardar
///     varios cientos de ms en dispositivos viejos.
///
/// Se monta en `MaterialApp.router.builder` (ver `lib/app.dart`) y
/// permanece visible durante un mínimo de 800 ms para dar feedback
/// claro, luego se desvanece.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  late final AnimationController _dots = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    _dots.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          gradient: slayBackgroundGradient(context),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // Brand centrado
              Center(
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, child) {
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        // Aura radial (sólo dark, más sutil que en login
                        // para no competir con el contenido detrás)
                        if (isDark)
                          Container(
                            width: 160 + (_pulse.value * 24),
                            height: 160 + (_pulse.value * 24),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  scheme.primary.withValues(alpha: 0.22),
                                  scheme.primary.withValues(alpha: 0.0),
                                ],
                              ),
                            ),
                          ),
                        child!,
                      ],
                    );
                  },
                  child: Container(
                    width: 96,
                    height: 96,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          scheme.primary,
                          scheme.primary.withValues(alpha: 0.8),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: scheme.primary.withValues(alpha: 0.4),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.bolt,
                      color: Colors.white,
                      size: 52,
                    ),
                  ),
                ),
              ),

              // Texto "Slay" + dots animados abajo
              Positioned(
                left: 0,
                right: 0,
                bottom: 64,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Slay',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    AnimatedBuilder(
                      animation: _dots,
                      builder: (context, _) {
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(3, (i) {
                            // Cada dot tiene un delay escalonado.
                            final t = ((_dots.value + (i * 0.2)) % 1.0);
                            final scale = 0.7 + (0.6 * (1 - (t - 0.5).abs() * 2).clamp(0.0, 1.0));
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: Transform.scale(
                                scale: scale,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: scheme.primary.withValues(
                                      alpha: 0.4 + 0.6 * scale,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            );
                          }),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
