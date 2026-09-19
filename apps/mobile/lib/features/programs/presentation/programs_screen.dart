import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/fit_card.dart';
import '../../../core/widgets/state_views.dart';
import '../application/program_providers.dart';
import '../domain/program.dart';

class ProgramsScreen extends ConsumerWidget {
  const ProgramsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<List<Program>> mine = ref.watch(myProgramsProvider);
    final AsyncValue<List<Program>> templates =
        ref.watch(programTemplatesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('programsTitle')),
        actions: <Widget>[
          IconButton(
            onPressed: () => context.pushNamed(Routes.planGenerator),
            tooltip: l10n.t('coachGeneratePlan'),
            icon: const Icon(Icons.auto_awesome_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myProgramsProvider);
          ref.invalidate(programTemplatesProvider);
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.huge),
          children: <Widget>[
            SectionHeader(title: l10n.t('programsMyPlans')),
            mine.when(
              loading: () => const SkeletonList(itemCount: 2, itemHeight: 80),
              error: (Object error, StackTrace _) => ErrorStateView(
                message: l10n.t('errorGeneric'),
                onRetry: () => ref.invalidate(myProgramsProvider),
              ),
              data: (List<Program> programs) {
                if (programs.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.screenPadding,
                    ),
                    child: FitCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            l10n.t('programsNoPlans'),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            l10n.t('programsNoPlansBody'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return Column(
                  children: programs
                      .map((Program program) => Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.screenPadding,
                              0,
                              AppSpacing.screenPadding,
                              AppSpacing.md,
                            ),
                            child: _ProgramCard(program: program),
                          ))
                      .toList(),
                );
              },
            ),
            SectionHeader(
              title: l10n.t('programsTemplates'),
              subtitle: l10n.t('programsNoPlansBody'),
            ),
            templates.when(
              loading: () => const SkeletonList(itemCount: 3, itemHeight: 80),
              error: (Object error, StackTrace _) => ErrorStateView(
                message: l10n.t('errorGeneric'),
                onRetry: () => ref.invalidate(programTemplatesProvider),
              ),
              data: (List<Program> programs) => Column(
                children: programs
                    .map((Program program) => Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.screenPadding,
                            0,
                            AppSpacing.screenPadding,
                            AppSpacing.md,
                          ),
                          child: _ProgramCard(program: program, isTemplate: true),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgramCard extends ConsumerWidget {
  const _ProgramCard({required this.program, this.isTemplate = false});

  final Program program;
  final bool isTemplate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);

    return FitCard(
      onTap: () => context.pushNamed(
        Routes.programDetail,
        pathParameters: <String, String>{'id': program.id},
      ),
      borderColor: program.isActive && !isTemplate
          ? theme.colorScheme.primary
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(program.name, style: theme.textTheme.titleMedium),
              ),
              if (program.isActive && !isTemplate)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    l10n.t('programsActive'),
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.primary),
                  ),
                ),
              if (program.generatedByAi)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: AppSpacing.sm),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    size: 16,
                    color: context.fitColors.info,
                  ),
                ),
            ],
          ),
          if (program.description != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              program.description!,
              style: theme.textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '${l10n.t('programsDayCount', <String, Object?>{'count': program.dayCount})}'
                  ' · ${program.exerciseCount} ${l10n.t('exercisesTitle').toLowerCase()}'
                  '${program.estimatedMinutes != null ? ' · ~${program.estimatedMinutes} min' : ''}',
                  style: theme.textTheme.labelSmall,
                ),
              ),
              if (isTemplate)
                TextButton(
                  onPressed: () => _duplicate(context, ref),
                  child: Text(l10n.t('programsUse')),
                )
              else if (!program.isActive)
                TextButton(
                  onPressed: () => _activate(context, ref),
                  child: Text(l10n.t('programsUse')),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _duplicate(BuildContext context, WidgetRef ref) async {
    try {
      final Program copy =
          await ref.read(programRepositoryProvider).duplicate(program.id);
      await ref.read(programRepositoryProvider).activate(copy.id);
      invalidatePrograms(ref);
      if (context.mounted) {
        AppToast.success(context, '${copy.name} · ${context.l10n.t('programsActive')}');
      }
    } on Object {
      if (context.mounted) {
        AppToast.error(context, context.l10n.t('errorGeneric'));
      }
    }
  }

  Future<void> _activate(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(programRepositoryProvider).activate(program.id);
      invalidatePrograms(ref);
    } on Object {
      if (context.mounted) {
        AppToast.error(context, context.l10n.t('errorGeneric'));
      }
    }
  }
}
