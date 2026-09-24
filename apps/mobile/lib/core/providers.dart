import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database/active_session_dao.dart';
import 'database/app_database.dart';
import 'database/cache_dao.dart';
import 'database/outbox_dao.dart';
import 'demo/demo_mode.dart';
import 'network/api_client.dart';
import 'network/connectivity_service.dart';
import 'storage/app_preferences.dart';
import 'storage/secure_storage.dart';

/// Infrastructure providers.
///
/// [appDatabaseProvider] and [appPreferencesProvider] are overridden in
/// `main()` with instances opened before the first frame, so no screen has to
/// handle "storage isn't ready yet". Tests override them with in-memory ones.
final Provider<AppDatabase> appDatabaseProvider =
    Provider<AppDatabase>((Ref ref) {
  throw UnimplementedError('appDatabaseProvider must be overridden in main()');
});

final Provider<AppPreferences> appPreferencesProvider =
    Provider<AppPreferences>((Ref ref) {
  throw UnimplementedError(
      'appPreferencesProvider must be overridden in main()');
});

final Provider<SecureStorage> secureStorageProvider =
    Provider<SecureStorage>((Ref ref) => SecureStorage());

final Provider<OutboxDao> outboxDaoProvider =
    Provider<OutboxDao>((Ref ref) => OutboxDao(ref.watch(appDatabaseProvider)));

final Provider<CacheDao> cacheDaoProvider =
    Provider<CacheDao>((Ref ref) => CacheDao(ref.watch(appDatabaseProvider)));

final Provider<ActiveSessionDao> activeSessionDaoProvider =
    Provider<ActiveSessionDao>(
  (Ref ref) => ActiveSessionDao(ref.watch(appDatabaseProvider)),
);

final Provider<ConnectivityService> connectivityServiceProvider =
    Provider<ConnectivityService>((Ref ref) => ConnectivityService());

/// Live online/offline state. Starts optimistic so the first frame doesn't
/// flash an offline banner while the platform channel answers.
final StreamProvider<bool> connectivityProvider =
    StreamProvider<bool>((Ref ref) {
  final ConnectivityService service = ref.watch(connectivityServiceProvider);
  return service.onStatusChange;
});

final Provider<bool> isOnlineProvider = Provider<bool>((Ref ref) {
  return ref.watch(connectivityProvider).maybeWhen(
        data: (bool online) => online,
        orElse: () => true,
      );
});

/// Raised when the refresh token is rejected; the router listens and redirects.
final StateProvider<int> sessionExpiredTickProvider =
    StateProvider<int>((Ref ref) => 0);

final Provider<ApiClient> apiClientProvider = Provider<ApiClient>((Ref ref) {
  // In demo mode the transport is swapped for one that answers from bundled
  // data. Everything above this line — repositories, controllers, screens — is
  // identical either way. That is the point: the demo exercises the real app,
  // and the online path is left untouched.
  final DemoState demo = ref.watch(demoControllerProvider);
  if (demo.isActive) {
    return buildDemoApiClient(
      demo.store!,
      ref.watch(secureStorageProvider),
      // The canned coach replies answer in whichever language is selected.
      localeCode: () =>
          ref.read(localeProvider)?.languageCode ??
          PlatformDispatcher.instance.locale.languageCode,
    );
  }
  return ApiClient(
    storage: ref.watch(secureStorageProvider),
    onSessionExpired: () =>
        ref.read(sessionExpiredTickProvider.notifier).state++,
  );
});

// --- device preferences ----------------------------------------------------

class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController(this._preferences) : super(_preferences.themeMode);

  final AppPreferences _preferences;

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await _preferences.setThemeMode(mode);
  }
}

final StateNotifierProvider<ThemeModeController, ThemeMode> themeModeProvider =
    StateNotifierProvider<ThemeModeController, ThemeMode>(
  (Ref ref) => ThemeModeController(ref.watch(appPreferencesProvider)),
);

/// `null` follows the device language.
class LocaleController extends StateNotifier<Locale?> {
  LocaleController(this._preferences) : super(_preferences.locale);

  final AppPreferences _preferences;

  Future<void> set(Locale? locale) async {
    state = locale;
    await _preferences.setLocale(locale);
  }
}

final StateNotifierProvider<LocaleController, Locale?> localeProvider =
    StateNotifierProvider<LocaleController, Locale?>(
  (Ref ref) => LocaleController(ref.watch(appPreferencesProvider)),
);

class UnitSystemController extends StateNotifier<bool> {
  UnitSystemController(this._preferences) : super(_preferences.useImperial);

  final AppPreferences _preferences;

  Future<void> set(bool imperial) async {
    state = imperial;
    await _preferences.setUseImperial(imperial);
  }
}

/// True when weights and lengths should render in imperial units.
final StateNotifierProvider<UnitSystemController, bool> useImperialProvider =
    StateNotifierProvider<UnitSystemController, bool>(
  (Ref ref) => UnitSystemController(ref.watch(appPreferencesProvider)),
);
