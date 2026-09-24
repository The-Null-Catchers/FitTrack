import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/localization/app_localizations.dart';

/// Arabic has to lay out right-to-left, and the strings have to actually be
/// Arabic once rendered — not keys, and not English left in place.
void main() {
  testWidgets('Arabic renders right-to-left', (WidgetTester tester) async {
    late TextDirection seen;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(
        builder: (BuildContext context) {
          seen = Directionality.of(context);
          return const SizedBox.shrink();
        },
      ),
    ));
    await tester.pumpAndSettle();
    expect(seen, TextDirection.rtl);
  });

  testWidgets('English renders left-to-right', (WidgetTester tester) async {
    late TextDirection seen;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(
        builder: (BuildContext context) {
          seen = Directionality.of(context);
          return const SizedBox.shrink();
        },
      ),
    ));
    await tester.pumpAndSettle();
    expect(seen, TextDirection.ltr);
  });

  testWidgets('Arabic lookups return Arabic, not the key and not English',
      (WidgetTester tester) async {
    late AppLocalizations ar;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(
        builder: (BuildContext context) {
          ar = AppLocalizations.of(context);
          return const SizedBox.shrink();
        },
      ),
    ));
    await tester.pumpAndSettle();

    final RegExp arabic = RegExp(r'[؀-ۿ]');
    for (final String key in <String>[
      'demoExplore',
      'demoReset',
      'reminderDaily',
      'routeNotFound',
      'privacyExportDescription',
    ]) {
      final String value = ar.t(key);
      expect(value, isNot(key), reason: 'raw key leaked to the UI: $key');
      expect(arabic.hasMatch(value), isTrue,
          reason: 'not translated to Arabic: $key = "$value"');
    }
  });
}
