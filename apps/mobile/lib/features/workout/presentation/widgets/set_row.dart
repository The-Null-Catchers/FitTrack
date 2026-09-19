import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/units.dart';
import '../../domain/workout_models.dart';

/// One row of the set-logging grid.
///
/// The row is the whole interaction: type the numbers, tap the check. Fields
/// keep their own controllers so typing never rebuilds the list, and the check
/// is a 48pt target because it gets pressed with tired hands mid-set.
class SetRow extends StatefulWidget {
  const SetRow({
    super.key,
    required this.set,
    required this.trackingType,
    required this.imperial,
    required this.previousSet,
    required this.onComplete,
    required this.onChanged,
    required this.onRemove,
    required this.onTypeChanged,
  });

  final WorkoutSet set;
  final String trackingType;
  final bool imperial;
  final WorkoutSet? previousSet;

  /// Called with the current field values when the check is tapped.
  final void Function({double? weightKg, int? reps, int? durationSeconds})
      onComplete;
  final void Function({double? weightKg, int? reps, int? durationSeconds})
      onChanged;
  final VoidCallback onRemove;
  final ValueChanged<String> onTypeChanged;

  @override
  State<SetRow> createState() => _SetRowState();
}

class _SetRowState extends State<SetRow> {
  late final TextEditingController _primary =
      TextEditingController(text: _primaryInitial());
  late final TextEditingController _secondary =
      TextEditingController(text: _secondaryInitial());

  bool _primaryHasFocus = false;
  bool _secondaryHasFocus = false;

  String _primaryInitial() {
    if (widget.trackingType == 'duration') {
      return widget.set.durationSeconds?.toString() ?? '';
    }
    final double? weight = widget.set.weightKg;
    if (weight == null) return '';
    final double display = widget.imperial ? Units.kgToLb(weight) : weight;
    return display.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
  }

  String _secondaryInitial() => widget.set.reps?.toString() ?? '';

