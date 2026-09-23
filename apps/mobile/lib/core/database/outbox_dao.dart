import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

/// One queued offline mutation.
class OutboxEntry {
  const OutboxEntry({
    required this.id,
    required this.clientUuid,
    required this.entity,
    required this.operation,
    required this.payload,
    required this.createdAt,
    this.attempts = 0,
    this.lastError,
    this.status = 'pending',
  });

  final int id;
  final String clientUuid;
  final String entity;
  final String operation;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int attempts;
  final String? lastError;
  final String status;

  factory OutboxEntry.fromRow(Map<String, Object?> row) => OutboxEntry(
        id: row['id']! as int,
        clientUuid: row['client_uuid']! as String,
        entity: row['entity']! as String,
        operation: row['operation']! as String,
        payload: Map<String, dynamic>.from(
          json.decode(row['payload']! as String) as Map<dynamic, dynamic>,
        ),
        createdAt: DateTime.parse(row['created_at']! as String),
        attempts: (row['attempts'] as int?) ?? 0,
        lastError: row['last_error'] as String?,
        status: (row['status'] as String?) ?? 'pending',
      );

  /// The shape `/api/v1/sync/push` expects.
  Map<String, dynamic> toSyncOperation() => <String, dynamic>{
        'client_uuid': clientUuid,
        'entity': entity,
        'operation': operation,
        'client_updated_at': createdAt.toUtc().toIso8601String(),
        'payload': payload,
      };
}

/// Reads and writes for the offline outbox.
class OutboxDao {
  const OutboxDao(this._database);

  final AppDatabase _database;

  /// Give up on an entry after this many failed attempts, so one permanently
  /// invalid change can't block the queue forever.
  static const int maxAttempts = 5;

  Database get _db => _database.raw;

  Future<void> enqueue({
    required String clientUuid,
    required String entity,
    required Map<String, dynamic> payload,
    String operation = 'create',
  }) async {
    await _db.insert(
      AppDatabase.outboxTable,
      <String, Object?>{
        'client_uuid': clientUuid,
        'entity': entity,
        'operation': operation,
        'payload': json.encode(payload),
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'status': 'pending',
      },
      // Re-queuing the same client_uuid replaces the payload rather than
      // creating a second operation for the same logical change.
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<OutboxEntry>> pending({int limit = 100}) async {
    final List<Map<String, Object?>> rows = await _db.query(
      AppDatabase.outboxTable,
      where: 'status = ?',
      whereArgs: <Object?>['pending'],
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return rows.map(OutboxEntry.fromRow).toList();
  }

  Future<int> pendingCount() async {
    final List<Map<String, Object?>> rows = await _db.rawQuery(
      'SELECT COUNT(*) AS count FROM ${AppDatabase.outboxTable} WHERE status = ?',
      <Object?>['pending'],
    );
    return (rows.first['count'] as int?) ?? 0;
  }

  Future<int> failedCount() async {
    final List<Map<String, Object?>> rows = await _db.rawQuery(
      'SELECT COUNT(*) AS count FROM ${AppDatabase.outboxTable} WHERE status = ?',
      <Object?>['failed'],
    );
    return (rows.first['count'] as int?) ?? 0;
  }

  Future<void> markSynced(String clientUuid) async {
    await _db.delete(
      AppDatabase.outboxTable,
      where: 'client_uuid = ?',
      whereArgs: <Object?>[clientUuid],
    );
  }

  /// Record a failure. The entry stays pending until [maxAttempts] is reached,
  /// at which point it is parked as `failed` for the user to retry manually.
  Future<void> markFailed(String clientUuid, String error) async {
    final List<Map<String, Object?>> rows = await _db.query(
      AppDatabase.outboxTable,
      where: 'client_uuid = ?',
      whereArgs: <Object?>[clientUuid],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final int attempts = ((rows.first['attempts'] as int?) ?? 0) + 1;
    await _db.update(
      AppDatabase.outboxTable,
      <String, Object?>{
        'attempts': attempts,
        'last_error': error,
        'status': attempts >= maxAttempts ? 'failed' : 'pending',
      },
      where: 'client_uuid = ?',
      whereArgs: <Object?>[clientUuid],
    );
  }

  /// Move parked entries back into the queue after a manual retry.
  Future<void> retryFailed() async {
    await _db.update(
      AppDatabase.outboxTable,
      <String, Object?>{'status': 'pending', 'attempts': 0, 'last_error': null},
      where: 'status = ?',
      whereArgs: <Object?>['failed'],
    );
  }

  Future<void> discard(String clientUuid) => markSynced(clientUuid);

  Future<List<OutboxEntry>> all() async {
    final List<Map<String, Object?>> rows = await _db.query(
      AppDatabase.outboxTable,
      orderBy: 'created_at ASC',
    );
    return rows.map(OutboxEntry.fromRow).toList();
  }
}
