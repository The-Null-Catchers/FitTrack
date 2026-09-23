import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

/// A cached JSON document and the moment it was written.
class CachedDocument {
  const CachedDocument({required this.payload, required this.updatedAt});

  final Object payload;
  final DateTime updatedAt;

  Map<String, dynamic> get asMap =>
      Map<String, dynamic>.from(payload as Map<dynamic, dynamic>);

  List<dynamic> get asList => payload as List<dynamic>;

  bool isOlderThan(Duration age) => DateTime.now().difference(updatedAt) > age;
}

/// Generic read-through cache for API responses.
///
/// Every list and detail screen reads from here first, which is what makes the
/// app usable on a cold start with no connection.
class CacheDao {
  const CacheDao(this._database);

  final AppDatabase _database;

  Database get _db => _database.raw;

  // Stable keys, so a screen and its refresher can't disagree.
  static const String dashboardKey = 'dashboard';
  static const String activeProgramKey = 'program.active';
  static const String programsKey = 'programs';
  static const String templatesKey = 'programs.templates';
  static const String habitsKey = 'habits';
  static const String goalsKey = 'goals';
  static const String profileKey = 'profile';
  static const String recordsKey = 'records';
  static const String workoutHistoryKey = 'workouts.history';

  static String exerciseSearchKey(String query) => 'exercises.$query';

  static String nutritionDayKey(String isoDate) => 'nutrition.$isoDate';

  Future<void> write(String key, Object payload) async {
    await _db.insert(
      AppDatabase.cacheTable,
      <String, Object?>{
        'key': key,
        'payload': json.encode(payload),
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<CachedDocument?> read(String key) async {
    final List<Map<String, Object?>> rows = await _db.query(
      AppDatabase.cacheTable,
      where: 'key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    try {
      return CachedDocument(
        payload: json.decode(rows.first['payload']! as String) as Object,
        updatedAt: DateTime.parse(rows.first['updated_at']! as String),
      );
    } on FormatException {
      // A corrupt entry is worth less than no entry.
      await delete(key);
      return null;
    }
  }

  Future<void> delete(String key) async {
    await _db.delete(AppDatabase.cacheTable,
        where: 'key = ?', whereArgs: <Object?>[key]);
  }

  Future<void> deletePrefix(String prefix) async {
    await _db.delete(
      AppDatabase.cacheTable,
      where: 'key LIKE ?',
      whereArgs: <Object?>['$prefix%'],
    );
  }
}
