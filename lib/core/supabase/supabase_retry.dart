import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Ejecuta [action] y reintenta automáticamente si detecta errores
/// transitorios comunes de PostgREST / Supabase, especialmente:
/// - PGRST303 ("JWT issued at future") generado por clock skew transitorio
///   entre los nodos de auth / API gateway de Supabase y la base de datos.
/// - Cortes o microdesconexiones de socket/handshake.
Future<T> retrySupabaseOperation<T>(
  Future<T> Function() action, {
  int maxRetries = 2,
  Duration initialDelay = const Duration(milliseconds: 600),
}) async {
  int attempt = 0;
  while (true) {
    try {
      return await action();
    } catch (e) {
      attempt++;
      if (attempt > maxRetries || !isTransientPostgrestError(e)) {
        rethrow;
      }
      final delay = initialDelay * attempt;
      debugPrint(
        'retrySupabaseOperation: detectado error transitorio ($e). '
        'Reintento $attempt/$maxRetries en ${delay.inMilliseconds}ms...',
      );
      await Future.delayed(delay);
    }
  }
}

/// Identifica si una excepción es un error transitorio recuperable con backoff.
bool isTransientPostgrestError(Object e) {
  if (e is PostgrestException) {
    if (e.code == 'PGRST303') return true;
    final msg = e.message.toLowerCase();
    if (msg.contains('jwt issued at future') ||
        msg.contains('jwt not yet valid')) {
      return true;
    }
  }
  final s = e.toString().toLowerCase();
  return s.contains('pgrst303') ||
      s.contains('jwt issued at future') ||
      s.contains('jwt not yet valid') ||
      s.contains('connection closed') ||
      s.contains('connection reset') ||
      s.contains('handshake');
}
