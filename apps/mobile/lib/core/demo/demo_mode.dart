import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../network/api_client.dart';
import '../providers.dart';
import '../storage/app_preferences.dart';
import '../storage/secure_storage.dart';
import 'demo_api_adapter.dart';
import 'demo_store.dart';

/// State of demo mode.
///
/// When [store] is non-null the app is running offline against bundled data:
/// `apiClientProvider` builds its Dio on [DemoApiAdapter] instead of a real
/// socket, and nothing below it knows the difference.
class DemoState {
  const DemoState({this.enabled = false, this.store});

  final bool enabled;
  final DemoStore? store;

  bool get isActive => enabled && store != null;
}

class DemoController extends StateNotifier<DemoState> {
  DemoController(this._preferences) : super(const DemoState());

  final AppPreferences _preferences;

  /// Re-enter demo mode on launch if it was left on. Called once from `main()`
  /// before the first frame, so the app never flashes the signed-out screen.
  Future<void> restore() async {
    if (!_preferences.demoMode) return;
    state = DemoState(enabled: true, store: await DemoStore.open());
  }

  Future<void> enable() async {
    final DemoStore store = await DemoStore.open();
    await _preferences.setDemoMode(true);
    state = DemoState(enabled: true, store: store);
  }

  Future<void> disable() async {
    await _preferences.setDemoMode(false);
    state = const DemoState();
  }

  /// Write an export to a temporary file and return it for sharing.
  Future<File?> exportToFile() async {
    final DemoStore? store = state.store;
    if (store == null) return null;
    final Directory dir = await getTemporaryDirectory();
    final String stamp =
        DateTime.now().toIso8601String().split('.').first.replaceAll(':', '-');
    final File out = File('${dir.path}/fittrack-backup-$stamp.json');
    await out.writeAsString(await store.exportJson(), flush: true);
    return out;
  }

  /// Restore from a previously exported file. Rethrows [FormatException] when
  /// the file is not one of ours, so the caller can say so.
  Future<void> importFromFile(File file) async {
    final DemoStore? store = state.store;
    if (store == null) return;
    await store.importJson(await file.readAsString());
    state = DemoState(enabled: true, store: await DemoStore.open());
  }

  /// Throw away every local change and go back to the bundled data.
  Future<void> resetData() async {
    final DemoStore? store = state.store;
    if (store == null) return;
    await store.reset();
    // Swap the identity so watchers rebuild and refetch.
    state = DemoState(enabled: true, store: await DemoStore.open());
  }
}

final StateNotifierProvider<DemoController, DemoState> demoControllerProvider =
    StateNotifierProvider<DemoController, DemoState>(
  (Ref ref) => DemoController(ref.watch(appPreferencesProvider)),
);

/// True when the app is serving everything from bundled data.
final Provider<bool> isDemoProvider = Provider<bool>(
  (Ref ref) => ref.watch(demoControllerProvider).isActive,
);

/// Builds an [ApiClient] whose transport is the bundled-data adapter.
ApiClient buildDemoApiClient(DemoStore store, SecureStorage storage) {
  final Dio dio = Dio()..httpClientAdapter = DemoApiAdapter(store);
  return ApiClient(storage: storage, dio: dio);
}
