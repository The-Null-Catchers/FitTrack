import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/state_views.dart';
import '../application/coach_controller.dart';
import '../domain/coach_models.dart';

/// FitCoach chat.
///
/// The standing disclaimer is always visible — FitCoach gives general fitness
/// information, and anything that reads as pain, injury or a medical condition
/// is answered by pointing to a professional before any model is called.
class CoachScreen extends ConsumerStatefulWidget {
  const CoachScreen({super.key});

  @override
  ConsumerState<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends ConsumerState<CoachScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send([String? preset]) {
    final String text = preset ?? _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    ref.read(coachProvider.notifier).send(text);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 200,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final CoachState state = ref.watch(coachProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('coachTitle')),
        actions: <Widget>[
          IconButton(
            onPressed: () => context.pushNamed(Routes.planGenerator),
            tooltip: l10n.t('coachGeneratePlan'),
            icon: const Icon(Icons.auto_awesome_rounded),
          ),
          IconButton(
            onPressed: () => ref.read(coachProvider.notifier).startNewConversation(),
            tooltip: l10n.t('actionAdd'),
            icon: const Icon(Icons.add_comment_outlined),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: state.isEmpty
                ? _EmptyCoach(onSuggestion: _send)
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(AppSpacing.screenPadding),
                    itemCount: state.messages.length + (state.isSending ? 1 : 0),
                    itemBuilder: (BuildContext context, int index) {
                      if (index >= state.messages.length) {
                        return const _TypingBubble();
                      }
                      return _MessageBubble(message: state.messages[index]);
                    },
                  ),
          ),
          if (state.errorMessage != null)
            Container(
              width: double.infinity,
              color: context.fitColors.danger.withValues(alpha: 0.1),
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(
                state.errorMessage!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: context.fitColors.danger),
              ),
            ),
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            child: Text(
              state.disclaimer.isEmpty ? l10n.t('coachDisclaimer') : state.disclaimer,
              style: Theme.of(context).textTheme.labelSmall,
              textAlign: TextAlign.center,
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: l10n.t('coachPlaceholder'),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  IconButton.filled(
                    onPressed: state.isSending ? null : () => _send(),
                    icon: const Icon(Icons.arrow_upward_rounded),
                    tooltip: l10n.t('actionConfirm'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCoach extends StatelessWidget {
  const _EmptyCoach({required this.onSuggestion});

  final ValueChanged<String> onSuggestion;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      children: <Widget>[
        const SizedBox(height: AppSpacing.xxl),
        Icon(
          Icons.auto_awesome_rounded,
          size: 40,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          l10n.t('coachEmptyTitle'),
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          l10n.t('coachEmptyBody'),
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xxl),
        for (final String key in <String>[
          'coachSuggestion1',
          'coachSuggestion2',
          'coachSuggestion3',
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: OutlinedButton(
              onPressed: () => onSuggestion(l10n.t(key)),
              child: Text(l10n.t(key), textAlign: TextAlign.center),
            ),
          ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final CoachMessage message;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isUser = message.isUser;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Align(
        alignment:
            isUser ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.82,
          ),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: isUser
                  ? theme.colorScheme.primary
                  : (message.safetyRedirect
                      ? context.fitColors.warning.withValues(alpha: 0.12)
                      : theme.colorScheme.surface),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: isUser
                  ? null
                  : Border.all(
                      color: message.safetyRedirect
                          ? context.fitColors.warning.withValues(alpha: 0.5)
                          : theme.colorScheme.outline,
                    ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (message.safetyRedirect)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.medical_information_outlined,
                          size: 16,
                          color: context.fitColors.warning,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          context.l10n.t('coachDisclaimer'),
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: context.fitColors.warning),
                        ),
                      ],
                    ),
                  ),
                Text(
                  message.content,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isUser ? theme.colorScheme.onPrimary : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
