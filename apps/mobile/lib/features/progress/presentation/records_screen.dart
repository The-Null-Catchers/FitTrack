import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/units.dart';
import '../../../core/widgets/fit_card.dart';
import '../../../core/widgets/state_views.dart';
import '../../workout/application/workout_controller.dart';
import '../../workout/domain/workout_models.dart';

class RecordsScreen extends ConsumerWidget {
  const RecordsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<List<PersonalRecord>> records =
        ref.watch(personalRecordsProvider);
    final bool imperial = ref.watch(useImperialProvider);
    final String locale = Localizations.localeOf(context).languageCode;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('progressRecords'))),
      body: records.when(
        loading: () => const SkeletonList(itemHeight: 72),
        error: (Object error, StackTrace _) => ErrorStateView(
          message: l10n.t('errorGeneric'),
          onRetry: () => ref.invalidate(personalRecordsProvider),
        ),
        data: (List<PersonalRecord> list) {
          if (list.isEmpty) {
            return EmptyStateView(
              icon: Icons.emoji_events_outlined,
              title: l10n.t('progressNoData'),
              message: l10n.t('workoutNoHistoryBody'),
            );
          }

          // Group by exercise so a lift's records read together.
          final Map<String, List<PersonalRecord>> byExercise =
              <String, List<PersonalRecord>>{};
          for (final PersonalRecord record in list) {
            byExercise
                .putIfAbsent(record.exercise.name, () => <PersonalRecord>[])
                .add(record);
          }

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            children: byExercise.entries
                .map(
                  (MapEntry<String, List<PersonalRecord>> entry) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: FitCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            entry.key,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          ...entry.value.map(
                            (PersonalRecord record) => Padding(
                              padding:
                                  const EdgeInsets.only(bottom: AppSpacing.sm),
                              child: Row(
                                children: <Widget>[
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          record.recordType
                                              .replaceAll('_', ' '),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium,
                                        ),
                                        Text(
                                          Formatters.fullDate(
                                            record.achievedAt,
                                            locale,
                                          ),
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    record.unit == 'kg'
                                        ? Units.weight(record.value,
                                            imperial: imperial)
                                        : '${record.value.toStringAsFixed(0)} ${record.unit}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          color: context.fitColors.warning,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(),
          );
        },
      ),
    );
  }
}
