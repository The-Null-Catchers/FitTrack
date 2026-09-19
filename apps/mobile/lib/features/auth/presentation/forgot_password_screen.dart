import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/validators.dart';
import '../application/auth_controller.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  bool _isSending = false;
  bool _isSent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() => _isSending = true);

    // The API answers identically whether or not the address exists, so the
    // screen does too — a reset form must never confirm an account.
    await ref
        .read(authRepositoryProvider)
        .requestPasswordReset(_email.text)
        .catchError((Object _) {});

    if (mounted) {
      setState(() {
        _isSending = false;
        _isSent = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('authResetPassword'))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: _isSent
              ? Column(
                  children: <Widget>[
                    Icon(
                      Icons.mark_email_read_outlined,
                      size: 44,
                      color: context.fitColors.success,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      l10n.t('authResetSent'),
                      style: theme.textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                  ],
                )
              : Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: l10n.t('authEmail'),
                          prefixIcon: const Icon(Icons.mail_outline_rounded),
                        ),
                        validator: (String? value) {
                          final String? key = Validators.email(value);
                          return key == null ? null : l10n.t(key);
                        },
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      FilledButton(
                        onPressed: _isSending ? null : _submit,
                        child: Text(l10n.t('authResetPassword')),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
