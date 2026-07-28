import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider que controla si se muestra el overlay de "Cerrando sesión…"
/// sobre toda la app.
///
/// Se renderiza en `MaterialApp.router.builder`, que está **por encima
/// del Navigator de GoRouter**: por eso sobrevive a la transición
/// post-logout, cuando el router reemplaza `/settings` → `/login` y
/// cualquier `showDialog` sobre el rootNavigator sería destruido con
/// el Navigator viejo.
final loggingOutProvider = StateProvider<bool>((ref) => false);
