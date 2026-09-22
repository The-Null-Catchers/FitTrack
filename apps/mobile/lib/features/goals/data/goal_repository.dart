import '../../../core/database/cache_dao.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../domain/goal.dart';

class GoalRepository {
  const GoalRepository(this._client, this._cache);

  final ApiClient _client;
  final CacheDao _cache;

  Future<List<Goal>> list({String? status}) async {
    try {
      final List<dynamic> body = await _client.get<List<dynamic>>(
        '/api/v1/goals',
        query: <String, dynamic>{if (status != null) 'status': status},
      );
      if (status == null) {
        await _cache.write(CacheDao.goalsKey, body);
      }
      return body
          .map((dynamic item) => Goal.fromJson(
              Map<String, dynamic>.from(item as Map<dynamic, dynamic>)))
          .toList();
    } on ApiException catch (error) {
      if (!error.isConnectivity) rethrow;
      final CachedDocument? cached = await _cache.read(CacheDao.goalsKey);
      if (cached == null) rethrow;
      return cached.asList
          .map((dynamic item) => Goal.fromJson(
              Map<String, dynamic>.from(item as Map<dynamic, dynamic>)))
          .toList();
    }
  }

  Future<Goal> create(Map<String, dynamic> payload) async {
    final Map<String, dynamic> body = await _client
        .post<Map<String, dynamic>>('/api/v1/goals', data: payload);
    await _cache.delete(CacheDao.goalsKey);
    return Goal.fromJson(body);
  }

  Future<Goal> update(String id, Map<String, dynamic> changes) async {
    final Map<String, dynamic> body = await _client.patch<Map<String, dynamic>>(
      '/api/v1/goals/$id',
      data: changes,
    );
    await _cache.delete(CacheDao.goalsKey);
    return Goal.fromJson(body);
  }

  Future<void> delete(String id) async {
    await _client.delete<void>('/api/v1/goals/$id');
    await _cache.delete(CacheDao.goalsKey);
  }
}
