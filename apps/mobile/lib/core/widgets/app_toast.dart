import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Transient feedback.
///
/// Toasts are for confirmations and recoverable problems. Anything the user
/// must act on belongs in a dialog or an inline error, not here.
class AppToast {
  const AppToast._();

  static void success(BuildContext context, String message) =>
      _show(context, message, icon: Icons.check_circle_outline_rounded);

  static void error(BuildContext context, String message, {VoidCallback? onRetry}) =>
      _show(
        context,
        message,
        icon: Icons.error_outline_rounded,
        tone: context.fitColors.danger,
        actionLabel: onRetry == null ? null : 'Retry',
        onAction: onRetry,
      );

  static void info(BuildContext context, String message) =>
      _show(context, message, icon: Icons.info_outline_rounded);

  static void _show(
    BuildContext context,
    String message, {
    IconData? icon,
    Color? tone,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 18, color: tone ?? Colors.white),
              const SizedBox(width: AppSpacing.sm),
            ],
            Expanded(child: Text(message)),
          ],
        ),
        duration: const Duration(seconds: 4),
        action: actionLabel == null
            ? null
            : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
      ),
    );
  }
}
