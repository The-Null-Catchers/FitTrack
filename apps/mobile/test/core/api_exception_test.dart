import 'package:dio/dio.dart';
import 'package:fittrack/core/network/api_exception.dart';
import 'package:flutter_test/flutter_test.dart';

RequestOptions _options() => RequestOptions(path: '/api/v1/workout-sessions');

void main() {
  group('error envelope', () {
    test('uses the human message the API returns', () {
      final ApiException error = ApiException.fromResponse(
        Response<dynamic>(
          requestOptions: _options(),
          statusCode: 409,
          data: <String, dynamic>{
            'error': <String, dynamic>{
              'code': 'workout_in_progress',
              'message': 'You already have a workout in progress.',
              'details': <String, dynamic>{'session_id': 'abc'},
              'request_id': 'req-1',
            },
          },
        ),
      );

      expect(error.code, 'workout_in_progress');
      expect(error.message, 'You already have a workout in progress.');
      expect(error.details['session_id'], 'abc');
      expect(error.requestId, 'req-1');
      expect(error.isConflict, isTrue);
    });

    test('falls back to a readable message for a non-JSON body', () {
      final ApiException error = ApiException.fromResponse(
        Response<dynamic>(
          requestOptions: _options(),
          statusCode: 502,
          data: '<html>Bad gateway</html>',
        ),
      );

      expect(error.isServerError, isTrue);
      expect(error.message, contains('try again'));
      // Never a bare status code.
      expect(error.message, isNot(contains('502')));
    });

    test('exposes field errors from a validation failure', () {
      final ApiException error = ApiException.fromResponse(
        Response<dynamic>(
          requestOptions: _options(),
          statusCode: 422,
          data: <String, dynamic>{
            'error': <String, dynamic>{
              'code': 'validation_error',
              'message': "Some of the information you entered isn't valid.",
              'details': <String, dynamic>{
                'fields': <String, dynamic>{'height_cm': 'must be greater than 50'},
              },
            },
          },
        ),
      );

      expect(error.fieldErrors['height_cm'], 'must be greater than 50');
    });
  });

  group('transport failures', () {
    test('a connection error is treated as connectivity, not a real failure', () {
      final ApiException error = ApiException.fromDio(
        DioException(
          requestOptions: _options(),
          type: DioExceptionType.connectionError,
        ),
      );

      expect(error.isConnectivity, isTrue);
      expect(error.message, contains('connection'));
    });

    test('a timeout is also connectivity, so the change can be queued', () {
      final ApiException error = ApiException.fromDio(
        DioException(
          requestOptions: _options(),
          type: DioExceptionType.receiveTimeout,
        ),
      );

      expect(error.isConnectivity, isTrue);
    });

    test('a 401 is not connectivity — it needs a sign-in, not a retry', () {
      final ApiException error = ApiException.fromDio(
        DioException(
          requestOptions: _options(),
          type: DioExceptionType.badResponse,
          response: Response<dynamic>(
            requestOptions: _options(),
            statusCode: 401,
          ),
        ),
      );

      expect(error.isUnauthorized, isTrue);
      expect(error.isConnectivity, isFalse);
    });
  });
}
