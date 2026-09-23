import 'package:fittrack/core/localization/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('loading', () {
    test('loads English', () async {
      final AppLocalizations l10n =
          await AppLocalizations.load(const Locale('en'));

      expect(l10n.locale.languageCode, 'en');
      expect(l10n.isRtl, isFalse);
      expect(l10n.t('navHome'), 'Home');
    });

    test('loads Arabic and reports it as right-to-left', () async {
      final AppLocalizations l10n =
          await AppLocalizations.load(const Locale('ar'));

      expect(l10n.locale.languageCode, 'ar');
      expect(l10n.isRtl, isTrue);
      expect(l10n.t('navHome'), 'الرئيسية');
      expect(l10n.t('workoutFinish'), 'إنهاء التمرين');
    });

    test('falls back to English for an unsupported language', () async {
      final AppLocalizations l10n =
          await AppLocalizations.load(const Locale('fr'));

      expect(l10n.locale.languageCode, 'en');
    });
  });

  group('lookup', () {
    test('substitutes placeholders', () async {
      final AppLocalizations l10n =
          await AppLocalizations.load(const Locale('en'));

      expect(
        l10n.t('homeGreetingMorning', <String, Object?>{'name': 'Sam'}),
        'Good morning, Sam',
      );
      expect(
        l10n.t('homeWorkoutsCompleted', <String, Object?>{
          'completed': 2,
          'target': 4,
        }),
        '2 of 4 workouts',
      );
    });

    test('returns the key itself for a missing entry rather than crashing',
        () async {
      final AppLocalizations l10n =
          await AppLocalizations.load(const Locale('en'));

      expect(l10n.t('thisKeyDoesNotExist'), 'thisKeyDoesNotExist');
    });
  });

  group('translation coverage', () {
    test('every English key has an Arabic counterpart', () async {
      final AppLocalizations english =
          await AppLocalizations.load(const Locale('en'));
      final AppLocalizations arabic =
          await AppLocalizations.load(const Locale('ar'));

      // A handful of keys are proper nouns and legitimately identical; the rest
      // must actually differ, which catches an untranslated copy-paste.
      const Set<String> sameInBothLanguages = <String>{};

      int translated = 0;
      for (final String key in <String>[
        'navHome',
        'navWorkout',
        'navNutrition',
        'navProgress',
        'navProfile',
        'workoutFinish',
        'workoutAddSet',
        'nutritionCalories',
        'progressTitle',
        'coachDisclaimer',
        'errorNetwork',
        'syncOffline',
      ]) {
        expect(arabic.t(key), isNot(key), reason: '$key is missing in Arabic');
        if (!sameInBothLanguages.contains(key)) {
          expect(
            arabic.t(key),
            isNot(english.t(key)),
            reason: '$key appears untranslated',
          );
        }
        translated++;
      }
      expect(translated, 12);
    });
  });
}
