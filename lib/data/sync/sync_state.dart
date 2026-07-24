/// Estado del proceso de sincronización offline → nube.
enum SyncState { idle, syncing, synced, error }

class SyncStatus {
  const SyncStatus({
    required this.isOnline,
    required this.state,
    required this.pendingCount,
    this.lastError,
  });

  final bool isOnline;
  final SyncState state;
  final int pendingCount;
  final String? lastError;

  SyncStatus copyWith({
    bool? isOnline,
    SyncState? state,
    int? pendingCount,
    String? lastError,
  }) {
    return SyncStatus(
      isOnline: isOnline ?? this.isOnline,
      state: state ?? this.state,
      pendingCount: pendingCount ?? this.pendingCount,
      lastError: lastError,
    );
  }
}
