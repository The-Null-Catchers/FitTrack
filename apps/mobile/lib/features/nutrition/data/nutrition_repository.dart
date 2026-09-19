import '../../../core/database/cache_dao.dart';
import '../../../core/database/outbox_dao.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/formatters.dart';
import '../../exercises/domain/exercise.dart';
import '../domain/nutrition_models.dart';

class NutritionRepository {
  const NutritionRepository(this._client, this._cache, this._outbox);

  final ApiClient _client;
  final CacheDao _cache;
  final OutboxDao _outbox;

  Future<NutritionDay> day(DateTime date) async {
    final String iso = Formatters.isoDate(date);
    try {
      final Map<String, dynamic> body = await _client.get<Map<String, dynamic>>(
        '/api/v1/nutrition/day',
        query: <String, dynamic>{'on': iso},
      );
      await _cache.write(CacheDao.nutritionDayKey(iso), body);
      return NutritionDay.fromJson(body);
    } on ApiException catch (error) {
      if (!error.isConnectivity) rethrow;
      final CachedDocument? cached =
          await _cache.read(CacheDao.nutritionDayKey(iso));
      if (cached == null) rethrow;
      return NutritionDay.fromJson(cached.asMap);
    }
  }

  Future<PagedResult<Food>> searchFoods(
    String query, {
    int page = 1,
    bool favouritesOnly = false,
    bool customOnly = false,
  }) async {
    final Map<String, dynamic> body = await _client.get<Map<String, dynamic>>(
      '/api/v1/nutrition/foods',
      query: <String, dynamic>{
        'page': page,
        'per_page': 30,
        if (query.isNotEmpty) 'q': query,
        if (favouritesOnly) 'favorites_only': true,
        if (customOnly) 'custom_only': true,
      },
    );
    return PagedResult<Food>.fromJson<Food>(body, Food.fromJson);
  }

  Future<List<Food>> recentFoods() async {
    final List<dynamic> body =
        await _client.get<List<dynamic>>('/api/v1/nutrition/foods/recent');
    return body
        .map((dynamic item) =>
            Food.fromJson(Map<String, dynamic>.from(item as Map<dynamic, dynamic>)))
        .toList();
  }

  Future<Food?> byBarcode(String barcode) async {
    final Map<String, dynamic>? body = await _client
        .get<Map<String, dynamic>?>('/api/v1/nutrition/foods/barcode/$barcode');
    return body == null ? null : Food.fromJson(body);
  }

  Future<bool> toggleFavourite(String foodId) async {
    final Map<String, dynamic> body = await _client
        .post<Map<String, dynamic>>('/api/v1/nutrition/foods/$foodId/favorite');
    return body['is_favorite'] as bool? ?? false;
  }

  Future<Food> createFood(Map<String, dynamic> payload) async {
    final Map<String, dynamic> body = await _client.post<Map<String, dynamic>>(
      '/api/v1/nutrition/foods',
      data: payload,
    );
    return Food.fromJson(body);
  }

  /// Log a meal, falling back to the outbox when offline.
  Future<Meal?> logMeal({
    required DateTime loggedOn,
    required String mealType,
    required List<Map<String, dynamic>> items,
    required String clientUuid,
    String? name,
  }) async {
    final Map<String, dynamic> payload = <String, dynamic>{
      'logged_on': Formatters.isoDate(loggedOn),
      'meal_type': mealType,
      if (name != null) 'name': name,
      'items': items,
      'client_uuid': clientUuid,
    };
    try {
      final Map<String, dynamic> body = await _client.post<Map<String, dynamic>>(
        '/api/v1/nutrition/meals',
        data: payload,
      );
      await _invalidateDay(loggedOn);
      return Meal.fromJson(body);
    } on ApiException catch (error) {
      if (!error.isConnectivity) rethrow;
      await _outbox.enqueue(
        clientUuid: clientUuid,
        entity: 'meal',
        payload: payload,
      );
      return null;
    }
  }

  Future<void> deleteMeal(String id, DateTime loggedOn) async {
    await _client.delete<void>('/api/v1/nutrition/meals/$id');
    await _invalidateDay(loggedOn);
  }

  Future<int?> logWater({
    required DateTime loggedOn,
    required int amountMl,
    required String clientUuid,
  }) async {
    final Map<String, dynamic> payload = <String, dynamic>{
      'logged_on': Formatters.isoDate(loggedOn),
      'amount_ml': amountMl,
      'client_uuid': clientUuid,
    };
    try {
      final Map<String, dynamic> body = await _client.post<Map<String, dynamic>>(
        '/api/v1/nutrition/water',
        data: payload,
      );
      await _invalidateDay(loggedOn);
      return body['water_ml'] as int?;
    } on ApiException catch (error) {
      if (!error.isConnectivity) rethrow;
      await _outbox.enqueue(
        clientUuid: clientUuid,
        entity: 'water_log',
        payload: payload,
      );
      return null;
    }
  }

  Future<void> _invalidateDay(DateTime date) async {
    await _cache.delete(CacheDao.nutritionDayKey(Formatters.isoDate(date)));
    await _cache.delete(CacheDao.dashboardKey);
  }
}
