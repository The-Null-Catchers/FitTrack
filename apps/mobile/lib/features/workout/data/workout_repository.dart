import '../../../core/database/active_session_dao.dart';
import '../../../core/database/cache_dao.dart';
import '../../../core/database/outbox_dao.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../exercises/domain/exercise.dart';
import '../domain/workout_models.dart';

/// Workout persistence.
///
/// The device is the source of truth while a workout is in progress: every
/// change is written to [ActiveSessionDao] immediately, and the server is told
/// about the session when it is finished. That ordering is what makes a
/// workout survive a dead battery, a tunnel or a force-quit.
class WorkoutRepository {
  const WorkoutRepository(
    this._client,
    this._activeSessions,
    this._outbox,
    this._cache,
  );

  final ApiClient _client;
  final ActiveSessionDao _activeSessions;
  final OutboxDao _outbox;
  final CacheDao _cache;

  // --- local session state -------------------------------------------------

  Future<WorkoutSession?> readActiveLocal() async {
    final Map<String, dynamic>? payload = await _activeSessions.read();
    return payload == null ? null : WorkoutSession.fromJson(payload);
  }

  Future<void> saveActiveLocal(WorkoutSession session) =>
      _activeSessions.save(session.localId, session.toJson());

  Future<void> clearActiveLocal() => _activeSessions.clear();

  // --- server ---------------------------------------------------------------

  /// Register the session server-side so previous-performance and progression
  /// hints can be attached. Idempotent on `client_uuid`.
  Future<WorkoutSession> startRemote(WorkoutSession session) async {
    final Map<String, dynamic> body = await _client.post<Map<String, dynamic>>(
      '/api/v1/workout-sessions',
      data: <String, dynamic>{
        if (session.programId != null) 'program_id': session.programId,
        if (session.dayId != null) 'day_id': session.dayId,
        'name': session.name,
        'started_at': session.startedAt.toUtc().toIso8601String(),
        'client_uuid': session.localId,
        if (session.dayId == null)
          'exercises': session.exercises
              .map((SessionExercise item) => item.toSyncJson())
              .toList(),
      },
    );
    return WorkoutSession.fromJson(body);
  }

  /// Push the finished workout and return it with any personal records.
  Future<WorkoutSession> finishRemote(WorkoutSession session) async {
    final WorkoutSession remote = await startRemote(session);
    final Map<String, dynamic> body = await _client.post<Map<String, dynamic>>(
      '/api/v1/workout-sessions/${remote.id}/finish',
      data: <String, dynamic>{
        if (session.completedAt != null)
          'completed_at': session.completedAt!.toUtc().toIso8601String(),
        if (session.durationSeconds != null)
          'duration_seconds': session.durationSeconds,
        if (session.notes != null) 'notes': session.notes,
        if (session.perceivedEffort != null)
          'perceived_effort': session.perceivedEffort,
        'exercises': session.exercises
            .map((SessionExercise item) => item.toSyncJson())
            .toList(),
      },
    );
    await _cache.delete(CacheDao.workoutHistoryKey);
    await _cache.delete(CacheDao.dashboardKey);
    return WorkoutSession.fromJson(body);
  }

  /// Queue a finished workout for the next sync window.
  Future<void> enqueueFinished(WorkoutSession session) => _outbox.enqueue(
        clientUuid: session.localId,
        entity: 'workout_session',
        payload: session.toSyncPayload(),
      );

  /// What the user did with this exercise last time, for the "Previous" column.
  Future<PreviousPerformance?> previousPerformance(String exerciseId) async {
    try {
      final Map<String, dynamic>? body = await _client
          .get<Map<String, dynamic>?>(
              '/api/v1/workout-sessions/exercises/$exerciseId/previous');
      return body == null ? null : PreviousPerformance.fromJson(body);
    } on ApiException {
      return null;
    }
  }

  Future<PagedResult<WorkoutSession>> history({
    int page = 1,
    int perPage = 20,
    DateTime? startDate,
    DateTime? endDate,
    String? exerciseId,
  }) async {
    try {
      final Map<String, dynamic> body = await _client.get<Map<String, dynamic>>(
        '/api/v1/workout-sessions',
        query: <String, dynamic>{
          'page': page,
          'per_page': perPage,
          if (startDate != null)
            'start_date': startDate.toIso8601String().split('T').first,
          if (endDate != null)
            'end_date': endDate.toIso8601String().split('T').first,
          if (exerciseId != null) 'exercise_id': exerciseId,
        },
      );
      if (page == 1 && startDate == null && exerciseId == null) {
        await _cache.write(CacheDao.workoutHistoryKey, body);
      }
      return PagedResult<WorkoutSession>.fromJson<WorkoutSession>(
        body,
        WorkoutSession.fromJson,
      );
    } on ApiException catch (error) {
      if (page == 1 && error.isConnectivity) {
        final CachedDocument? cached =
            await _cache.read(CacheDao.workoutHistoryKey);
        if (cached != null) {
          return PagedResult<WorkoutSession>.fromJson<WorkoutSession>(
            cached.asMap,
            WorkoutSession.fromJson,
          );
        }
      }
      rethrow;
    }
  }

  Future<WorkoutSession> sessionDetail(String id) async {
    final Map<String, dynamic> body = await _client
        .get<Map<String, dynamic>>('/api/v1/workout-sessions/$id');
    return WorkoutSession.fromJson(body);
  }

  Future<void> deleteSession(String id) async {
    await _client.delete<void>('/api/v1/workout-sessions/$id');
    await _cache.delete(CacheDao.workoutHistoryKey);
  }

  /// Discard an in-progress workout on both sides.
  Future<void> discard(WorkoutSession session) async {
    await clearActiveLocal();
    await _outbox.discard(session.localId);
    if (session.id != null) {
      try {
        await _client.post<void>('/api/v1/workout-sessions/${session.id}/discard');
      } on ApiException {
        // The local session is gone either way; a stale in-progress row on the
        // server is closed by the worker's stale-session job.
      }
    }
  }

  Future<List<PersonalRecord>> personalRecords({String? exerciseId}) async {
    try {
      final List<dynamic> body = await _client.get<List<dynamic>>(
        '/api/v1/personal-records',
        query: <String, dynamic>{
          if (exerciseId != null) 'exercise_id': exerciseId,
          'limit': 100,
        },
      );
      await _cache.write(CacheDao.recordsKey, body);
      return body
          .map((dynamic item) => PersonalRecord.fromJson(
              Map<String, dynamic>.from(item as Map<dynamic, dynamic>)))
          .toList();
    } on ApiException catch (error) {
      if (error.isConnectivity) {
        final CachedDocument? cached = await _cache.read(CacheDao.recordsKey);
        if (cached != null) {
          return cached.asList
              .map((dynamic item) => PersonalRecord.fromJson(
                  Map<String, dynamic>.from(item as Map<dynamic, dynamic>)))
              .toList();
        }
      }
      rethrow;
    }
  }

  Future<void> acknowledgeRecords(List<String> ids) async {
    if (ids.isEmpty) return;
    try {
      await _client.post<Map<String, dynamic>>(
        '/api/v1/personal-records/acknowledge',
        data: <String, dynamic>{'ids': ids},
      );
    } on ApiException {
      // Purely cosmetic; not worth surfacing or retrying.
    }
  }

  Future<List<Exercise>> trainedExercises() async {
    final List<dynamic> body =
        await _client.get<List<dynamic>>('/api/v1/progress/exercises');
    return body
        .map((dynamic item) => Exercise.fromJson(
            Map<String, dynamic>.from(item as Map<dynamic, dynamic>)))
        .toList();
  }
}
