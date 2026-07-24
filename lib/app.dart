import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/slay_theme.dart';
import 'core/theme/theme_controller.dart';
import 'data/sync/sync_service.dart';
import 'widgets/network_status_pill.dart';

class SlayApp extends ConsumerWidget {
  const SlayApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeControllerProvider);
    // Inicializa el SyncService en cuanto se monta la app. Es seguro
    // hacerlo acá porque `syncServiceProvider` es lazy: hasta que algo
    // lo lea, no abre DB ni se suscribe a connectivity.
    ref.watch(syncServiceProvider);
    return MaterialApp.router(
      title: 'Slay',
      debugShowCheckedModeBanner: false,
      theme: SlayTheme.light,
      darkTheme: SlayTheme.dark,
      themeMode: toMaterialThemeMode(themeMode),
      routerConfig: router,
      builder: (context, child) => Stack(
        children: [
          child ?? const SizedBox.shrink(),
          const Positioned(top: 0, left: 0, right: 0, child: NetworkStatusPill()),
        ],
      ),
    );
  }
}
