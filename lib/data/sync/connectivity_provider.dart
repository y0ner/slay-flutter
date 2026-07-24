import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `true` cuando hay al menos una interfaz de red activa (wifi, mobile,
/// ethernet, vpn…). `false` cuando todas las interfaces están en
/// `ConnectivityResult.none`.
///
/// `connectivity_plus` reporta cambios con un pequeño delay cuando se
/// desconecta; el stream emite el estado inicial al primer `listen`.
final connectivityProvider = StreamProvider<bool>((ref) {
  final c = Connectivity();
  return c.onConnectivityChanged.map((results) {
    return results.any((r) => r != ConnectivityResult.none);
  });
});
