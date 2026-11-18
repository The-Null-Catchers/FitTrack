import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fittrack/core/database/app_database.dart';
import 'package:fittrack/core/demo/demo_mode.dart';
import 'package:fittrack/core/localization/app_localizations.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/router/app_router.dart';
import 'package:fittrack/core/storage/app_preferences.dart';
import 'package:fittrack/core/theme/app_theme.dart';
import 'package:fittrack/core/utils/units.dart';
import 'package:fittrack/features/auth/application/auth_controller.dart';

/// Renders the real screens, in demo mode, and writes them out as PNGs.
///
/// This is a tool rather than an assertion: it exists because reading Arabic
/// strings in an ARB file is not the same as seeing them laid out, and this
/// environment has no emulator. It drives the actual router, providers and
/// widgets against the bundled data, so what comes out is the real layout with
/// the real translations.
///
/// It is skipped unless a destination is given. CI runs it explicitly and
/// publishes the rendered images as a workflow artifact:
///
///   FITTRACK_SCREENSHOT_DIR=/tmp/shots flutter test test/tools/render_screens_test.dart
///
/// One honest caveat: the test renderer has no system font, so a substitute
/// (DejaVu Sans, which covers Arabic) is loaded. Glyph shapes and metrics
/// differ from the phone's own font — line breaks and overflow are indicative,
/// not exact.
const List<_Shot> _shots = <_Shot>[
  _Shot('home', '/home'),
  _Shot('workout', '/workout'),
  _Shot('nutrition', '/nutrition'),
  _Shot('progress', '/progress'),
];

const List<_Shot> _additionalShots = <_Shot>[
  _Shot('profile', '/profile'),
  _Shot('programs', '/programs'),
  _Shot('exercises', '/exercises'),
  _Shot('measurements', '/measurements'),
  _Shot('records', '/records'),
  _Shot('coach', '/coach'),
  _Shot('weight-log', '/weight-log'),
  _Shot('workout-history', '/workout-history'),
];

class _Shot {
  const _Shot(this.name, this.location);
  final String name;
  final String location;
}

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

/// The app, minus the lifecycle observers, with a font the test renderer has.
class _Harness extends ConsumerWidget {
  const _Harness({required this.locale});

  final Locale locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GoRouter router = ref.watch(routerProvider);
    final ThemeData base = AppTheme.light();
    return MaterialApp.router(
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // The substitute font has to reach the component themes too — buttons,
      // the app bar and chips carry their own text styles, and anything left
      // on the test renderer's default font draws as empty boxes.
      theme: _withFont(base),
      // Mirrors what the real app does in its own builder: the unit words
      // come from the resolved locale. Without this the screenshots would
      // show English units the app itself would not print.
      builder: (BuildContext context, Widget? child) {
        final AppLocalizations l10n = AppLocalizations.of(context);
        Units.labels = UnitLabels(
          kg: l10n.t('commonKg'),
          lb: l10n.t('unitLb'),
          cm: l10n.t('unitCm'),
          inch: l10n.t('unitIn'),
          km: l10n.t('unitKm'),
          metre: l10n.t('unitMetre'),
          mile: l10n.t('unitMile'),
          foot: l10n.t('unitFoot'),
          hour: l10n.t('unitHourShort'),
          minute: l10n.t('unitMinuteShort'),
        );
        return child ?? const SizedBox.shrink();
      },
    );
  }
}

