import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

/// Persistence for the workout currently in progress.
///
/// Stored as a single row holding the whole session document. The session is
/// written after every set, so force-quitting the app mid-workout — or losing
/// the network entirely — costs nothing.
class ActiveSessionDao {
  const ActiveSessionDao(this._database);

  final AppDatabase _database;

  Database get _db => _database.raw;

  Future<void> save(String clientUuid, Map<String, dynamic> session) async {
    await _db.insert(
      AppDatabase.activeSessionTable,
      <String, Object?>{
        'id': 1,
        'client_uuid': clientUuid,
        'payload': json.encode(session),
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> read() async {
    final List<Map<String, Object?>> rows = await _db.query(
      AppDatabase.activeSessionTable,
      where: 'id = 1',
      limit: 1,
    );
    if (rows.isEmpty) return null;

    try {
      return Map<String, dynamic>.from(
        json.decode(rows.first['payload']! as String) as Map<dynamic, dynamic>,
      );
    } on FormatException {
      await clear();
      return null;
    }
  }

  Future<String?> readClientUuid() async {
    final List<Map<String, Object?>> rows = await _db.query(
      AppDatabase.activeSessionTable,
      columns: <String>['client_uuid'],
      where: 'id = 1',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['client_uuid'] as String?;
  }

  Future<void> clear() async {
    await _db.delete(AppDatabase.activeSessionTable, where: 'id = 1');
  }
}
