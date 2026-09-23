import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/units.dart';
import '../../application/rest_timer_controller.dart';

/// The rest countdown, pinned above the set list while it runs.
class RestTimerBar extends ConsumerWidget {
  const RestTimerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final RestTimerState timer = ref.watch(restTimerProvider);
    if (!timer.isActive) return const SizedBox.shrink();

    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final RestTimerController controller = ref.read(restTimerProvider.notifier);

    return Material(
      color: theme.colorScheme.primaryContainer,
      child: Column(
        children: <Widget>[
          LinearProgressIndicator(
            value: timer.progress,
            minHeight: 3,
            backgroundColor: Colors.transparent,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: <Widget>[
                Semantics(
                  liveRegion: true,
                  label:
                      '${l10n.t('workoutRestTimer')} ${Units.duration(timer.remainingSeconds)}',
                  child: Text(
                    Units.duration(timer.remainingSeconds),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    timer.exerciseName ?? l10n.t('workoutRestTimer'),
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _TimerButton(
                  label: l10n.t('workoutRestSubtract'),
                  onPressed: () => controller.adjust(-15),
                ),
                _TimerButton(
                  label: l10n.t('workoutRestAdd'),
                  onPressed: () => controller.adjust(15),
                ),
                IconButton(
                  onPressed:
                      timer.isPaused ? controller.resume : controller.pause,
                  tooltip: timer.isPaused ? 'Resume' : 'Pause',
                  icon: Icon(
                    timer.isPaused
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded,
                  ),
                ),
                IconButton(
                  onPressed: controller.skip,
                  tooltip: l10n.t('workoutRestSkip'),
                  icon: const Icon(Icons.skip_next_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimerButton extends StatelessWidget {
  const _TimerButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(44, AppSpacing.minTouchTarget),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      ),
      child: Text(label),
    );
  }
}
