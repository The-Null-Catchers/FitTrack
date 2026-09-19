import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Token storage backed by the Keychain / EncryptedSharedPreferences.
///
/// Access and refresh tokens never touch `SharedPreferences` or the local
/// database — a rooted-device dump of either should not yield a session.
class SecureStorage {
  SecureStorage([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            );

  final FlutterSecureStorage _storage;

  static const String _accessTokenKey = 'fittrack.access_token';
  static const String _refreshTokenKey = 'fittrack.refresh_token';
  static const String _refreshExpiryKey = 'fittrack.refresh_expires_at';

  Future<String?> readAccessToken() => _storage.read(key: _accessTokenKey);

  Future<String?> readRefreshToken() => _storage.read(key: _refreshTokenKey);

  Future<DateTime?> readRefreshExpiry() async {
    final String? raw = await _storage.read(key: _refreshExpiryKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    DateTime? refreshExpiresAt,
  }) async {
    await Future.wait(<Future<void>>[
      _storage.write(key: _accessTokenKey, value: accessToken),
      _storage.write(key: _refreshTokenKey, value: refreshToken),
      if (refreshExpiresAt != null)
        _storage.write(
          key: _refreshExpiryKey,
          value: refreshExpiresAt.toIso8601String(),
        ),
    ]);
  }

  Future<void> clear() async {
    await Future.wait(<Future<void>>[
      _storage.delete(key: _accessTokenKey),
      _storage.delete(key: _refreshTokenKey),
      _storage.delete(key: _refreshExpiryKey),
    ]);
  }

  Future<bool> get hasSession async =>
      (await readRefreshToken())?.isNotEmpty ?? false;
}
