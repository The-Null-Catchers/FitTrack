import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/localization/category_labels.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/state_views.dart';
import '../application/exercise_providers.dart';
import '../domain/exercise.dart';

/// The exercise library.
///
/// Doubles as a picker: opened with `?picker=true` it pops the chosen
/// [Exercise] back to the caller instead of navigating to the detail page.
class ExerciseLibraryScreen extends ConsumerStatefulWidget {
  const ExerciseLibraryScreen({super.key, this.isPicker = false});

  final bool isPicker;

  @override
  ConsumerState<ExerciseLibraryScreen> createState() =>
      _ExerciseLibraryScreenState();
}

class _ExerciseLibraryScreenState extends ConsumerState<ExerciseLibraryScreen> {
  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();

  static const List<String> _muscleGroups = <String>[
    'chest',
    'back',
    'shoulders',
    'arms',
    'legs',
    'core',
    'cardio',
    'mobility',
  ];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      // Load the next page a screen ahead of the bottom.
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
        ref.read(exerciseListProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ExerciseListState state = ref.watch(exerciseListProvider);
    final ExerciseFilters filters = ref.watch(exerciseFiltersProvider);
    final String languageCode = Localizations.localeOf(context).languageCode;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('exercisesTitle'))),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              AppSpacing.sm,
              AppSpacing.screenPadding,
              AppSpacing.md,
            ),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: l10n.t('exercisesSearch'),
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _search.clear();
                          ref.read(exerciseFiltersProvider.notifier).state =
                              filters.copyWith(query: '');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
              onChanged: (String value) {
                setState(() {});
                ref.read(exerciseFiltersProvider.notifier).state =
                    filters.copyWith(query: value);
              },
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenPadding,
              ),
              children: <Widget>[
                for (final String group in _muscleGroups)
                  Padding(
                    padding:
                        const EdgeInsetsDirectional.only(end: AppSpacing.sm),
                    child: FilterChip(
                      label: Text(_label(group)),
                      selected: filters.muscleGroup == group,
                      onSelected: (bool selected) {
                        ref.read(exerciseFiltersProvider.notifier).state =
                            selected
                                ? filters.copyWith(muscleGroup: group)
                                : filters.copyWith(clearMuscleGroup: true);
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: Builder(
              builder: (BuildContext context) {
                if (state.isLoading) {
                  return const SkeletonList(itemHeight: 68);
                }
                if (state.error != null && state.items.isEmpty) {
                  return ErrorStateView(
                    message: l10n.t('errorLoadExercises'),
                    onRetry: () =>
                        ref.read(exerciseListProvider.notifier).refresh(),
                  );
                }
                if (state.isEmpty) {
                  return EmptyStateView(
                    icon: Icons.search_off_rounded,
                    title: l10n.t('exercisesNoResults'),
                    message: l10n.t('exercisesNoResultsBody'),
                  );
                }
                return ListView.separated(
                  controller: _scroll,
                  padding: const EdgeInsets.only(bottom: AppSpacing.huge),
                  itemCount: state.items.length + (state.isLoadingMore ? 1 : 0),
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    if (index >= state.items.length) {
                      return const Padding(
                        padding: EdgeInsets.all(AppSpacing.lg),
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    }
                    final Exercise exercise = state.items[index];
                    return _ExerciseTile(
                      exercise: exercise,
                      languageCode: languageCode,
                      onTap: () {
                        if (widget.isPicker) {
                          context.pop(exercise);
                          return;
                        }
                        context.pushNamed(
                          Routes.exerciseDetail,
                          pathParameters: <String, String>{'id': exercise.id},
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _label(String value) => value
      .split('_')
      .map((String part) =>
          part.isEmpty ? part : part[0].toUpperCase() + part.substring(1))
      .join(' ');
}

class _ExerciseTile extends StatelessWidget {
  const _ExerciseTile({
    required this.exercise,
    required this.languageCode,
    required this.onTap,
  });

  final Exercise exercise;
  final String languageCode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        clipBehavior: Clip.antiAlias,
        child: exercise.imageUrl == null
            ? Icon(
                Icons.fitness_center_rounded,
                size: 20,
                color: context.fitColors.textMuted,
              )
            : CachedNetworkImage(
                imageUrl: exercise.imageUrl!,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Icon(
                  Icons.fitness_center_rounded,
                  size: 20,
                  color: context.fitColors.textMuted,
                ),
              ),
      ),
      title: Text(exercise.displayName(languageCode)),
      subtitle: Text(
        '${context.l10n.category(exercise.muscleGroup)}'
        ' · ${context.l10n.category(exercise.equipment)}',
        style: theme.textTheme.bodySmall,
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
    );
  }
}
