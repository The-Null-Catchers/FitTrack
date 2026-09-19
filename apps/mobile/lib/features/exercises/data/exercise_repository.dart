import '../../../core/database/cache_dao.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../domain/exercise.dart';

/// Exercise library access, cached so the browser works offline.
class ExerciseRepository {
  const ExerciseRepository(this._client, this._cache);

  final ApiClient _client;
  final CacheDao _cache;

  /// Search the library.
  ///
  /// The first page of every distinct search is cached; a network failure on
  /// page one falls back to that cache instead of showing an error, which is
  /// what lets the library be browsed on a train.
  Future<PagedResult<Exercise>> search(
    ExerciseFilters filters, {
    int page = 1,
    int perPage = 30,
  }) async {
    try {
      final Map<String, dynamic> body = await _client.get<Map<String, dynamic>>(
        '/api/v1/exercises',
        query: filters.toQuery(page: page, perPage: perPage),
      );
      if (page == 1) {
        await _cache.write(CacheDao.exerciseSearchKey(filters.cacheKey), body);
      }
      return PagedResult<Exercise>.fromJson<Exercise>(body, Exercise.fromJson);
    } on ApiException catch (error) {
      if (page == 1 && error.isConnectivity) {
        final CachedDocument? cached =
            await _cache.read(CacheDao.exerciseSearchKey(filters.cacheKey));
        if (cached != null) {
          return PagedResult<Exercise>.fromJson<Exercise>(
            cached.asMap,
            Exercise.fromJson,
          );
        }
      }
      rethrow;
    }
  }

  Future<Exercise> byId(String id) async {
    final Map<String, dynamic> body =
        await _client.get<Map<String, dynamic>>('/api/v1/exercises/$id');
    await _cache.write('exercise.$id', body);
    return Exercise.fromJson(body);
  }

  /// Detail with an offline fallback, for opening an exercise from a workout.
  Future<Exercise?> byIdCached(String id) async {
    try {
      return await byId(id);
    } on ApiException {
      final CachedDocument? cached = await _cache.read('exercise.$id');
      return cached == null ? null : Exercise.fromJson(cached.asMap);
    }
  }

  Future<Map<String, List<String>>> filterOptions() async {
    final Map<String, dynamic> body =
        await _client.get<Map<String, dynamic>>('/api/v1/exercises/filters');
    return body.map(
      (String key, dynamic value) => MapEntry<String, List<String>>(
        key,
        (value as List<dynamic>).map((dynamic item) => '$item').toList(),
      ),
    );
  }

  Future<Exercise> create(Map<String, dynamic> payload) async {
    final Map<String, dynamic> body = await _client.post<Map<String, dynamic>>(
      '/api/v1/exercises',
      data: payload,
    );
    await _cache.deletePrefix('exercises.');
    return Exercise.fromJson(body);
  }
}
