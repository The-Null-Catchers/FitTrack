import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/state_views.dart';

final FutureProvider<Map<String, dynamic>> notificationPreferencesProvider =
    FutureProvider<Map<String, dynamic>>((Ref ref) {
  return ref
      .watch(apiClientProvider)
      .get<Map<String, dynamic>>('/api/v1/notifications/preferences');
});

class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  static const List<List<String>> _toggles = <List<String>>[
    <String>['push_enabled', 'profileNotifications'],
    <String>['workout_reminders', 'notificationsWorkoutReminders'],
    <String>['habit_reminders', 'notificationsHabitReminders'],
    <String>['goal_reminders', 'notificationsGoalReminders'],
    <String>['weekly_summary', 'notificationsWeeklySummary'],
    <String>['personal_record_alerts', 'notificationsRecords'],
    <String>['rest_timer_alerts', 'notificationsRestTimer'],
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<Map<String, dynamic>> preferences =
        ref.watch(notificationPreferencesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('profileNotifications'))),
      body: preferences.when(
        loading: () => const SkeletonList(itemHeight: 56),
        error: (Object error, StackTrace _) => ErrorStateView(
          message: l10n.t('errorGeneric'),
          onRetry: () => ref.invalidate(notificationPreferencesProvider),
        ),
        data: (Map<String, dynamic> values) => ListView(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          children: <Widget>[
            ..._toggles.map(
              (List<String> toggle) => SwitchListTile(
                title: Text(l10n.t(toggle[1])),
                value: values[toggle[0]] as bool? ?? true,
                onChanged: (bool value) =>
                    _update(context, ref, toggle[0], value),
              ),
            ),
            const Divider(),
            ListTile(
              title: Text(l10n.t('notificationsQuietHours')),
              subtitle: Text(
                '${values['quiet_hours_start'] ?? '—'} – ${values['quiet_hours_end'] ?? '—'}',
              ),
              trailing: const Icon(Icons.bedtime_outlined),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _update(
    BuildContext context,
    WidgetRef ref,
    String key,
    bool value,
  ) async {
    try {
      await ref.read(apiClientProvider).patch<Map<String, dynamic>>(
            '/api/v1/notifications/preferences',
            data: <String, dynamic>{key: value},
          );
      ref.invalidate(notificationPreferencesProvider);
    } on Object {
      if (context.mounted) {
        AppToast.error(context, context.l10n.t('errorSaveFailed'));
      }
    }
  }
}
