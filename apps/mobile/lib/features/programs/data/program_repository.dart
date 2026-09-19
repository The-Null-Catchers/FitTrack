import '../../../core/database/cache_dao.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../exercises/domain/exercise.dart';
import '../domain/program.dart';

/// Program and template access, cached so a plan can be opened offline.
class ProgramRepository {
  const ProgramRepository(this._client, this._cache);

  final ApiClient _client;
  final CacheDao _cache;

  Future<Program?> active() async {
    try {
      final Map<String, dynamic>? body = await _client
          .get<Map<String, dynamic>?>('/api/v1/programs/active');
      if (body == null) {
        await _cache.delete(CacheDao.activeProgramKey);
        return null;
      }
      await _cache.write(CacheDao.activeProgramKey, body);
      return Program.fromJson(body);
    } on ApiException catch (error) {
      if (!error.isConnectivity) rethrow;
      final CachedDocument? cached = await _cache.read(CacheDao.activeProgramKey);
      return cached == null ? null : Program.fromJson(cached.asMap);
    }
  }

  Future<PagedResult<Program>> mine({int page = 1, String? status}) async {
    try {
      final Map<String, dynamic> body = await _client.get<Map<String, dynamic>>(
        '/api/v1/programs',
        query: <String, dynamic>{
          'page': page,
          'per_page': 20,
          if (status != null) 'status': status,
        },
      );
      if (page == 1 && status == null) {
        await _cache.write(CacheDao.programsKey, body);
      }
      return PagedResult<Program>.fromJson<Program>(body, Program.fromJson);
    } on ApiException catch (error) {
      if (page == 1 && error.isConnectivity) {
        final CachedDocument? cached = await _cache.read(CacheDao.programsKey);
        if (cached != null) {
          return PagedResult<Program>.fromJson<Program>(
            cached.asMap,
            Program.fromJson,
          );
        }
      }
      rethrow;
    }
  }

  Future<List<Program>> templates({bool featuredOnly = false}) async {
    try {
      final List<dynamic> body = await _client.get<List<dynamic>>(
        '/api/v1/programs/templates',
        query: <String, dynamic>{if (featuredOnly) 'featured_only': true},
      );
      if (!featuredOnly) {
        await _cache.write(CacheDao.templatesKey, body);
      }
      return body
          .map((dynamic item) => Program.fromJson(
              Map<String, dynamic>.from(item as Map<dynamic, dynamic>)))
          .toList();
    } on ApiException catch (error) {
      if (!error.isConnectivity) rethrow;
      final CachedDocument? cached = await _cache.read(CacheDao.templatesKey);
      if (cached == null) rethrow;
      return cached.asList
          .map((dynamic item) => Program.fromJson(
              Map<String, dynamic>.from(item as Map<dynamic, dynamic>)))
          .toList();
    }
  }

  Future<Program> byId(String id) async {
    try {
      final Map<String, dynamic> body =
          await _client.get<Map<String, dynamic>>('/api/v1/programs/$id');
      await _cache.write('program.$id', body);
      return Program.fromJson(body);
    } on ApiException catch (error) {
      if (!error.isConnectivity) rethrow;
      final CachedDocument? cached = await _cache.read('program.$id');
      if (cached == null) rethrow;
      return Program.fromJson(cached.asMap);
    }
  }

  Future<Program> duplicate(String id, {String? name}) async {
    final Map<String, dynamic> body = await _client.post<Map<String, dynamic>>(
      '/api/v1/programs/$id/duplicate',
      data: <String, dynamic>{if (name != null) 'name': name},
    );
    await _invalidate();
    return Program.fromJson(body);
  }

  Future<Program> activate(String id) async {
    final Map<String, dynamic> body = await _client
        .post<Map<String, dynamic>>('/api/v1/programs/$id/activate');
    await _invalidate();
    return Program.fromJson(body);
  }

  Future<Program> archive(String id) async {
    final Map<String, dynamic> body =
        await _client.post<Map<String, dynamic>>('/api/v1/programs/$id/archive');
    await _invalidate();
    return Program.fromJson(body);
  }

  Future<void> delete(String id) async {
    await _client.delete<void>('/api/v1/programs/$id');
    await _invalidate();
  }

  Future<Program> create(Map<String, dynamic> payload) async {
    final Map<String, dynamic> body = await _client.post<Map<String, dynamic>>(
      '/api/v1/programs',
      data: payload,
    );
    await _invalidate();
    return Program.fromJson(body);
  }

  Future<Program> rename(String id, String name) async {
    final Map<String, dynamic> body = await _client.patch<Map<String, dynamic>>(
      '/api/v1/programs/$id',
      data: <String, dynamic>{'name': name},
    );
    await _invalidate();
    return Program.fromJson(body);
  }

  Future<Program> addExerciseToDay(
    String dayId, {
    required String exerciseId,
    int targetSets = 3,
    int? targetRepsMin,
    int? targetRepsMax,
    int restSeconds = 90,
  }) async {
    final Map<String, dynamic> body = await _client.post<Map<String, dynamic>>(
      '/api/v1/programs/days/$dayId/exercises',
      data: <String, dynamic>{
        'exercise_id': exerciseId,
        'target_sets': targetSets,
        if (targetRepsMin != null) 'target_reps_min': targetRepsMin,
        if (targetRepsMax != null) 'target_reps_max': targetRepsMax,
        'rest_seconds': restSeconds,
      },
    );
    await _invalidate();
    return Program.fromJson(body);
  }

  Future<Program> removeDayExercise(String itemId) async {
    final Map<String, dynamic> body = await _client
        .delete<Map<String, dynamic>>('/api/v1/programs/day-exercises/$itemId');
    await _invalidate();
    return Program.fromJson(body);
  }

  Future<Program> reorderDayExercises(String dayId, List<String> ids) async {
    final Map<String, dynamic> body = await _client.post<Map<String, dynamic>>(
      '/api/v1/programs/days/$dayId/exercises/reorder',
      data: <String, dynamic>{'ids': ids},
    );
    await _invalidate();
    return Program.fromJson(body);
  }

  Future<void> _invalidate() async {
    await _cache.delete(CacheDao.programsKey);
    await _cache.delete(CacheDao.activeProgramKey);
    await _cache.delete(CacheDao.dashboardKey);
  }
}
