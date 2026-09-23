import 'package:fittrack/core/localization/app_localizations.dart';
import 'package:fittrack/core/theme/app_theme.dart';
import 'package:fittrack/features/workout/domain/workout_models.dart';
import 'package:fittrack/features/workout/presentation/widgets/set_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        DefaultMaterialLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('shows the previous performance for the same set number',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      _wrap(
        SetRow(
          set: const WorkoutSet(localId: 's-1', setNumber: 1),
          trackingType: 'weight_reps',
          imperial: false,
          previousSet: const WorkoutSet(
            localId: 'prev',
            setNumber: 1,
            weightKg: 80,
            reps: 8,
            isCompleted: true,
          ),
          onComplete: ({double? weightKg, int? reps, int? durationSeconds}) {},
          onChanged: ({double? weightKg, int? reps, int? durationSeconds}) {},
          onRemove: () {},
          onTypeChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('80 × 8'), findsOneWidget);
  });

  testWidgets('shows a dash when there is nothing to compare against',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      _wrap(
        SetRow(
          set: const WorkoutSet(localId: 's-1', setNumber: 1),
          trackingType: 'weight_reps',
          imperial: false,
          previousSet: null,
          onComplete: ({double? weightKg, int? reps, int? durationSeconds}) {},
          onChanged: ({double? weightKg, int? reps, int? durationSeconds}) {},
          onRemove: () {},
          onTypeChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('typing values and tapping the check reports them',
      (WidgetTester tester) async {
    double? completedWeight;
    int? completedReps;

    await tester.pumpWidget(
      _wrap(
        SetRow(
          set: const WorkoutSet(localId: 's-1', setNumber: 1),
          trackingType: 'weight_reps',
          imperial: false,
          previousSet: null,
          onComplete: ({double? weightKg, int? reps, int? durationSeconds}) {
            completedWeight = weightKg;
            completedReps = reps;
          },
          onChanged: ({double? weightKg, int? reps, int? durationSeconds}) {},
          onRemove: () {},
          onTypeChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Finder fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));

    await tester.enterText(fields.at(0), '82.5');
    await tester.enterText(fields.at(1), '7');
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    expect(completedWeight, 82.5);
    expect(completedReps, 7);
  });

  testWidgets('imperial entry is converted back to kilograms',
      (WidgetTester tester) async {
    double? completedWeight;

    await tester.pumpWidget(
      _wrap(
        SetRow(
          set: const WorkoutSet(localId: 's-1', setNumber: 1),
          trackingType: 'weight_reps',
          imperial: true,
          previousSet: null,
          onComplete: ({double? weightKg, int? reps, int? durationSeconds}) =>
              completedWeight = weightKg,
          onChanged: ({double? weightKg, int? reps, int? durationSeconds}) {},
          onRemove: () {},
          onTypeChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '100');
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    // 100 lb is 45.36 kg — the app stores metric regardless of display units.
    expect(completedWeight, closeTo(45.36, 0.01));
  });

  testWidgets('a timed exercise offers one field, not two',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      _wrap(
        SetRow(
          set: const WorkoutSet(localId: 's-1', setNumber: 1),
          trackingType: 'duration',
          imperial: false,
          previousSet: null,
          onComplete: ({double? weightKg, int? reps, int? durationSeconds}) {},
          onChanged: ({double? weightKg, int? reps, int? durationSeconds}) {},
          onRemove: () {},
          onTypeChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('a warm-up set is badged W rather than its number',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      _wrap(
        SetRow(
          set: const WorkoutSet(
            localId: 's-1',
            setNumber: 1,
            setType: 'warmup',
          ),
          trackingType: 'weight_reps',
          imperial: false,
          previousSet: null,
          onComplete: ({double? weightKg, int? reps, int? durationSeconds}) {},
          onChanged: ({double? weightKg, int? reps, int? durationSeconds}) {},
          onRemove: () {},
          onTypeChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('W'), findsOneWidget);
  });
}