void main() {
  final String? outRoot = Platform.environment['FITTRACK_SCREENSHOT_DIR'];
  final bool portfolioOnly = Platform.environment['FITTRACK_PORTFOLIO'] == '1';
  final List<_Shot> shots = <_Shot>[
    ..._shots,
    if (!portfolioOnly) ..._additionalShots,
  ];

  // Fonts are registered once, from `setUpAll`, which runs outside the test's
  // fake clock. `FontLoader.load()` waits on the engine, so it cannot complete
  // inside a `testWidgets` body.
  setUpAll(() async {
    if (outRoot == null) return;
    // Without the binding, the font-registration message has nothing to answer
    // it and the load never returns.
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
  });

  for (final String language in <String>['ar', 'en']) {
    for (final Size size in <Size>[
      const Size(412, 915),
      const Size(320, 480)
    ]) {
      testWidgets(
        'render $language at ${size.width.toInt()}x${size.height.toInt()}',
        (WidgetTester tester) async {
          final Directory out = Directory(
            '$outRoot/$language-${size.width.toInt()}x${size.height.toInt()}',
          )..createSync(recursive: true);

          void stage(String s) => debugPrint('[shots] $s');

          // `createTemp` is real file I/O, so it too has to run outside the
          // fake clock.
          Directory? scratch;
          await tester.runAsync(() async => scratch =
              await Directory.systemTemp.createTemp('fittrack_shots'));
          final Directory tmp = scratch!;
          addTearDown(() {
            if (tmp.existsSync()) tmp.deleteSync(recursive: true);
          });
          stage('tmp dir ${tmp.path}');
          PathProviderPlatform.instance = _FakePathProvider(tmp.path);
          FlutterSecureStorage.setMockInitialValues(<String, String>{});
          SharedPreferences.setMockInitialValues(<String, Object>{
            'fittrack.demo_mode': true,
            'fittrack.locale': language,
            'fittrack.onboarding_seen': true,
          });
          sqfliteFfiInit();
          databaseFactory = databaseFactoryFfi;

          // Everything here touches the real file system, the real SQLite
          // engine and the bundled asset, so it has to run outside the test's
          // fake clock — inside `runAsync` — or the await never completes.
          stage('opening storage');
          ProviderContainer? built;
          await tester.runAsync(() async {
            final AppDatabase database =
                await AppDatabase.open(path: inMemoryDatabasePath);
            built = ProviderContainer(
              overrides: <Override>[
                appDatabaseProvider.overrideWithValue(database),
                isOnlineProvider.overrideWithValue(true),
                appPreferencesProvider
                    .overrideWithValue(await AppPreferences.create()),
              ],
            );

            // Demo mode, then the ordinary sign-in the demo button performs.
            // The adapter ignores the credentials; nothing leaves the device.
            await built!.read(demoControllerProvider.notifier).restore();
            await built!.read(authControllerProvider.notifier).signIn(
                  email: 'demo@fittrack.app',
                  password: 'demo',
                );
          });
          stage('signed in');
          final ProviderContainer container = built!;
          addTearDown(container.dispose);

          stage('pumping');
          await tester.binding.setSurfaceSize(size);
          addTearDown(() => tester.binding.setSurfaceSize(null));

          final GlobalKey boundaryKey = GlobalKey();
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: RepaintBoundary(
                key: boundaryKey,
                child: _Harness(locale: Locale(language)),
              ),
            ),
          );
          await _settle(tester);

          stage('first frame settled');
          final GoRouter router = container.read(routerProvider);
          for (final _Shot shot in shots) {
            router.go(shot.location);
            await _settle(tester);
            await _write(tester, boundaryKey, '${out.path}/${shot.name}.png');
            stage('wrote ${shot.name}');
          }
        },
        skip: outRoot == null,
        timeout: const Timeout(Duration(minutes: 5)),
      );
    }
  }
}

/// A font the test renderer can actually draw with, including Arabic. The
/// platform font is not available under `flutter test`.
Future<void> _loadFonts() async {
  final String flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter';
  final Map<String, List<String>> families = <String, List<String>>{
    // Covers Arabic as well as Latin; the phone's own font is not available
    // to the test renderer.
    'DejaVuSans': <String>[
      '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
      '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
    ],
    // Otherwise every icon draws as an empty box.
    'MaterialIcons': <String>[
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ],
  };
  for (final MapEntry<String, List<String>> entry in families.entries) {
    final FontLoader loader = FontLoader(entry.key);
    for (final String path in entry.value) {
      final File file = File(path);
      if (!file.existsSync()) continue;
      final Uint8List bytes = file.readAsBytesSync();
      loader.addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }
}

/// Settles by hand rather than with `pumpAndSettle`.
///
/// Two reasons: the screens fetch from the bundled data, which needs real
/// asynchrony (`runAsync`) rather than fake-clock pumping; and a screen showing
/// a `CircularProgressIndicator` never settles, because that animation never
/// ends — `pumpAndSettle` would sit there until it timed out.
Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 12; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _write(WidgetTester tester, GlobalKey key, String path) async {
  final RenderRepaintBoundary boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage();
    final ByteData? png =
        await image.toByteData(format: ui.ImageByteFormat.png);
    if (png != null) {
      File(path).writeAsBytesSync(png.buffer.asUint8List());
    }
    image.dispose();
  });
}

/// Re-points every text style in [base] at the substitute font.
ThemeData _withFont(ThemeData base) {
  const String family = 'DejaVuSans';
  TextStyle? f(TextStyle? style) => style?.copyWith(fontFamily: family);
  ButtonStyle? b(ButtonStyle? style) => style?.copyWith(
        textStyle: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) =>
              f(style.textStyle?.resolve(states)) ??
              TextStyle(fontFamily: family, fontWeight: FontWeight.w600),
        ),
      );
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: family),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: family),
    appBarTheme: base.appBarTheme.copyWith(
      titleTextStyle: f(base.appBarTheme.titleTextStyle) ??
          TextStyle(fontFamily: family, fontSize: 20),
    ),
    chipTheme: base.chipTheme.copyWith(
      labelStyle: f(base.chipTheme.labelStyle),
      secondaryLabelStyle: f(base.chipTheme.secondaryLabelStyle),
    ),
    filledButtonTheme:
        FilledButtonThemeData(style: b(base.filledButtonTheme.style)),
    outlinedButtonTheme:
        OutlinedButtonThemeData(style: b(base.outlinedButtonTheme.style)),
    textButtonTheme: TextButtonThemeData(style: b(base.textButtonTheme.style)),
    navigationBarTheme: base.navigationBarTheme.copyWith(
      labelTextStyle: WidgetStateProperty.resolveWith(
        (Set<WidgetState> states) =>
            f(base.navigationBarTheme.labelTextStyle?.resolve(states)) ??
            TextStyle(fontFamily: family, fontSize: 11),
      ),
    ),
  );
}
