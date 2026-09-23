import '../../../core/database/cache_dao.dart';
import '../../../core/database/outbox_dao.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/formatters.dart';
import '../domain/habit.dart';

class HabitRepository {
  const HabitRepository(this._client, this._cache, this._outbox);

  final ApiClient _client;
  final CacheDao _cache;
  final OutboxDao _outbox;

  Future<List<Habit>> list() async {
    try {
      final List<dynamic> body =
          await _client.get<List<dynamic>>('/api/v1/habits');
      await _cache.write(CacheDao.habitsKey, body);
      return body
          .map((dynamic item) => Habit.fromJson(
              Map<String, dynamic>.from(item as Map<dynamic, dynamic>)))
          .toList();
    } on ApiException catch (error) {
      if (!error.isConnectivity) rethrow;
      final CachedDocument? cached = await _cache.read(CacheDao.habitsKey);
      if (cached == null) rethrow;
      return cached.asList
          .map((dynamic item) => Habit.fromJson(
              Map<String, dynamic>.from(item as Map<dynamic, dynamic>)))
          .toList();
    }
  }

  Future<Habit> create({
    required String name,
    String icon = 'check_circle',
    String frequency = 'daily',
    int targetCount = 1,
    String? reminderTime,
    List<int> activeWeekdays = const <int>[],
  }) async {
    final Map<String, dynamic> body = await _client.post<Map<String, dynamic>>(
      '/api/v1/habits',
      data: <String, dynamic>{
        'name': name,
        'icon': icon,
        'frequency': frequency,
        'target_count': targetCount,
        if (reminderTime != null) 'reminder_time': reminderTime,
        'active_weekdays': activeWeekdays,
      },
    );
    await _cache.delete(CacheDao.habitsKey);
    return Habit.fromJson(body);
  }

  Future<Habit?> log({
    required String habitId,
    required DateTime loggedOn,
    required int count,
    required String clientUuid,
  }) async {
    final Map<String, dynamic> payload = <String, dynamic>{
      'logged_on': Formatters.isoDate(loggedOn),
      'count': count,
      'client_uuid': clientUuid,
    };
    try {
      final Map<String, dynamic> body =
          await _client.post<Map<String, dynamic>>(
        '/api/v1/habits/$habitId/log',
        data: payload,
      );
      await _cache.delete(CacheDao.habitsKey);
      await _cache.delete(CacheDao.dashboardKey);
      return Habit.fromJson(body);
    } on ApiException catch (error) {
      if (!error.isConnectivity) rethrow;
      await _outbox.enqueue(
        clientUuid: clientUuid,
        entity: 'habit_log',
        payload: <String, dynamic>{...payload, 'habit_id': habitId},
      );
      return null;
    }
  }

  Future<Habit> unlog(String habitId, DateTime loggedOn) async {
    final Map<String, dynamic> body =
        await _client.delete<Map<String, dynamic>>(
      '/api/v1/habits/$habitId/log',
      data: <String, dynamic>{'on': Formatters.isoDate(loggedOn)},
    );
    await _cache.delete(CacheDao.habitsKey);
    return Habit.fromJson(body);
  }

  Future<void> delete(String habitId) async {
    await _client.delete<void>('/api/v1/habits/$habitId');
    await _cache.delete(CacheDao.habitsKey);
  }
}
