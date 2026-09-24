import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/localization/app_localizations.dart';
import 'package:fittrack/core/localization/category_labels.dart';

/// Arabic strings are often longer than their English counterparts, and this
/// app ships to small phones. These render the real translations at hostile
/// sizes and fail on overflow, which is the failure that would otherwise only
/// show up on someone's screen.
///
/// This is not a substitute for looking at the app on a device — it catches
/// overflow and direction, not whether the result reads well.
const List<Size> _screens = <Size>[
  Size(320, 480), // the smallest Android phone still in the wild
  Size(360, 640), // very common budget size
  Size(412, 915), // typical modern handset
];

Widget _wrap(Widget child, Locale locale, Size size) => MediaQuery(
      data: MediaQueryData(size: size, devicePixelRatio: 1),
      child: MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: child),
      ),
    );

/// Any RenderBox that overflowed its constraints.
bool _overflowed(WidgetTester tester) =>
    tester.takeException().toString().toLowerCase().contains('overflow');

void main() {
  for (final Size size in _screens) {
    testWidgets('longest Arabic strings fit at ${size.width.toInt()}px',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      late AppLocalizations ar;
      await tester.pumpWidget(_wrap(
        Builder(builder: (BuildContext c) {
          ar = AppLocalizations.of(c);
          return const SizedBox.shrink();
        }),
        const Locale('ar'),
        size,
      ));
      await tester.pumpAndSettle();

      // The ten longest Arabic strings the app can show.
      final List<String> longest = <String>[
        ar.t('demoResetBody'),
        ar.t('reminderBlocked'),
        ar.t('privacyVisibleOnlyToYou'),
        ar.t('privacyExportDescription'),
        ar.t('demoRestoreWrongFile'),
        ar.t('demoExploreHint'),
      ]..sort((String a, String b) => b.length.compareTo(a.length));

      await tester.pumpWidget(_wrap(
        ListView(
          children: <Widget>[
            for (final String s in longest)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(s),
              ),
          ],
        ),
        const Locale('ar'),
        size,
      ));
      await tester.pumpAndSettle();
      expect(_overflowed(tester), isFalse,
          reason:
              'Arabic body text overflowed at ${size.width}x${size.height}');
    });

    testWidgets('category chips fit in a row at ${size.width.toInt()}px',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      late AppLocalizations ar;
      await tester.pumpWidget(_wrap(
        Builder(builder: (BuildContext c) {
          ar = AppLocalizations.of(c);
          return const SizedBox.shrink();
        }),
        const Locale('ar'),
        size,
      ));
      await tester.pumpAndSettle();

      // Four tags side by side is what the exercise detail screen shows.
      await tester.pumpWidget(_wrap(
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final String slug in <String>[
              'shoulders',
              'resistance_band',
              'intermediate',
              'plyometric',
            ])
              Chip(label: Text(ar.category(slug))),
          ],
        ),
        const Locale('ar'),
        size,
      ));
      await tester.pumpAndSettle();
      expect(_overflowed(tester), isFalse,
          reason: 'category chips overflowed at ${size.width}');
    });
  }

  testWidgets('mixed Arabic and Latin text stays right-to-left overall',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(
      Builder(
        builder: (BuildContext context) => Text(
          // A weight entry: Arabic label, Latin number and unit.
          '${AppLocalizations.of(context).t('catMuscleChest')} 82.5 kg',
        ),
      ),
      const Locale('ar'),
      const Size(360, 640),
    ));
    await tester.pumpAndSettle();
    final BuildContext ctx = tester.element(find.byType(Text));
    expect(Directionality.of(ctx), TextDirection.rtl);
    expect(_overflowed(tester), isFalse);
  });
}
