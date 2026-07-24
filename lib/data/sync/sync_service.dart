import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../local/app_database.dart';
import 'connectivity_provider.dart';
import 'sync_state.dart';

/// Servicio que sincroniza la cola de `pending_ops` contra Supabase
/// cuando hay conexión. Se suscribe a `connectivityProvider` y
/// dispara `processQueue()` cada vez que vuelve internet.
///
/// Reintenta con backoff (incrementa `attempts` y guarda `lastError`)
/// en vez de borrar las ops que fallan, para que sobrevivan cierres
/// de la app y cortes de luz.
class SyncService {
  SyncService({
    required this.db,
    required this.supabaseUrl,
    required this.anonKey,
  });

  final AppDatabase db;
  final String supabaseUrl;
  final String anonKey;

  StreamController<SyncStatus>? _controller;
  SyncStatus _status = const SyncStatus(
    isOnline: true,
    state: SyncState.idle,
    pendingCount: 0,
  );
  Timer? _debounce;
  bool _processing = false;

  /// Stream reactivo con el estado actual (online/offline, count pendiente,
  /// si está sincronizando o terminó).
  Stream<SyncStatus> watch() {
    _controller ??= StreamController<SyncStatus>.broadcast(
      onListen: () => _emit(),
    );
    return _controller!.stream;
  }

  SyncStatus get current => _status;

  /// Lo llama el `Ref` cuando se inicializa. Arranca el listener de
  /// conectividad y procesa la cola si ya hay ops pendientes.
  void attach(Ref ref) {
    ref.listen<AsyncValue<bool>>(connectivityProvider, (_, next) {
      final online = next.maybeWhen(data: (v) => v, orElse: () => true);
      _status = _status.copyWith(isOnline: online);
      _emit();
      if (online) _scheduleProcess();
    });
    // Disparar carga inicial del count.
    refreshCount();
  }

  /// Recarga el contador de ops pendientes y emite.
  Future<void> refreshCount() async {
    final pending = await db.allPendingOps();
    _status = _status.copyWith(pendingCount: pending.length);
    _emit();
  }

  /// Encola una operación. Usado por los repositorios cuando
  /// Supabase falla por red.
  Future<void> enqueue({
    required String op,
    required String tableName,
    required Map<String, dynamic> payload,
  }) async {
    await db.into(db.pendingOps).insert(
      PendingOpsCompanion.insert(
        op: op,
        targetTable: tableName,
        payload: jsonEncode(payload),
        createdAt: DateTime.now(),
      ),
    );
    await refreshCount();
    _scheduleProcess();
  }

