import 'package:fittrack/core/database/app_database.dart';
import 'package:fittrack/core/database/cache_dao.dart';
import 'package:fittrack/core/database/outbox_dao.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// These run against a real in-memory SQLite database, so the offline queue is
/// exercised the same way it behaves on a device.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase database;
  late OutboxDao outbox;
  late CacheDao cache;

  setUp(() async {
    database = await AppDatabase.open(path: inMemoryDatabasePath);
    outbox = OutboxDao(database);
    cache = CacheDao(database);
  });

  tearDown(() async => database.close());

  group('outbox', () {
    test('queues an operation and reports it as pending', () async {
      await outbox.enqueue(
        clientUuid: 'weight-1',
        entity: 'body_weight',
        payload: <String, dynamic>{'weight_kg': 82.4},
      );

      expect(await outbox.pendingCount(), 1);
      final List<OutboxEntry> pending = await outbox.pending();
      expect(pending.single.entity, 'body_weight');
      expect(pending.single.payload['weight_kg'], 82.4);
    });

    test('re-queuing the same client id replaces rather than duplicates', () async {
      await outbox.enqueue(
        clientUuid: 'weight-1',
        entity: 'body_weight',
        payload: <String, dynamic>{'weight_kg': 82.4},
      );
      await outbox.enqueue(
        clientUuid: 'weight-1',
        entity: 'body_weight',
        payload: <String, dynamic>{'weight_kg': 81.9},
      );

      expect(await outbox.pendingCount(), 1);
      expect((await outbox.pending()).single.payload['weight_kg'], 81.9);
    });

    test('preserves the order changes were made in', () async {
      for (int index = 0; index < 3; index++) {
        await outbox.enqueue(
          clientUuid: 'op-$index',
          entity: 'water_log',
          payload: <String, dynamic>{'amount_ml': 250},
        );
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }

      final List<OutboxEntry> pending = await outbox.pending();
      expect(
        pending.map((OutboxEntry entry) => entry.clientUuid).toList(),
        <String>['op-0', 'op-1', 'op-2'],
      );
    });

    test('a synced operation leaves the queue', () async {
      await outbox.enqueue(
        clientUuid: 'meal-1',
        entity: 'meal',
        payload: <String, dynamic>{},
      );
      await outbox.markSynced('meal-1');

      expect(await outbox.pendingCount(), 0);
    });

    test('stays pending while retries remain, then parks as failed', () async {
      await outbox.enqueue(
        clientUuid: 'meal-1',
        entity: 'meal',
        payload: <String, dynamic>{},
      );

      for (int attempt = 1; attempt < OutboxDao.maxAttempts; attempt++) {
        await outbox.markFailed('meal-1', 'boom');
        expect(await outbox.pendingCount(), 1, reason: 'attempt $attempt');
      }

      await outbox.markFailed('meal-1', 'boom');
      expect(await outbox.pendingCount(), 0);
      expect(await outbox.failedCount(), 1);
    });

    test('a manual retry puts parked work back in the queue', () async {
      await outbox.enqueue(
        clientUuid: 'meal-1',
        entity: 'meal',
        payload: <String, dynamic>{},
      );
      for (int attempt = 0; attempt <= OutboxDao.maxAttempts; attempt++) {
        await outbox.markFailed('meal-1', 'boom');
      }
      expect(await outbox.failedCount(), 1);

      await outbox.retryFailed();
      expect(await outbox.pendingCount(), 1);
      expect(await outbox.failedCount(), 0);
    });

    test('serialises to the shape the sync endpoint expects', () async {
      await outbox.enqueue(
        clientUuid: 'weight-1',
        entity: 'body_weight',
        payload: <String, dynamic>{'weight_kg': 82.4},
      );

      final Map<String, dynamic> operation =
          (await outbox.pending()).single.toSyncOperation();
      expect(operation['client_uuid'], 'weight-1');
      expect(operation['entity'], 'body_weight');
      expect(operation['operation'], 'create');
      expect(operation['payload'], <String, dynamic>{'weight_kg': 82.4});
      expect(operation['client_updated_at'], isA<String>());
    });
  });

  group('cache', () {
    test('round-trips a document', () async {
      await cache.write(CacheDao.dashboardKey, <String, dynamic>{'streak': 5});

      final CachedDocument? cached = await cache.read(CacheDao.dashboardKey);
      expect(cached, isNotNull);
      expect(cached!.asMap['streak'], 5);
    });

    test('overwrites rather than appending', () async {
      await cache.write(CacheDao.dashboardKey, <String, dynamic>{'streak': 5});
      await cache.write(CacheDao.dashboardKey, <String, dynamic>{'streak': 6});

      expect((await cache.read(CacheDao.dashboardKey))!.asMap['streak'], 6);
    });

    test('returns null for a key that was never written', () async {
      expect(await cache.read('nothing-here'), isNull);
    });

    test('deletes a whole prefix', () async {
      await cache.write(CacheDao.exerciseSearchKey('chest'), <dynamic>[]);
      await cache.write(CacheDao.exerciseSearchKey('back'), <dynamic>[]);
      await cache.write(CacheDao.dashboardKey, <String, dynamic>{});

      await cache.deletePrefix('exercises.');

      expect(await cache.read(CacheDao.exerciseSearchKey('chest')), isNull);
      expect(await cache.read(CacheDao.dashboardKey), isNotNull);
    });
  });

  group('sign-out', () {
    test('clears every local table', () async {
      await outbox.enqueue(
        clientUuid: 'op-1',
        entity: 'meal',
        payload: <String, dynamic>{},
      );
      await cache.write(CacheDao.dashboardKey, <String, dynamic>{});

      await database.clear();

      expect(await outbox.pendingCount(), 0);
      expect(await cache.read(CacheDao.dashboardKey), isNull);
    });
  });
}
