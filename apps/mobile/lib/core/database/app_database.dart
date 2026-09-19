import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// The on-device SQLite database.
///
/// Three tables carry the whole offline story:
///
/// * `outbox` — mutations made while offline, replayed to `/sync/push` in
///   order. Each row carries the `client_uuid` the server treats as an
///   idempotency key, so a retried batch can never double-write.
/// * `cache` — JSON documents (exercise library, programs, dashboard) keyed by
///   a stable string, so every screen has something to render without a
///   network round trip.
/// * `active_session` — the in-progress workout, written on every set so
///   closing the app mid-workout loses nothing.
///
/// sqflite is used directly rather than through Drift or Isar: the schema is
/// small and stable, and keeping it codegen-free means the build has no
/// generation step that can drift out of sync with the source.
class AppDatabase {
  AppDatabase._(this._db);

  final Database _db;

  Database get raw => _db;

  static const String outboxTable = 'outbox';
  static const String cacheTable = 'cache';
  static const String activeSessionTable = 'active_session';
  static const int _version = 1;

  static Future<AppDatabase> open({String? path}) async {
    final String databasePath =
        path ?? p.join(await getDatabasesPath(), 'fittrack.db');

    final Database db = await openDatabase(
      databasePath,
      version: _version,
      onConfigure: (Database db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _createSchema,
      onUpgrade: _upgradeSchema,
    );
    return AppDatabase._(db);
  }

  static Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $outboxTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_uuid TEXT NOT NULL UNIQUE,
        entity TEXT NOT NULL,
        operation TEXT NOT NULL DEFAULT 'create',
        payload TEXT NOT NULL,
        created_at TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        status TEXT NOT NULL DEFAULT 'pending'
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_outbox_status ON $outboxTable (status, created_at)',
    );

    await db.execute('''
      CREATE TABLE $cacheTable (
        key TEXT PRIMARY KEY,
        payload TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE $activeSessionTable (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        client_uuid TEXT NOT NULL,
        payload TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _upgradeSchema(Database db, int from, int to) async {
    // Only version 1 exists so far. Future migrations append here; the app
    // never drops a table, because the outbox may hold unsynced work.
  }

  Future<void> close() => _db.close();

  /// Wipe local state on sign-out. Unsynced work is intentionally included:
  /// it belongs to the account that is leaving the device.
  Future<void> clear() async {
    await _db.transaction((Transaction txn) async {
      await txn.delete(outboxTable);
      await txn.delete(cacheTable);
      await txn.delete(activeSessionTable);
    });
  }
}
