import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/units.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/fit_card.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_models.dart';
import '../../habits/application/habit_providers.dart';
import '../../habits/domain/habit.dart';
import '../../sync/application/sync_controller.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final AuthUser? user = ref.watch(currentUserProvider);
    final FitnessProfile? profile = ref.watch(currentProfileProvider);
    final bool imperial = ref.watch(useImperialProvider);
    final ThemeMode themeMode = ref.watch(themeModeProvider);
    final Locale? locale = ref.watch(localeProvider);
    final SyncState sync = ref.watch(syncProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('profileTitle'))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.huge),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            child: FitCard(
              child: Row(
                children: <Widget>[
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text(
                      (user?.givenName.isNotEmpty ?? false)
                          ? user!.givenName[0].toUpperCase()
                          : '?',
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(color: theme.colorScheme.primary),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          user?.fullName ?? '',
                          style: theme.textTheme.titleMedium,
                        ),
                        Text(user?.email ?? '', style: theme.textTheme.bodySmall),
                        if (user != null && !user.emailVerified)
                          Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.xs),
                            child: Text(
                              'Email not confirmed',
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: context.fitColors.warning),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (profile != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenPadding,
              ),
              child: FitCard(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: <Widget>[
                    StatTile(
                      label: l10n.t('fieldWeight'),
                      value:
                          Units.weight(profile.currentWeightKg, imperial: imperial),
                    ),
                    StatTile(
                      label: l10n.t('fieldHeight'),
                      value: Units.height(profile.heightCm, imperial: imperial),
                    ),
                    StatTile(
                      label: l10n.t('homeGoals'),
                      value: profile.primaryGoal
                          .replaceAll('_', ' ')
                          .split(' ')
                          .map((String p) =>
                              p.isEmpty ? p : p[0].toUpperCase() + p.substring(1))
                          .join(' '),
                    ),
                  ],
                ),
              ),
            ),

          SectionHeader(title: l10n.t('habitsTitle')),
          const _HabitsCard(),

          SectionHeader(title: l10n.t('profileAppearance')),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
            child: FitCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                children: <Widget>[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.t('profileAppearance')),
                    subtitle: SegmentedButton<ThemeMode>(
                      segments: <ButtonSegment<ThemeMode>>[
                        ButtonSegment<ThemeMode>(
                          value: ThemeMode.system,
                          label: Text(l10n.t('profileThemeSystem')),
                        ),
                        ButtonSegment<ThemeMode>(
                          value: ThemeMode.light,
                          label: Text(l10n.t('profileThemeLight')),
                        ),
                        ButtonSegment<ThemeMode>(
                          value: ThemeMode.dark,
                          label: Text(l10n.t('profileThemeDark')),
                        ),
                      ],
                      selected: <ThemeMode>{themeMode},
                      showSelectedIcon: false,
                      onSelectionChanged: (Set<ThemeMode> next) =>
                          ref.read(themeModeProvider.notifier).set(next.first),
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.t('profileLanguage')),
                    trailing: DropdownButton<String>(
                      value: locale?.languageCode ?? 'system',
                      underline: const SizedBox.shrink(),
                      items: const <DropdownMenuItem<String>>[
                        DropdownMenuItem<String>(
                          value: 'system',
                          child: Text('System'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'en',
                          child: Text('English'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'ar',
                          child: Text('العربية'),
                        ),
                      ],
                      onChanged: (String? value) =>
                          ref.read(localeProvider.notifier).set(
                                value == null || value == 'system'
                                    ? null
                                    : Locale(value),
                              ),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.t('fieldUnits')),
                    subtitle: Text(
                      imperial ? l10n.t('unitsImperial') : l10n.t('unitsMetric'),
                    ),
                    value: imperial,
                    onChanged: (bool value) =>
                        ref.read(useImperialProvider.notifier).set(value),
                  ),
                ],
              ),
            ),
          ),

          SectionHeader(title: l10n.t('profileSettings')),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
            child: Column(
              children: <Widget>[
                _SettingRow(
                  icon: Icons.notifications_outlined,
                  label: l10n.t('profileNotifications'),
                  onTap: () => context.pushNamed(Routes.notificationSettings),
                ),
                _SettingRow(
                  icon: Icons.devices_outlined,
                  label: l10n.t('profileDevices'),
                  onTap: () => context.pushNamed(Routes.devices),
                ),
                _SettingRow(
                  icon: Icons.shield_outlined,
                  label: l10n.t('profilePrivacy'),
                  onTap: () => context.pushNamed(Routes.privacy),
                ),
                _SettingRow(
                  icon: Icons.list_alt_rounded,
                  label: l10n.t('programsTitle'),
                  onTap: () => context.pushNamed(Routes.programs),
                ),
                _SettingRow(
                  icon: sync.hasPendingWork
                      ? Icons.cloud_upload_outlined
                      : Icons.cloud_done_outlined,
                  label: sync.hasPendingWork
                      ? l10n.t('syncPending', <String, Object?>{
                          'count': sync.pendingCount + sync.failedCount,
                        })
                      : l10n.t('syncUpToDate'),
                  onTap: () => ref.read(syncProvider.notifier).retryFailed(),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.xl),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
            child: OutlinedButton.icon(
              onPressed: () => _signOut(context, ref),
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: Text(l10n.t('authSignOut')),
            ),
          ),

          const SizedBox(height: AppSpacing.xl),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (BuildContext context, AsyncSnapshot<PackageInfo> snapshot) {
              final String version = snapshot.data?.version ?? '1.0.0';
              return Center(
                child: Text(
                  l10n.t('profileVersion', <String, Object?>{'version': version}),
                  style: theme.textTheme.labelSmall,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final AppLocalizations l10n = context.l10n;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(l10n.t('authSignOut')),
        content: Text(l10n.t('syncUpToDate')),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.t('actionCancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.t('authSignOut')),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(authControllerProvider.notifier).signOut();
    }
  }
}

class _HabitsCard extends ConsumerWidget {
  const _HabitsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<List<Habit>> habits = ref.watch(habitsProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      child: FitCard(
        child: habits.when(
          loading: () => const SizedBox(
            height: 56,
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (Object error, StackTrace _) => Text(l10n.t('errorGeneric')),
          data: (List<Habit> list) {
            if (list.isEmpty) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(l10n.t('habitsNone'),
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.xs),
                  Text(l10n.t('habitsNoneBody'),
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              );
            }
            return Column(
              children: list
                  .map(
                    (Habit habit) => CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: habit.isDoneToday,
                      title: Text(habit.name),
                      subtitle: habit.currentStreak > 0
                          ? Text(
                              l10n.t('habitsStreak', <String, Object?>{
                                'count': habit.currentStreak,
                              }),
                              style: Theme.of(context).textTheme.labelSmall,
                            )
                          : null,
                      onChanged: (bool? value) =>
                          _toggle(context, ref, habit, value ?? false),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ),
    );
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    Habit habit,
    bool done,
  ) async {
    try {
      if (done) {
        await ref.read(habitRepositoryProvider).log(
              habitId: habit.id,
              loggedOn: DateTime.now(),
              count: habit.targetCount,
              clientUuid: 'habit-${habit.id}-${DateTime.now().microsecondsSinceEpoch}',
            );
      } else {
        await ref.read(habitRepositoryProvider).unlog(habit.id, DateTime.now());
      }
      ref.invalidate(habitsProvider);
    } on Object {
      if (context.mounted) {
        AppToast.error(context, context.l10n.t('errorSaveFailed'));
      }
    }
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: FitCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 20, color: context.fitColors.textMuted),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}
