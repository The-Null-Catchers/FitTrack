import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/env.dart';
import '../storage/secure_storage.dart';
import 'api_exception.dart';

/// Called when the refresh token is rejected and the session is unrecoverable.
typedef SessionExpiredCallback = void Function();

/// Thin wrapper over Dio.
///
/// Responsibilities kept here so no repository has to think about them:
/// attaching the access token, refreshing it exactly once when it expires
/// (queuing concurrent callers behind the single refresh), and converting
/// every failure into an [ApiException] with a message fit for the screen.
class ApiClient {
  ApiClient({
    required SecureStorage storage,
    Dio? dio,
    this.onSessionExpired,
  })  : _storage = storage,
        _dio = dio ?? Dio() {
    _dio.options
      ..baseUrl = Env.apiBaseUrl
      ..connectTimeout = Env.connectTimeout
      ..receiveTimeout = Env.receiveTimeout
      ..headers = <String, dynamic>{'Accept': 'application/json'}
      ..validateStatus = (int? status) => status != null && status < 400;

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: _onRequest,
        onError: _onError,
      ),
    );

    if (kDebugMode && Env.verboseLogging) {
      _dio.interceptors.add(
        LogInterceptor(
            requestBody: true, responseBody: true, requestHeader: false),
      );
    }
  }

  final Dio _dio;
  final SecureStorage _storage;
  final SessionExpiredCallback? onSessionExpired;

  /// In-flight refresh, so ten parallel 401s cause one refresh, not ten.
  Future<bool>? _refreshInFlight;

  Dio get raw => _dio;

  /// Endpoints that must never carry a stale access token or trigger a refresh.
  static const Set<String> _unauthenticatedPaths = <String>{
    '/api/v1/auth/login',
    '/api/v1/auth/register',
    '/api/v1/auth/refresh',
    '/api/v1/auth/forgot-password',
    '/api/v1/auth/reset-password',
  };

  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (!_unauthenticatedPaths.contains(options.path)) {
      final String? token = await _storage.readAccessToken();
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    handler.next(options);
  }

  Future<void> _onError(
    DioException error,
    ErrorInterceptorHandler handler,
  ) async {
    final RequestOptions request = error.requestOptions;
    final bool retryable = error.response?.statusCode == 401 &&
        !_unauthenticatedPaths.contains(request.path) &&
        request.extra['retried'] != true;

    if (!retryable) {
      handler.next(error);
      return;
    }

    final bool refreshed = await _refreshTokens();
    if (!refreshed) {
      await _storage.clear();
      onSessionExpired?.call();
      handler.next(error);
      return;
    }

    try {
      request.extra['retried'] = true;
      final String? token = await _storage.readAccessToken();
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      final Response<dynamic> response = await _dio.fetch<dynamic>(request);
      handler.resolve(response);
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  Future<bool> _refreshTokens() {
    return _refreshInFlight ??= _performRefresh().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<bool> _performRefresh() async {
    final String? refreshToken = await _storage.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return false;

    try {
      // A bare Dio instance: the interceptors above must not recurse.
      final Response<dynamic> response = await Dio(
        BaseOptions(
            baseUrl: Env.apiBaseUrl, connectTimeout: Env.connectTimeout),
      ).post<dynamic>(
        '/api/v1/auth/refresh',
        data: <String, dynamic>{'refresh_token': refreshToken},
      );

      final Map<String, dynamic> body = Map<String, dynamic>.from(
        response.data as Map<dynamic, dynamic>,
      );
      await _storage.saveTokens(
        accessToken: body['access_token'] as String,
        refreshToken: body['refresh_token'] as String,
        refreshExpiresAt: DateTime.tryParse('${body['refresh_expires_at']}'),
      );
      return true;
    } on DioException {
      return false;
    }
  }

  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) =>
      _send<T>(() =>
          _dio.get<T>(path, queryParameters: query, cancelToken: cancelToken));

  Future<T> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) =>
      _send<T>(
        () => _dio.post<T>(
          path,
          data: data,
          queryParameters: query,
          cancelToken: cancelToken,
        ),
      );

  Future<T> patch<T>(String path, {Object? data}) =>
      _send<T>(() => _dio.patch<T>(path, data: data));

  Future<T> put<T>(String path, {Object? data}) =>
      _send<T>(() => _dio.put<T>(path, data: data));

  Future<T> delete<T>(String path, {Object? data}) =>
      _send<T>(() => _dio.delete<T>(path, data: data));

  Future<T> upload<T>(String path, FormData form) => _send<T>(
        () => _dio.post<T>(
          path,
          data: form,
          options: Options(contentType: 'multipart/form-data'),
        ),
      );

  Future<T> _send<T>(Future<Response<T>> Function() call) async {
    try {
      final Response<T> response = await call();
      return response.data as T;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}
