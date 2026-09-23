import '../../../core/network/api_client.dart';
import '../../../core/storage/secure_storage.dart';
import '../domain/auth_models.dart';

/// All calls under `/api/v1/auth` plus the profile endpoints the session needs.
class AuthRepository {
  const AuthRepository(this._client, this._storage);

  final ApiClient _client;
  final SecureStorage _storage;

  Future<AuthSession> register({
    required String email,
    required String password,
    required String fullName,
    String locale = 'en',
  }) async {
    final Map<String, dynamic> body = await _client.post<Map<String, dynamic>>(
      '/api/v1/auth/register',
      data: <String, dynamic>{
        'email': email.trim(),
        'password': password,
        'full_name': fullName.trim(),
        'locale': locale,
        'device': _deviceInfo(),
      },
    );
    return _persist(body);
  }

  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final Map<String, dynamic> body = await _client.post<Map<String, dynamic>>(
      '/api/v1/auth/login',
      data: <String, dynamic>{
        'email': email.trim(),
        'password': password,
        'device': _deviceInfo(),
      },
    );
    return _persist(body);
  }

  Future<AuthSession> _persist(Map<String, dynamic> body) async {
    final AuthSession session = AuthSession.fromJson(body);
    await _storage.saveTokens(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
      refreshExpiresAt: session.refreshExpiresAt,
    );
    return session;
  }

  Future<void> logout() async {
    final String? refreshToken = await _storage.readRefreshToken();
    try {
      await _client.post<Map<String, dynamic>>(
        '/api/v1/auth/logout',
        data: <String, dynamic>{
          'refresh_token': refreshToken,
          'all_devices': false,
        },
      );
    } finally {
      // Signing out locally must succeed even if the server call doesn't.
      await _storage.clear();
    }
  }

  Future<void> requestPasswordReset(String email) =>
      _client.post<Map<String, dynamic>>(
        '/api/v1/auth/forgot-password',
        data: <String, dynamic>{'email': email.trim()},
      );

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) =>
      _client.post<Map<String, dynamic>>(
        '/api/v1/auth/change-password',
        data: <String, dynamic>{
          'current_password': currentPassword,
          'new_password': newPassword,
        },
      );

  Future<void> resendVerification() =>
      _client.post<Map<String, dynamic>>('/api/v1/auth/resend-verification');

  Future<AuthUser> currentUser() async {
    final Map<String, dynamic> body =
        await _client.get<Map<String, dynamic>>('/api/v1/profile');
    return AuthUser.fromJson(body);
  }

  Future<AuthUser> completeOnboarding(OnboardingDraft draft) async {
    final Map<String, dynamic> body = await _client.post<Map<String, dynamic>>(
      '/api/v1/profile/onboarding',
      data: draft.toJson(),
    );
    return AuthUser.fromJson(body);
  }

  Future<AuthUser> updateAccount(Map<String, dynamic> changes) async {
    final Map<String, dynamic> body = await _client.patch<Map<String, dynamic>>(
      '/api/v1/profile',
      data: changes,
    );
    return AuthUser.fromJson(body);
  }

  Future<FitnessProfile> updateFitnessProfile(
      Map<String, dynamic> changes) async {
    final Map<String, dynamic> body = await _client.patch<Map<String, dynamic>>(
      '/api/v1/profile/fitness',
      data: changes,
    );
    return FitnessProfile.fromJson(body);
  }

  Future<FitnessProfile> updateNutritionTargets(
      Map<String, dynamic> targets) async {
    final Map<String, dynamic> body = await _client.put<Map<String, dynamic>>(
      '/api/v1/profile/nutrition-targets',
      data: targets,
    );
    return FitnessProfile.fromJson(body);
  }

  Future<Map<String, dynamic>> estimateNutritionTargets() => _client
      .get<Map<String, dynamic>>('/api/v1/profile/nutrition-targets/estimate');

  Future<List<Map<String, dynamic>>> sessions() async {
    final List<dynamic> body =
        await _client.get<List<dynamic>>('/api/v1/auth/sessions');
    return body
        .map((dynamic item) =>
            Map<String, dynamic>.from(item as Map<dynamic, dynamic>))
        .toList();
  }

  Future<void> revokeSession(String sessionId) =>
      _client.delete<void>('/api/v1/auth/sessions/$sessionId');

  Future<void> deleteAccount({String? password}) async {
    await _client.post<Map<String, dynamic>>(
      '/api/v1/auth/delete-account',
      data: <String, dynamic>{
        if (password != null) 'password': password,
        'confirmation': 'DELETE',
      },
    );
    await _storage.clear();
  }

  Future<bool> hasStoredSession() => _storage.hasSession;

  Map<String, dynamic> _deviceInfo() => <String, dynamic>{
        'device_name': 'FitTrack mobile',
        'platform': 'mobile',
      };
}
