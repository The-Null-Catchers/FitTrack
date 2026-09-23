/// Build-time configuration.
///
/// Values come from `--dart-define`, so no endpoint or key is compiled into
/// the source tree:
///
/// ```
/// flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
/// ```
class Env {
  const Env._();

  /// Base URL of the FitTrack API.
  ///
  /// The default targets the Android emulator's host loopback, which is the
  /// address a developer running `docker compose up` actually needs.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  static const String appPublicUrl = String.fromEnvironment(
    'APP_PUBLIC_URL',
    defaultValue: 'https://fittrack.app',
  );

  static const String sentryDsn = String.fromEnvironment('SENTRY_DSN');

  /// Extra logging and the debug banner, off in release builds.
  static const bool verboseLogging = bool.fromEnvironment(
    'VERBOSE_LOGGING',
    defaultValue: false,
  );

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 30);

  /// How long an unsynced change may sit in the outbox before we surface it.
  static const Duration syncStaleAfter = Duration(hours: 6);

  static String get apiV1 => '$apiBaseUrl/api/v1';
}
