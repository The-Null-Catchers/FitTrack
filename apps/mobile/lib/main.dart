import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/database/app_database.dart';
import 'core/demo/demo_mode.dart';
import 'core/providers.dart';
import 'core/storage/app_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The app is portrait-only: the set-logging grid and the charts are designed
  // around a single-column layout.
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
  );

  // Open local storage before the first frame so no screen has to handle a
  // "not ready yet" state.
  final AppDatabase database = await AppDatabase.open();
  final AppPreferences preferences = await AppPreferences.create();

  // If demo mode was left on, reopen the bundled data before the first frame
  // so the app does not flash the signed-out screen on the way back in.
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      appDatabaseProvider.overrideWithValue(database),
      appPreferencesProvider.overrideWithValue(preferences),
    ],
  );
  await container.read(demoControllerProvider.notifier).restore();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const FitTrackApp(),
    ),
  );
}
