import 'dart:io';

import 'package:dio/dio.dart';

import '../../../core/database/cache_dao.dart';
import '../../../core/database/outbox_dao.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/formatters.dart';
import '../../exercises/domain/exercise.dart';
import '../domain/progress_models.dart';

/// Dashboard, body tracking, photos and analytics.
class ProgressRepository {
  const ProgressRepository(this._client, this._cache, this._outbox);

  final ApiClient _client;
  final CacheDao _cache;
  final OutboxDao _outbox;

  // --- dashboard -----------------------------------------------------------

  /// The home dashboard, with the last successful response as a fallback so a
  /// cold start offline still shows something real.
  Future<DashboardData> dashboard() async {
    try {
      final Map<String, dynamic> body =
          await _client.get<Map<String, dynamic>>('/api/v1/progress/dashboard');
      await _cache.write(CacheDao.dashboardKey, body);
      return DashboardData.fromJson(body);
    } on ApiException catch (error) {
      if (!error.isConnectivity) rethrow;
      final CachedDocument? cached = await _cache.read(CacheDao.dashboardKey);
      if (cached == null) rethrow;
      return DashboardData.fromJson(cached.asMap);
    }
  }

  // --- body weight ---------------------------------------------------------

  Future<List<BodyWeightEntry>> weights({DateTime? from, DateTime? to}) async {
    final List<dynamic> body = await _client.get<List<dynamic>>(
      '/api/v1/progress/weights',
      query: <String, dynamic>{
        if (from != null) 'start_date': Formatters.isoDate(from),
        if (to != null) 'end_date': Formatters.isoDate(to),
      },
    );
    return body
        .map((dynamic item) => BodyWeightEntry.fromJson(
            Map<String, dynamic>.from(item as Map<dynamic, dynamic>)))
        .toList();
  }

  /// Log a weigh-in. Queued locally when offline so the entry is never lost.
  Future<void> logWeight({
    required DateTime recordedOn,
    required double weightKg,
    double? bodyFatPercent,
    String? note,
    required String clientUuid,
  }) async {
    final Map<String, dynamic> payload = <String, dynamic>{
      'recorded_on': Formatters.isoDate(recordedOn),
      'weight_kg': weightKg,
      if (bodyFatPercent != null) 'body_fat_percent': bodyFatPercent,
      if (note != null && note.isNotEmpty) 'note': note,
      'client_uuid': clientUuid,
    };
    try {
      await _client.post<Map<String, dynamic>>(
        '/api/v1/progress/weights',
        data: payload,
      );
      await _cache.delete(CacheDao.dashboardKey);
    } on ApiException catch (error) {
      if (!error.isConnectivity) rethrow;
      await _outbox.enqueue(
        clientUuid: clientUuid,
        entity: 'body_weight',
        payload: payload,
      );
    }
  }

  Future<void> deleteWeight(String id) =>
      _client.delete<void>('/api/v1/progress/weights/$id');

  // --- measurements --------------------------------------------------------

  Future<List<MeasurementEntry>> measurements({String? type}) async {
    final List<dynamic> body = await _client.get<List<dynamic>>(
      '/api/v1/progress/measurements',
      query: <String, dynamic>{if (type != null) 'measurement_type': type},
    );
    return body
        .map((dynamic item) => MeasurementEntry.fromJson(
            Map<String, dynamic>.from(item as Map<dynamic, dynamic>)))
        .toList();
  }

  Future<void> logMeasurement({
    required DateTime recordedOn,
    required String measurementType,
    required double valueCm,
    String? customLabel,
    required String clientUuid,
  }) async {
    final Map<String, dynamic> payload = <String, dynamic>{
      'recorded_on': Formatters.isoDate(recordedOn),
      'measurement_type': measurementType,
      'value_cm': valueCm,
      if (customLabel != null) 'custom_label': customLabel,
      'client_uuid': clientUuid,
    };
    try {
      await _client.post<Map<String, dynamic>>(
        '/api/v1/progress/measurements',
        data: payload,
      );
    } on ApiException catch (error) {
      if (!error.isConnectivity) rethrow;
      await _outbox.enqueue(
        clientUuid: clientUuid,
        entity: 'body_measurement',
        payload: payload,
      );
    }
  }

