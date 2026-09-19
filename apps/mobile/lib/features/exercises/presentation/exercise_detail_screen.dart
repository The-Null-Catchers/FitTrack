import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/fit_card.dart';
import '../../../core/widgets/state_views.dart';
import '../application/exercise_providers.dart';
import '../domain/exercise.dart';

class ExerciseDetailScreen extends ConsumerWidget {
  const ExerciseDetailScreen({super.key, required this.exerciseId});

  final String exerciseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<Exercise?> exercise =
        ref.watch(exerciseDetailProvider(exerciseId));
    final String languageCode = Localizations.localeOf(context).languageCode;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('exercisesTitle'))),
      body: exercise.when(
        loading: () => const SkeletonList(itemHeight: 90),
        error: (Object error, StackTrace _) => ErrorStateView(
          message: l10n.t('errorLoadExercises'),
          onRetry: () => ref.invalidate(exerciseDetailProvider(exerciseId)),
        ),
        data: (Exercise? item) {
          if (item == null) {
            return EmptyStateView(title: l10n.t('errorNotFound'));
          }
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            children: <Widget>[
              if (item.imageUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  child: CachedNetworkImage(
                    imageUrl: item.imageUrl!,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                item.displayName(languageCode),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: <Widget>[
                  _Tag(label: _pretty(item.muscleGroup)),
                  _Tag(label: _pretty(item.equipment)),
                  _Tag(label: _pretty(item.difficulty)),
                  _Tag(label: _pretty(item.exerciseType)),
                ],
              ),
              if (item.description != null) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                Text(item.description!,
                    style: Theme.of(context).textTheme.bodyMedium),
              ],
              if (item.instructions.isNotEmpty) ...<Widget>[
                SectionHeader(
                  title: l10n.t('exercisesInstructions'),
                  padding: const EdgeInsets.only(
                    top: AppSpacing.xxl,
                    bottom: AppSpacing.md,
                  ),
                ),
                FitCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: item.instructions
                        .asMap()
                        .entries
                        .map(
                          (MapEntry<int, String> entry) => Padding(
                            padding: EdgeInsets.only(
                              bottom: entry.key == item.instructions.length - 1
                                  ? 0
                                  : AppSpacing.md,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Container(
                                  width: 22,
                                  height: 22,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primaryContainer,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    '${entry.key + 1}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                        ),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: Text(
                                    entry.value,
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
              if (item.secondaryMuscles.isNotEmpty) ...<Widget>[
                SectionHeader(
                  title: l10n.t('exercisesMuscleGroup'),
                  padding: const EdgeInsets.only(
                    top: AppSpacing.xxl,
                    bottom: AppSpacing.md,
                  ),
                ),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: item.secondaryMuscles
                      .map((String muscle) => _Tag(label: _pretty(muscle)))
                      .toList(),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  static String _pretty(String value) => value
      .split('_')
      .map((String part) =>
          part.isEmpty ? part : part[0].toUpperCase() + part.substring(1))
      .join(' ');
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}
