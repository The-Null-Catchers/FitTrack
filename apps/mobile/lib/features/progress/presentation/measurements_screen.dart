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

class MeasurementsScreen extends ConsumerStatefulWidget {
  const MeasurementsScreen({super.key});

  @override
  ConsumerState<MeasurementsScreen> createState() => _MeasurementsScreenState();
}

class _MeasurementsScreenState extends ConsumerState<MeasurementsScreen> {
  static const List<String> _types = <String>[
    'waist',
    'chest',
    'left_arm',
    'right_arm',
    'left_thigh',
    'right_thigh',
    'hips',
    'neck',
    'shoulders',
  ];

  String? _filter;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<List<MeasurementEntry>> entries =
        ref.watch(measurementsProvider(_filter));
    final bool imperial = ref.watch(useImperialProvider);
    final String locale = Localizations.localeOf(context).languageCode;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('progressMeasurements'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEntrySheet(imperial),
        icon: const Icon(Icons.add_rounded),
        label: Text(l10n.t('homeAddMeasurement')),
      ),
      body: Column(
        children: <Widget>[
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenPadding,
                vertical: AppSpacing.sm,
              ),
              children: <Widget>[
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: AppSpacing.sm),
                  child: FilterChip(
                    label: Text(l10n.t('actionSeeAll')),
                    selected: _filter == null,
                    onSelected: (_) => setState(() => _filter = null),
                  ),
                ),
                for (final String type in _types)
                  Padding(
                    padding:
                        const EdgeInsetsDirectional.only(end: AppSpacing.sm),
                    child: FilterChip(
                      label: Text(_label(type)),
                      selected: _filter == type,
                      onSelected: (bool selected) =>
                          setState(() => _filter = selected ? type : null),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: entries.when(
              loading: () => const SkeletonList(itemHeight: 56),
              error: (Object error, StackTrace _) => ErrorStateView(
                message: l10n.t('errorGeneric'),
                onRetry: () => ref.invalidate(measurementsProvider(_filter)),
              ),
              data: (List<MeasurementEntry> list) {
                if (list.isEmpty) {
                  return EmptyStateView(
                    icon: Icons.straighten_rounded,
                    title: l10n.t('progressNoData'),
                    message: l10n.t('progressNoDataBody'),
                  );
                }
                final List<MeasurementEntry> ordered = list.reversed.toList();
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: ordered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    final MeasurementEntry entry = ordered[index];
                    return ListTile(
                      title: Text(_label(entry.measurementType)),
                      subtitle: Text(
                        Formatters.fullDate(entry.recordedOn, locale),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      trailing: Text(
                        Units.length(entry.valueCm, imperial: imperial),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _label(String value) => value
      .split('_')
      .map((String part) =>
          part.isEmpty ? part : part[0].toUpperCase() + part.substring(1))
      .join(' ');

  Future<void> _showEntrySheet(bool imperial) async {
    final AppLocalizations l10n = context.l10n;
    final TextEditingController controller = TextEditingController();
    String type = _filter ?? _types.first;

    final double? entered = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => StatefulBuilder(
        builder: (BuildContext builderContext, StateSetter setSheetState) =>
            Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.screenPadding,
            right: AppSpacing.screenPadding,
            top: AppSpacing.lg,
            bottom:
                MediaQuery.viewInsetsOf(builderContext).bottom + AppSpacing.xxl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                l10n.t('homeAddMeasurement'),
                style: Theme.of(builderContext).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.lg),
              DropdownButtonFormField<String>(
                value: type,
                decoration:
                    InputDecoration(labelText: l10n.t('progressMeasurements')),
                items: _types
                    .map((String value) => DropdownMenuItem<String>(
                          value: value,
                          child: Text(_label(value)),
                        ))
                    .toList(),
                onChanged: (String? value) =>
                    setSheetState(() => type = value ?? type),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: l10n.t('progressMeasurements'),
                  suffixText:
                      imperial ? l10n.t('commonIn') : l10n.t('commonCm'),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton(
                onPressed: () => Navigator.of(builderContext).pop(
                  double.tryParse(controller.text.trim().replaceAll(',', '.')),
                ),
                child: Text(l10n.t('actionSave')),
              ),
            ],
          ),
        ),
      ),
    );
    controller.dispose();

    if (entered == null || entered <= 0) return;
    final double centimetres = imperial ? Units.inchToCm(entered) : entered;

    try {
      await ref.read(progressRepositoryProvider).logMeasurement(
            recordedOn: DateTime.now(),
            measurementType: type,
            valueCm: centimetres,
            clientUuid: 'measure-${DateTime.now().microsecondsSinceEpoch}',
          );
      ref.invalidate(measurementsProvider(_filter));
      ref.invalidate(measurementsProvider(null));
    } on Object {
      if (mounted) {
        AppToast.error(context, l10n.t('errorSaveFailed'));
      }
    }
  }
}
