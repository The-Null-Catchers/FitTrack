import 'package:fittrack/core/localization/app_localizations.dart';
import 'package:fittrack/core/theme/app_theme.dart';
import 'package:fittrack/core/widgets/state_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    locale: locale,
    theme: AppTheme.light(),
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      AppLocalizations.delegate,
      DefaultMaterialLocalizations.delegate,
      DefaultWidgetsLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('empty state shows its title and message', (WidgetTester tester) async {
    await tester.pumpWidget(
      _wrap(
        const EmptyStateView(
          title: 'No workouts yet',
          message: 'Finish your first workout and it will show up here.',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No workouts yet'), findsOneWidget);
    expect(
      find.text('Finish your first workout and it will show up here.'),
      findsOneWidget,
    );
  });

  testWidgets('error state offers a retry and calls back', (WidgetTester tester) async {
    int retries = 0;
    await tester.pumpWidget(
      _wrap(
        ErrorStateView(
          message: "We couldn't load your workout history. Try again.",
          onRetry: () => retries++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text("We couldn't load your workout history. Try again."),
      findsOneWidget,
    );

    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(retries, 1);
  });

  testWidgets('error state without a callback shows no retry button',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const ErrorStateView(message: 'Nope')));
    await tester.pumpAndSettle();

    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('offline banner reports the queued change count',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const OfflineBanner(pendingChanges: 3)));
    await tester.pumpAndSettle();

    expect(find.textContaining('3'), findsOneWidget);
  });

  testWidgets('offline banner without pending work states the plain message',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const OfflineBanner()));
    await tester.pumpAndSettle();

    expect(find.text("You're offline"), findsOneWidget);
  });

  testWidgets('Arabic renders right-to-left', (WidgetTester tester) async {
    await tester.pumpWidget(
      _wrap(
        const EmptyStateView(title: 'x'),
        locale: const Locale('ar'),
      ),
    );
    await tester.pumpAndSettle();

    final Directionality directionality = tester.widget<Directionality>(
      find.descendant(
        of: find.byType(MaterialApp),
        matching: find.byType(Directionality),
      ).first,
    );
    expect(directionality.textDirection, TextDirection.rtl);
  });
}
