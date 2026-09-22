import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/units.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/state_views.dart';
import '../application/progress_providers.dart';
import '../domain/progress_models.dart';

class WeightLogScreen extends ConsumerWidget {
  const WeightLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<List<BodyWeightEntry>> entries =
        ref.watch(bodyWeightsProvider);
    final bool imperial = ref.watch(useImperialProvider);
    final String locale = Localizations.localeOf(context).languageCode;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('progressWeight'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEntrySheet(context, ref, imperial),
        icon: const Icon(Icons.add_rounded),
        label: Text(l10n.t('homeLogWeight')),
      ),
      body: entries.when(
        loading: () => const SkeletonList(itemHeight: 56),
        error: (Object error, StackTrace _) => ErrorStateView(
          message: l10n.t('errorGeneric'),
          onRetry: () => ref.invalidate(bodyWeightsProvider),
        ),
        data: (List<BodyWeightEntry> list) {
          if (list.isEmpty) {
            return EmptyStateView(
              icon: Icons.monitor_weight_outlined,
              title: l10n.t('progressNoData'),
              message: l10n.t('progressNoDataBody'),
            );
          }
          final List<BodyWeightEntry> ordered = list.reversed.toList();
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: ordered.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (BuildContext context, int index) {
              final BodyWeightEntry entry = ordered[index];
              final BodyWeightEntry? previous =
                  index + 1 < ordered.length ? ordered[index + 1] : null;
              final double? delta =
                  previous == null ? null : entry.weightKg - previous.weightKg;

              return ListTile(
                title: Text(
                  Units.weight(entry.weightKg, imperial: imperial),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                subtitle: Text(
                  Formatters.fullDate(entry.recordedOn, locale),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                trailing: delta == null
                    ? null
                    : Text(
                        '${delta > 0 ? '+' : ''}'
                        '${Units.weight(delta.abs(), imperial: imperial)}',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _showEntrySheet(
    BuildContext context,
    WidgetRef ref,
    bool imperial,
  ) async {
    final TextEditingController controller = TextEditingController();
    final AppLocalizations l10n = context.l10n;

    final double? entered = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.screenPadding,
          right: AppSpacing.screenPadding,
          top: AppSpacing.lg,
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + AppSpacing.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              l10n.t('homeLogWeight'),
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: l10n.t('progressWeight'),
                suffixText: imperial ? l10n.t('commonLb') : l10n.t('commonKg'),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              onPressed: () {
                final double? value = double.tryParse(
                  controller.text.trim().replaceAll(',', '.'),
                );
                Navigator.of(sheetContext).pop(value);
              },
              child: Text(l10n.t('actionSave')),
            ),
          ],
        ),
      ),
    );
    controller.dispose();

    if (entered == null || entered <= 0) return;
    final double kilograms = imperial ? Units.lbToKg(entered) : entered;

    try {
      await ref.read(progressRepositoryProvider).logWeight(
            recordedOn: DateTime.now(),
            weightKg: kilograms,
            clientUuid: 'weight-${DateTime.now().microsecondsSinceEpoch}',
          );
      invalidateProgress(ref);
      if (context.mounted) {
        AppToast.success(context, l10n.t('syncUpToDate'));
      }
    } on Object {
      if (context.mounted) {
        AppToast.error(context, l10n.t('errorSaveFailed'));
      }
    }
  }
}
