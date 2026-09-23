import 'package:dio/dio.dart';

/// A failure the UI can render directly.
///
/// The API returns human-readable messages in a uniform envelope; anything
/// that doesn't (a timeout, a DNS failure) is mapped to a message written for
/// the same audience. No screen should ever show "Error 500".
class ApiException implements Exception {
  const ApiException({
    required this.message,
    required this.code,
    this.statusCode,
    this.details = const <String, dynamic>{},
    this.requestId,
  });

  final String message;
  final String code;
  final int? statusCode;
  final Map<String, dynamic> details;
  final String? requestId;

  /// True when the request never reached the server — the caller can queue the
  /// change for later instead of reporting a failure.
  bool get isConnectivity =>
      code == 'network_error' || code == 'timeout' || code == 'offline';

  bool get isUnauthorized => statusCode == 401;

  bool get isForbidden => statusCode == 403;

  bool get isNotFound => statusCode == 404;

  bool get isConflict => statusCode == 409;

  bool get isServerError => (statusCode ?? 0) >= 500;

  /// Field-level validation messages, keyed by field name.
  Map<String, String> get fieldErrors {
    final Object? fields = details['fields'];
    if (fields is Map) {
      return fields.map(
        (Object? key, Object? value) =>
            MapEntry<String, String>('$key', '$value'),
      );
    }
    return const <String, String>{};
  }

  factory ApiException.fromDio(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const ApiException(
          message: 'That took too long. Please try again.',
          code: 'timeout',
        );
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return const ApiException(
          message:
              "We couldn't reach FitTrack. Check your connection and try again.",
          code: 'network_error',
        );
      case DioExceptionType.cancel:
        return const ApiException(
            message: 'Request cancelled.', code: 'cancelled');
      case DioExceptionType.badCertificate:
        return const ApiException(
          message: "We couldn't establish a secure connection.",
          code: 'bad_certificate',
        );
      case DioExceptionType.badResponse:
        return ApiException.fromResponse(error.response);
    }
  }

  factory ApiException.fromResponse(Response<dynamic>? response) {
    final int? status = response?.statusCode;
    final dynamic body = response?.data;

    if (body is Map && body['error'] is Map) {
      final Map<dynamic, dynamic> envelope =
          body['error'] as Map<dynamic, dynamic>;
      return ApiException(
        message: '${envelope['message'] ?? _defaultMessage(status)}',
        code: '${envelope['code'] ?? 'error'}',
        statusCode: status,
        details: Map<String, dynamic>.from(
          (envelope['details'] as Map<dynamic, dynamic>?) ??
              <dynamic, dynamic>{},
        ),
        requestId: envelope['request_id'] as String?,
      );
    }

    return ApiException(
      message: _defaultMessage(status),
      code: 'http_error',
      statusCode: status,
    );
  }

  static String _defaultMessage(int? status) {
    if (status == null) {
      return 'Something went wrong. Please try again.';
    }
    return switch (status) {
      401 => 'Please sign in to continue.',
      403 => "You don't have access to that.",
      404 => "We couldn't find what you were looking for.",
      429 => "You're doing that a little too often. Please try again shortly.",
      >= 500 =>
        'FitTrack is having a problem right now. Please try again shortly.',
      _ => 'Something went wrong. Please try again.',
    };
  }

  @override
  String toString() => 'ApiException($code, $statusCode): $message';
}
