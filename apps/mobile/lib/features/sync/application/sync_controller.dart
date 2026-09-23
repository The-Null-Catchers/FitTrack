import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/outbox_dao.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';

/// What the sync indicator is showing.
enum SyncStatus { idle, syncing, offline, failed }

@immutable
class SyncState {
  const SyncState({
    this.status = SyncStatus.idle,
    this.pendingCount = 0,
    this.failedCount = 0,
    this.lastSyncedAt,
    this.lastError,
  });

  final SyncStatus status;
  final int pendingCount;
  final int failedCount;
  final DateTime? lastSyncedAt;
  final String? lastError;

  bool get hasPendingWork => pendingCount > 0 || failedCount > 0;

  SyncState copyWith({
    SyncStatus? status,
    int? pendingCount,
    int? failedCount,
    DateTime? lastSyncedAt,
    String? lastError,
    bool clearError = false,
  }) =>
      SyncState(
        status: status ?? this.status,
        pendingCount: pendingCount ?? this.pendingCount,
        failedCount: failedCount ?? this.failedCount,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
        lastError: clearError ? null : (lastError ?? this.lastError),
      );
}

/// Drains the offline outbox.
///
/// Runs when connectivity returns, when the app resumes, and on demand. Each
/// operation carries the `client_uuid` the server uses as an idempotency key,
/// so replaying a batch after a half-failed push is safe by construction.
class SyncController extends StateNotifier<SyncState> {
  SyncController(this._ref) : super(const SyncState()) {
    unawaited(refreshCounts());

    // Sync as soon as the device comes back online.
    _ref.listen<bool>(isOnlineProvider, (bool? previous, bool online) {
      if (online && (previous ?? false) == false) {
        unawaited(sync());
      }
      if (!online) {
        state = state.copyWith(status: SyncStatus.offline);
      }
    });
  }

  final Ref _ref;
  bool _isSyncing = false;

  OutboxDao get _outbox => _ref.read(outboxDaoProvider);

  ApiClient get _client => _ref.read(apiClientProvider);

  /// How many operations are pushed in one request.
  static const int batchSize = 50;

  Future<void> refreshCounts() async {
    state = state.copyWith(
      pendingCount: await _outbox.pendingCount(),
      failedCount: await _outbox.failedCount(),
    );
  }

  Future<void> sync() async {
    if (_isSyncing) return;
    if (!_ref.read(isOnlineProvider)) {
      state = state.copyWith(status: SyncStatus.offline);
      return;
    }

    final List<OutboxEntry> pending = await _outbox.pending(limit: batchSize);
    if (pending.isEmpty) {
      await refreshCounts();
      state = state.copyWith(status: SyncStatus.idle, clearError: true);
      return;
    }

    _isSyncing = true;
    state = state.copyWith(status: SyncStatus.syncing, clearError: true);

    try {
      final Map<String, dynamic> body =
          await _client.post<Map<String, dynamic>>(
        '/api/v1/sync/push',
        data: <String, dynamic>{
          'operations': pending
              .map((OutboxEntry entry) => entry.toSyncOperation())
              .toList(),
        },
      );

      for (final dynamic raw
          in (body['results'] as List<dynamic>? ?? const <dynamic>[])) {
        final Map<String, dynamic> result =
            Map<String, dynamic>.from(raw as Map<dynamic, dynamic>);
        final String clientUuid = result['client_uuid'] as String;
        final String status = result['status'] as String;

        if (status == 'applied' || status == 'duplicate') {
          await _outbox.markSynced(clientUuid);
        } else {
          await _outbox.markFailed(
            clientUuid,
            '${result['message'] ?? 'Sync failed'}',
          );
        }
      }

      await _ref.read(appPreferencesProvider).setLastSyncAt(DateTime.now());
      await refreshCounts();

      final int stillFailed = await _outbox.failedCount();
      state = state.copyWith(
        status: stillFailed > 0 ? SyncStatus.failed : SyncStatus.idle,
        lastSyncedAt: DateTime.now(),
      );

      // More work queued than one batch: keep going.
      if (await _outbox.pendingCount() > 0) {
        _isSyncing = false;
        await sync();
        return;
      }
    } on ApiException catch (error) {
      state = state.copyWith(
        status: error.isConnectivity ? SyncStatus.offline : SyncStatus.failed,
        lastError: error.message,
      );
    } finally {
      _isSyncing = false;
    }
  }

  /// Re-queue everything that was parked after repeated failures.
  Future<void> retryFailed() async {
    await _outbox.retryFailed();
    await refreshCounts();
    await sync();
  }

  Future<void> discard(String clientUuid) async {
    await _outbox.discard(clientUuid);
    await refreshCounts();
  }
}

final StateNotifierProvider<SyncController, SyncState> syncProvider =
    StateNotifierProvider<SyncController, SyncState>(
  (Ref ref) => SyncController(ref),
);