  @override
  void didUpdateWidget(SetRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep the fields in step when the set changes from elsewhere (an undo, a
    // sync) — but never while the user is typing in them.
    if (oldWidget.set.weightKg != widget.set.weightKg && !_primaryHasFocus) {
      _primary.text = _primaryInitial();
    }
    if (oldWidget.set.reps != widget.set.reps && !_secondaryHasFocus) {
      _secondary.text = _secondaryInitial();
    }
  }

  @override
  void dispose() {
    _primary.dispose();
    _secondary.dispose();
    super.dispose();
  }

  double? get _weightKg {
    final double? entered =
        double.tryParse(_primary.text.trim().replaceAll(',', '.'));
    if (entered == null) return null;
    return widget.imperial ? Units.lbToKg(entered) : entered;
  }

  int? get _reps => int.tryParse(_secondary.text.trim());

  int? get _durationSeconds => int.tryParse(_primary.text.trim());

  void _emitChange() {
    if (widget.trackingType == 'duration') {
      widget.onChanged(durationSeconds: _durationSeconds);
      return;
    }
    widget.onChanged(weightKg: _weightKg, reps: _reps);
  }

  void _complete() {
    HapticFeedback.selectionClick();
    FocusScope.of(context).unfocus();
    if (widget.trackingType == 'duration') {
      widget.onComplete(durationSeconds: _durationSeconds);
      return;
    }
    widget.onComplete(weightKg: _weightKg, reps: _reps);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final FitColorsExtension colors = context.fitColors;
    final bool completed = widget.set.isCompleted;
    final bool showReps =
        widget.trackingType != 'duration' && widget.trackingType != 'distance';

    return Dismissible(
      key: ValueKey<String>('set-${widget.set.localId}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        color: colors.danger.withValues(alpha: 0.15),
        child: Icon(Icons.delete_outline_rounded, color: colors.danger),
      ),
      onDismissed: (_) => widget.onRemove(),
      child: Container(
        color: completed
            ? colors.success.withValues(alpha: 0.07)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          children: <Widget>[
            // Set number — long-press to change the set's type.
            SizedBox(
              width: 34,
              child: GestureDetector(
                onLongPress: () => _showTypeSheet(context),
                child: _SetBadge(set: widget.set),
              ),
            ),
            SizedBox(
              width: 62,
              child: Text(
                _previousLabel(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.textMuted,
                  fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              child: Focus(
                onFocusChange: (bool hasFocus) => _primaryHasFocus = hasFocus,
                child: _CompactField(
                  controller: _primary,
                  hint: widget.trackingType == 'duration'
                      ? l10n.t('workoutDuration')
                      : (widget.imperial
                          ? l10n.t('commonLb')
                          : l10n.t('commonKg')),
                  onChanged: (_) => _emitChange(),
                  allowDecimal: widget.trackingType != 'duration',
                ),
              ),
            ),
            if (showReps) ...<Widget>[
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Focus(
                  onFocusChange: (bool hasFocus) => _secondaryHasFocus = hasFocus,
                  child: _CompactField(
                    controller: _secondary,
                    hint: l10n.t('workoutReps'),
                    onChanged: (_) => _emitChange(),
                    allowDecimal: false,
                  ),
                ),
              ),
            ],
            const SizedBox(width: AppSpacing.sm),
            IconButton(
              onPressed: _complete,
              tooltip: '${l10n.t('workoutSet')} ${widget.set.setNumber}',
              iconSize: 26,
              constraints: const BoxConstraints(
                minWidth: AppSpacing.minTouchTarget,
                minHeight: AppSpacing.minTouchTarget,
              ),
              icon: Icon(
                completed
                    ? Icons.check_circle_rounded
                    : Icons.check_circle_outline_rounded,
                color: completed ? colors.success : colors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _previousLabel() {
    final WorkoutSet? previous = widget.previousSet;
    if (previous == null) return '—';
    if (widget.trackingType == 'duration') {
      return Units.duration(previous.durationSeconds);
    }
    if (previous.weightKg == null) return '${previous.reps ?? '—'}';
    final String weight = Units.weight(
      previous.weightKg,
      imperial: widget.imperial,
      withUnit: false,
    );
    return '$weight × ${previous.reps ?? '—'}';
  }

  Future<void> _showTypeSheet(BuildContext context) async {
    final AppLocalizations l10n = context.l10n;
    final List<List<String>> options = <List<String>>[
      <String>['normal', l10n.t('workoutSet')],
      <String>['warmup', l10n.t('workoutWarmUp')],
      <String>['drop', l10n.t('workoutDropSet')],
      <String>['failure', l10n.t('workoutToFailure')],
    ];

    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: options
              .map(
                (List<String> option) => ListTile(
                  title: Text(option[1]),
                  trailing: widget.set.setType == option[0]
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () {
                    widget.onTypeChanged(option[0]);
                    Navigator.of(sheetContext).pop();
                  },
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _SetBadge extends StatelessWidget {
  const _SetBadge({required this.set});

  final WorkoutSet set;

  @override
  Widget build(BuildContext context) {
    final FitColorsExtension colors = context.fitColors;
    late final String label;
    late final Color color;

    switch (set.setType) {
      case 'warmup':
        label = 'W';
        color = colors.warning;
      case 'drop':
        label = 'D';
        color = colors.info;
      case 'failure':
        label = 'F';
        color = colors.danger;
      default:
        label = '${set.setNumber}';
        color = colors.textMuted;
    }

    return Center(
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelMedium
            ?.copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _CompactField extends StatelessWidget {
  const _CompactField({
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.allowDecimal,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final bool allowDecimal;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textAlign: TextAlign.center,
      keyboardType: TextInputType.numberWithOptions(decimal: allowDecimal),
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(
          allowDecimal ? RegExp(r'[\d.,]') : RegExp(r'\d'),
        ),
      ],
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.md,
        ),
      ),
    );
  }
}
