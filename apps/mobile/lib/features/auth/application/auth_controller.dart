import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../data/auth_repository.dart';
import '../domain/auth_models.dart';

final Provider<AuthRepository> authRepositoryProvider =
    Provider<AuthRepository>((Ref ref) {
  return AuthRepository(
    ref.watch(apiClientProvider),
    ref.watch(secureStorageProvider),
  );
});

/// Where the app is in the sign-in lifecycle.
enum AuthStatus { unknown, unauthenticated, needsOnboarding, authenticated }

@immutable
class AuthState {
  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.isBusy = false,
    this.errorMessage,
  });

  final AuthStatus status;
  final AuthUser? user;
  final bool isBusy;
  final String? errorMessage;

  bool get isSignedIn =>
      status == AuthStatus.authenticated ||
      status == AuthStatus.needsOnboarding;

  AuthState copyWith({
    AuthStatus? status,
    AuthUser? user,
    bool? isBusy,
    String? errorMessage,
    bool clearError = false,
    bool clearUser = false,
  }) =>
      AuthState(
        status: status ?? this.status,
        user: clearUser ? null : (user ?? this.user),
        isBusy: isBusy ?? this.isBusy,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._ref) : super(const AuthState()) {
    unawaited(restore());
  }

  final Ref _ref;

  AuthRepository get _repository => _ref.read(authRepositoryProvider);

  /// Resolve the startup state from whatever is stored on the device.
  ///
  /// A stored session with no connectivity still signs the user in: the app is
  /// offline-first, and the token is validated on the first successful call.
  Future<void> restore() async {
    if (!await _repository.hasStoredSession()) {
      state = const AuthState(status: AuthStatus.unauthenticated);
      return;
    }

    try {
      final AuthUser user = await _repository.currentUser();
      state = AuthState(status: _statusFor(user), user: user);
    } on ApiException catch (error) {
      if (error.isUnauthorized || error.isForbidden) {
        await _clearLocalState();
        state = const AuthState(status: AuthStatus.unauthenticated);
        return;
      }
      // Network failure: trust the stored session rather than locking the user
      // out of an app that works offline.
      state = const AuthState(status: AuthStatus.authenticated);
    }
  }

  Future<bool> signIn({required String email, required String password}) async {
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final AuthSession session =
          await _repository.login(email: email, password: password);
      state = AuthState(status: _statusFor(session.user), user: session.user);
      return true;
    } on ApiException catch (error) {
      state = state.copyWith(isBusy: false, errorMessage: error.message);
      return false;
    }
  }

  Future<bool> register({
    required String email,
    required String password,
    required String fullName,
    String locale = 'en',
  }) async {
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final AuthSession session = await _repository.register(
        email: email,
        password: password,
        fullName: fullName,
        locale: locale,
      );
      state = AuthState(status: _statusFor(session.user), user: session.user);
      return true;
    } on ApiException catch (error) {
      state = state.copyWith(isBusy: false, errorMessage: error.message);
      return false;
    }
  }

  Future<bool> completeOnboarding(OnboardingDraft draft) async {
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final AuthUser user = await _repository.completeOnboarding(draft);
      state = AuthState(status: AuthStatus.authenticated, user: user);
      return true;
    } on ApiException catch (error) {
      state = state.copyWith(isBusy: false, errorMessage: error.message);
      return false;
    }
  }

  Future<void> refreshUser() async {
    try {
      final AuthUser user = await _repository.currentUser();
      state = state.copyWith(status: _statusFor(user), user: user);
    } on ApiException {
      // Keep the cached user; a refresh failure is not a sign-out.
    }
  }

  Future<void> signOut() async {
    state = state.copyWith(isBusy: true);
    try {
      await _repository.logout();
    } finally {
      await _clearLocalState();
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  Future<bool> deleteAccount({String? password}) async {
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      await _repository.deleteAccount(password: password);
      await _clearLocalState();
      state = const AuthState(status: AuthStatus.unauthenticated);
      return true;
    } on ApiException catch (error) {
      state = state.copyWith(isBusy: false, errorMessage: error.message);
      return false;
    }
  }

  /// Called by the API client when a refresh token is rejected.
  Future<void> handleSessionExpired() async {
    await _clearLocalState();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  void clearError() => state = state.copyWith(clearError: true);

  /// Local data belongs to the account that owned it — including unsynced work.
  Future<void> _clearLocalState() async {
    final AppDatabase database = _ref.read(appDatabaseProvider);
    await database.clear();
  }

  AuthStatus _statusFor(AuthUser user) => user.onboardingCompleted
      ? AuthStatus.authenticated
      : AuthStatus.needsOnboarding;
}

final StateNotifierProvider<AuthController, AuthState> authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>(
  (Ref ref) => AuthController(ref),
);

/// The signed-in user, or `null`.
final Provider<AuthUser?> currentUserProvider = Provider<AuthUser?>(
  (Ref ref) => ref.watch(authControllerProvider).user,
);

final Provider<FitnessProfile?> currentProfileProvider =
    Provider<FitnessProfile?>(
  (Ref ref) => ref.watch(currentUserProvider)?.profile,
);
