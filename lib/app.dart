import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/state/logging_out_provider.dart';
import 'core/theme/slay_theme.dart';
import 'core/theme/theme_controller.dart';
import 'data/sync/sync_service.dart';
import 'widgets/logout_overlay.dart';
import 'widgets/network_status_pill.dart';
import 'widgets/splash_screen.dart';

class SlayApp extends ConsumerStatefulWidget {
  const SlayApp({super.key});

  @override
  ConsumerState<SlayApp> createState() => _SlayAppState();
}

class _SlayAppState extends ConsumerState<SlayApp> {
  /// Splash visible al inicio. Se oculta tras el primer frame + un
  /// mínimo de 800 ms para que la marca tenga tiempo de "presentarse"
  /// y tape el frame negro del cold start.
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) setState(() => _showSplash = false);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeControllerProvider);
    // Inicializa el SyncService en cuanto se monta la app. Es seguro
    // hacerlo acá porque `syncServiceProvider` es lazy: hasta que algo
    // lo lea, no abre DB ni se suscribe a connectivity.
    ref.watch(syncServiceProvider);
    final loggingOut = ref.watch(loggingOutProvider);

    return MaterialApp.router(
      title: 'Slay',
      debugShowCheckedModeBanner: false,
      theme: SlayTheme.light,
      darkTheme: SlayTheme.dark,
      themeMode: toMaterialThemeMode(themeMode),
      routerConfig: router,
      // El `builder` envuelve TODO el árbol del router. Cualquier widget
      // posicionado acá vive por encima del Navigator de GoRouter, así
      // que **sobrevive al redirect post-logout** (cuando el router
      // reemplaza `/settings` → `/login` y destruiría cualquier
      // showDialog sobre su rootNavigator).
      builder: (context, child) => Stack(
        children: [
          // 1) Contenido del router (login, home, etc.).
          child ?? const SizedBox.shrink(),
          // 2) Píldora de estado de red (ya existente).
          const Positioned(top: 0, left: 0, right: 0, child: NetworkStatusPill()),
          // 3) Overlay de logout (sólamente mientras se está cerrando
          //    sesión, antes del redirect).
          if (loggingOut) const Positioned.fill(child: LogoutOverlay()),
          // 4) Splash de arranque (cold start, tapa el frame negro
          //    mientras el router monta la primera ruta).
          if (_showSplash)
            const Positioned.fill(
              child: IgnorePointer(child: SplashScreen()),
            ),
        ],
      ),
    );
  }
}
