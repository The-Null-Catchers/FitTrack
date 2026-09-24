import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../core/demo/demo_mode.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/notifications/local_reminders.dart';
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
            const _DailyReminderTile(),
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

/// A reminder the phone itself delivers — no server, no account, no network.
///
/// The switch only turns on once the OS has actually accepted the schedule, so
/// it never claims a reminder is set when it is not.
class _DailyReminderTile extends ConsumerStatefulWidget {
  const _DailyReminderTile();

  @override
  ConsumerState<_DailyReminderTile> createState() => _DailyReminderTileState();
}

class _DailyReminderTileState extends ConsumerState<_DailyReminderTile> {
  bool _on = false;
  bool _busy = false;
  TimeOfDay _time = const TimeOfDay(hour: 18, minute: 0);

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final List<PendingNotificationRequest> pending =
        await ref.read(localRemindersProvider).pending().catchError(
              (Object _) => <PendingNotificationRequest>[],
            );
    if (!mounted) return;
    setState(() => _on = pending.any((PendingNotificationRequest r) =>
        r.id == LocalReminders.workoutReminderId));
  }

  Future<void> _toggle(bool value) async {
    setState(() => _busy = true);
    final LocalReminders reminders = ref.read(localRemindersProvider);
    String? problem;
    try {
      if (!value) {
        await reminders.cancel(LocalReminders.workoutReminderId);
      } else if (!await reminders.requestPermission()) {
        problem = context.l10n.t('reminderBlocked');
      } else {
        final bool ok = await reminders.scheduleDaily(
          id: LocalReminders.workoutReminderId,
          title: context.l10n.t('reminderTitle'),
          body: context.l10n.t('reminderBody'),
          hour: _time.hour,
          minute: _time.minute,
        );
        if (!ok) problem = context.l10n.t('reminderRefused');
      }
    } on Object {
      problem = context.l10n.t('reminderUnavailable');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _refresh();
    if (problem != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(problem)));
    }
  }

  Future<void> _pickTime() async {
    final TimeOfDay? picked =
        await showTimePicker(context: context, initialTime: _time);
    if (picked == null) return;
    setState(() => _time = picked);
    if (_on) await _toggle(true);
  }

  @override
  Widget build(BuildContext context) {
    final bool demo = ref.watch(isDemoProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SwitchListTile(
          title: Text(context.l10n.t('reminderDaily')),
          subtitle: Text(
            demo
                ? context.l10n.t('reminderDeliveredBy')
                : '${context.l10n.t('reminderDeliveredBy')} ${_time.format(context)}',
          ),
          value: _on,
          onChanged: _busy ? null : _toggle,
        ),
        ListTile(
          enabled: !_busy,
          title: Text(context.l10n.t('reminderTime')),
          subtitle: Text(_time.format(context)),
          trailing: const Icon(Icons.schedule_outlined),
          onTap: _busy ? null : _pickTime,
        ),
      ],
    );
  }
}
