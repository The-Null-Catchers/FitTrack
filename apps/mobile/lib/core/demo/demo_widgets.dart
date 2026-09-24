import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_controller.dart';
import '../localization/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'demo_mode.dart';

/// Enters demo mode: bundled data, no account, no network.
///
/// Turning demo mode on swaps the API transport, then signs in through the
/// ordinary auth flow — the credentials are ignored by the bundled-data
/// adapter, so no password is checked and nothing leaves the device.
class DemoModeButton extends ConsumerStatefulWidget {
  const DemoModeButton({super.key});

  @override
  ConsumerState<DemoModeButton> createState() => _DemoModeButtonState();
}

class _DemoModeButtonState extends ConsumerState<DemoModeButton> {
  bool _busy = false;

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      await ref.read(demoControllerProvider.notifier).enable();
      await ref.read(authControllerProvider.notifier).signIn(
            email: 'demo@fittrack.app',
            password: 'demo',
          );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TextButton(
          onPressed: _busy ? null : _start,
          child: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(context.l10n.t('demoExplore')),
        ),
        Text(
          context.l10n.t('demoExploreHint'),
          style: theme.textTheme.bodySmall
              ?.copyWith(color: context.fitColors.textMuted),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// A slim strip shown while demo mode is on, so it is never ambiguous whether
/// what you are looking at is real.
class DemoBanner extends ConsumerWidget {
  const DemoBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(isDemoProvider)) return const SizedBox.shrink();
    final ThemeData theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.tertiaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.xs),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.science_outlined,
                  size: 16, color: theme.colorScheme.onTertiaryContainer),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  context.l10n.t('demoBanner'),
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.onTertiaryContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
