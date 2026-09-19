import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/env.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/fit_card.dart';
import '../../auth/application/auth_controller.dart';

/// Privacy, data export and account deletion.
class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('profilePrivacy'))),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        children: <Widget>[
          FitCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(l10n.t('profilePrivacy'), style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.t('progressPhotosPrivate'),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Your workouts, nutrition logs, measurements and FitCoach '
                  'conversations are visible only to you. Administrators can see '
                  'account-level counts for support, never the content itself.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg),
          FitCard(
            onTap: () => _openUrl('${Env.appPublicUrl}/privacy'),
            child: Row(
              children: <Widget>[
                const Icon(Icons.description_outlined, size: 20),
                const SizedBox(width: AppSpacing.lg),
                Expanded(child: Text(l10n.t('profilePrivacyPolicy'))),
                const Icon(Icons.open_in_new_rounded, size: 18),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          FitCard(
            onTap: () => _openUrl('${Env.appPublicUrl}/terms'),
            child: Row(
              children: <Widget>[
                const Icon(Icons.gavel_rounded, size: 20),
                const SizedBox(width: AppSpacing.lg),
                Expanded(child: Text(l10n.t('profileTerms'))),
                const Icon(Icons.open_in_new_rounded, size: 18),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg),
          FitCard(
            onTap: () => _openUrl('${Env.apiV1}/profile/export'),
            child: Row(
              children: <Widget>[
                const Icon(Icons.download_outlined, size: 20),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(l10n.t('profileExportData')),
                      Text(
                        'A complete JSON file of everything stored for your account.',
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.xxl),
          FitCard(
            borderColor: context.fitColors.danger.withValues(alpha: 0.5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  l10n.t('profileDeleteAccount'),
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: context.fitColors.danger),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.t('profileDeleteWarning'),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.lg),
                OutlinedButton(
                  onPressed: () => _confirmDelete(context, ref),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.fitColors.danger,
                    side: BorderSide(color: context.fitColors.danger),
                  ),
                  child: Text(l10n.t('profileDeleteAccount')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final AppLocalizations l10n = context.l10n;
    final TextEditingController password = TextEditingController();

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(l10n.t('profileDeleteAccount')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(l10n.t('profileDeleteWarning')),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: password,
              obscureText: true,
              decoration: InputDecoration(labelText: l10n.t('authPassword')),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.t('actionCancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.fitColors.danger,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.t('actionDelete')),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      final bool deleted = await ref
          .read(authControllerProvider.notifier)
          .deleteAccount(password: password.text);
      if (!deleted && context.mounted) {
        AppToast.error(context, l10n.t('errorGeneric'));
      }
    }
    password.dispose();
  }
}