  void _scheduleProcess() {
    if (_processing) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), processQueue);
  }

  /// Procesa todas las ops pendientes en orden FIFO. Las que tienen
  /// éxito se borran; las que fallan incrementan `attempts`.
  Future<void> processQueue() async {
    if (_processing) return;
    final online = _status.isOnline;
    if (!online) return;

    _processing = true;
    _status = _status.copyWith(state: SyncState.syncing, lastError: null);
    _emit();

    final pending = await db.allPendingOps();
    var anyError = false;
    String? lastError;

    for (final op in pending) {
      try {
        final createdServerId = await _executeOp(op);
        // Si fue un `create` con id local, reconciliar el cache local.
        if (op.op == 'create' && createdServerId != null) {
          await _reconcileLocalId(op, createdServerId);
        }
        await db.deleteOp(op.id);
      } catch (e) {
        anyError = true;
        lastError = e.toString();
        await _bumpAttempts(op.id, lastError);
        // Si es un error de red, abortamos el batch — el resto también fallará.
        if (_isNetworkError(e)) break;
      }
    }

    final remaining = await db.allPendingOps();
    _status = _status.copyWith(
      state: anyError ? SyncState.error : SyncState.synced,
      pendingCount: remaining.length,
      lastError: lastError,
    );
    _emit();

    // Si todo OK, mostrar "synced" 2s y volver a idle (mismo patrón que
    // el NetworkStatusPill de Slay-Desktop).
    if (!anyError) {
      Timer(const Duration(seconds: 2), () {
        if (_status.state == SyncState.synced) {
          _status = _status.copyWith(state: SyncState.idle);
          _emit();
        }
      });
    }
    _processing = false;
  }

  /// Renombra la fila local con el id generado por Supabase, así el
  /// cache local queda consistente con la nube y los siguientes
  /// `update`/`delete` referencian el id real.
  Future<void> _reconcileLocalId(PendingOp op, String serverId) async {
    final payload = jsonDecode(op.payload) as Map<String, dynamic>;
    final localId = payload['id'] as String?;
    if (localId == null || !localId.startsWith('local_')) return;
    if (op.targetTable == 'tasks') {
      await db.renameCachedTaskId(localId, serverId);
    } else if (op.targetTable == 'categories') {
      await db.renameCachedCategoryId(localId, serverId);
    }
  }

  /// Ejecuta la op contra Supabase. Si fue un `create` y Supabase
  /// devuelve el id generado (con `Prefer: return=representation`),
  /// lo retorna para que `processQueue` reconcilie el cache local.
  Future<String?> _executeOp(PendingOp op) async {
    final payload = jsonDecode(op.payload) as Map<String, dynamic>;
    final token =
        Supabase.instance.client.auth.currentSession?.accessToken ?? anonKey;
    final url = '$supabaseUrl/rest/v1/${op.targetTable}';
    final headers = {
      'apikey': anonKey,
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      // `return=representation` → Supabase devuelve la fila creada
      // en el body (necesario para capturar el id server-generated).
      'Prefer': 'return=representation',
    };

    final method = switch (op.op) {
      'create' => 'POST',
      'update' => 'PATCH',
      'delete' => 'DELETE',
      _ => throw Exception('Unknown op: ${op.op}'),
    };

    http.Response res;
    final body = method == 'DELETE' ? null : jsonEncode(_stripLocalId(payload));
    final reqUrl = method == 'DELETE'
        ? Uri.parse('$url?id=eq.${Uri.encodeComponent(payload['id'] as String)}')
        : Uri.parse(url);
    switch (method) {
      case 'POST':
        res = await http.post(reqUrl, headers: headers, body: body);
      case 'PATCH':
        res = await http.patch(reqUrl, headers: headers, body: body);
      case 'DELETE':
        res = await http.delete(reqUrl, headers: headers);
      default:
        throw Exception('Unsupported method $method');
    }
    if (res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    // Capturar el id generado por el server (sólo para `create`).
    if (op.op == 'create' && res.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is List && decoded.isNotEmpty) {
          final first = decoded.first;
          if (first is Map<String, dynamic>) {
            return first['id'] as String?;
          }
        }
      } catch (_) {
        // body no parseable — sin reconciliación, pero la op ya está aplicada.
      }
    }
    return null;
  }

  /// Quita `id` si es local (empieza con `local_`) — el server asigna
  /// su propio UUID al hacer POST.
  Map<String, dynamic> _stripLocalId(Map<String, dynamic> p) {
    final id = p['id'] as String?;
    if (id != null && id.startsWith('local_')) {
      final copy = Map<String, dynamic>.from(p);
      copy.remove('id');
      return copy;
    }
    return p;
  }

  bool _isNetworkError(Object e) => SyncService.isNetworkError(e);

  /// Heurística pública para detectar errores de red. La usan tanto el
  /// `SyncService` (al drenar la cola) como los repositorios (para
  /// decidir si encolar o relanzar la excepción).
  ///
  /// Cubre:
  /// - DNS failure → "Failed host lookup" (`lookup`, no `failed host`)
  /// - Socket/timeout → `socket`, `timeout`, `connection`, `unreachable`
  /// - TLS/cert → `handshake`, `tls`, `cert`
  /// - TCP → `refused`, `reset`, `closed`
  static bool isNetworkError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('socket') ||
        s.contains('network') ||
        s.contains('failed host') ||
        s.contains('lookup') ||
        s.contains('timeout') ||
        s.contains('connection') ||
        s.contains('unreachable') ||
        s.contains('handshake') ||
        s.contains('tls') ||
        s.contains('cert') ||
        s.contains('refused') ||
        s.contains('reset') ||
        s.contains('closed');
  }

  Future<void> _bumpAttempts(int id, String err) async {
    final op = await (db.select(db.pendingOps)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (op == null) return;
    await (db.update(db.pendingOps)..where((t) => t.id.equals(id))).write(
      PendingOpsCompanion(
        attempts: Value(op.attempts + 1),
        lastError: Value(err.length > 500 ? err.substring(0, 500) : err),
      ),
    );
  }

  void _emit() {
    if (_controller == null || _controller!.isClosed) return;
    _controller!.add(_status);
  }

  Future<void> dispose() async {
    _debounce?.cancel();
    await _controller?.close();
  }
}

final syncServiceProvider = Provider<SyncService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final svc = SyncService(
    db: db,
    supabaseUrl: const String.fromEnvironment('SUPABASE_URL'),
    anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
  );
  svc.attach(ref);
  ref.onDispose(svc.dispose);
  return svc;
});

final syncStatusProvider = StreamProvider<SyncStatus>((ref) {
  final svc = ref.watch(syncServiceProvider);
  return svc.watch();
});
