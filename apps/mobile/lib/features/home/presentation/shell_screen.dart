import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/units.dart';
import '../../../core/widgets/state_views.dart';
import '../../sync/application/sync_controller.dart';
import '../../workout/application/workout_controller.dart';
import '../../workout/domain/workout_models.dart';

/// The tabbed shell.
///
/// Holds the bottom navigation, the offline banner and — the important part —
/// a persistent bar for a workout in progress, so a session can be minimised
/// and picked back up from anywhere in the app.
class ShellScreen extends ConsumerWidget {
  const ShellScreen({super.key, required this.child});

  final Widget child;

  static const List<String> _routes = <String>[
    '/home',
    '/workout',
    '/nutrition',
    '/progress',
    '/profile',
  ];

  int _indexFor(String location) {
    for (int index = _routes.length - 1; index >= 0; index--) {
      if (location.startsWith(_routes[index])) return index;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final String location = GoRouterState.of(context).matchedLocation;
    final int index = _indexFor(location);

    final bool isOnline = ref.watch(isOnlineProvider);
    final SyncState sync = ref.watch(syncProvider);
    final WorkoutSession? activeWorkout =
        ref.watch(activeWorkoutProvider).session;

    return Scaffold(
      body: Column(
        children: <Widget>[
          if (!isOnline) OfflineBanner(pendingChanges: sync.pendingCount),
          Expanded(child: child),
          if (activeWorkout != null && location != '/active-workout')
            _ActiveWorkoutBar(session: activeWorkout),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (int next) => context.go(_routes[next]),
        destinations: <NavigationDestination>[
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home_rounded),
            label: l10n.t('navHome'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.fitness_center_outlined),
            selectedIcon: const Icon(Icons.fitness_center_rounded),
            label: l10n.t('navWorkout'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.restaurant_outlined),
            selectedIcon: const Icon(Icons.restaurant_rounded),
            label: l10n.t('navNutrition'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.insights_outlined),
            selectedIcon: const Icon(Icons.insights_rounded),
            label: l10n.t('navProgress'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline_rounded),
            selectedIcon: const Icon(Icons.person_rounded),
            label: l10n.t('navProfile'),
          ),
        ],
      ),
    );
  }
}

/// The "you're mid-workout" bar. Tapping it reopens the session.
class _ActiveWorkoutBar extends StatelessWidget {
  const _ActiveWorkoutBar({required this.session});

  final WorkoutSession session;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.primary,
      child: InkWell(
        onTap: () => context.pushNamed(Routes.activeWorkout),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.play_circle_fill_rounded,
                  color: theme.colorScheme.onPrimary,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        session.name,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(color: theme.colorScheme.onPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${session.completedSetCount}/${session.plannedSetCount} '
                        '${context.l10n.t('workoutTotalSets').toLowerCase()} · '
                        '${Units.durationLong(session.elapsed.inSeconds)}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimary
                              .withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_up_rounded,
                  color: theme.colorScheme.onPrimary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