  Future<void> deleteMeasurement(String id) =>
      _client.delete<void>('/api/v1/progress/measurements/$id');

  // --- progress photos -----------------------------------------------------

  /// Photos are private: the API returns short-lived signed URLs, which is why
  /// this list is never cached to disk.
  Future<List<ProgressPhoto>> photos({String? pose}) async {
    final List<dynamic> body = await _client.get<List<dynamic>>(
      '/api/v1/progress/photos',
      query: <String, dynamic>{if (pose != null) 'pose': pose},
    );
    return body
        .map((dynamic item) => ProgressPhoto.fromJson(
            Map<String, dynamic>.from(item as Map<dynamic, dynamic>)))
        .toList();
  }

  Future<ProgressPhoto> uploadPhoto({
    required File file,
    required DateTime takenOn,
    required String pose,
    double? weightKg,
    String? note,
  }) async {
    final FormData form = FormData.fromMap(<String, dynamic>{
      'file': await MultipartFile.fromFile(file.path),
      'taken_on': Formatters.isoDate(takenOn),
      'pose': pose,
      if (weightKg != null) 'weight_kg': weightKg,
      if (note != null && note.isNotEmpty) 'note': note,
    });
    final Map<String, dynamic> body =
        await _client.upload<Map<String, dynamic>>(
      '/api/v1/progress/photos',
      form,
    );
    return ProgressPhoto.fromJson(body);
  }

  Future<void> deletePhoto(String id) =>
      _client.delete<void>('/api/v1/progress/photos/$id');

  Future<Map<String, dynamic>> comparePhotos(String beforeId, String afterId) =>
      _client.get<Map<String, dynamic>>(
        '/api/v1/progress/photos/compare',
        query: <String, dynamic>{'before_id': beforeId, 'after_id': afterId},
      );

  // --- charts --------------------------------------------------------------

  Future<ChartData> weightChart(String range) async {
    final Map<String, dynamic> body = await _client.get<Map<String, dynamic>>(
      '/api/v1/progress/charts/weight',
      query: <String, dynamic>{'range': range},
    );
    await _cache.write('chart.weight.$range', body);
    return ChartData.fromJson(body);
  }

  Future<ChartData> volumeChart(String range) async {
    final Map<String, dynamic> body = await _client.get<Map<String, dynamic>>(
      '/api/v1/progress/charts/volume',
      query: <String, dynamic>{'range': range},
    );
    return ChartData.fromJson(body);
  }

  Future<ChartData> nutritionChart(String range) async {
    final Map<String, dynamic> body = await _client.get<Map<String, dynamic>>(
      '/api/v1/progress/charts/nutrition',
      query: <String, dynamic>{'range': range},
    );
    return ChartData.fromJson(body);
  }

  Future<ChartData> measurementChart(String type, String range) async {
    final Map<String, dynamic> body = await _client.get<Map<String, dynamic>>(
      '/api/v1/progress/charts/measurements',
      query: <String, dynamic>{'measurement_type': type, 'range': range},
    );
    return ChartData.fromJson(body);
  }

  Future<ExerciseProgress> exerciseProgress(
      String exerciseId, String range) async {
    final Map<String, dynamic> body = await _client.get<Map<String, dynamic>>(
      '/api/v1/progress/exercises/$exerciseId',
      query: <String, dynamic>{'range': range},
    );
    return ExerciseProgress.fromJson(body);
  }

  Future<TrainingOverview> overview(String range) async {
    final Map<String, dynamic> body = await _client.get<Map<String, dynamic>>(
      '/api/v1/progress/overview',
      query: <String, dynamic>{'range': range},
    );
    return TrainingOverview.fromJson(body);
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
