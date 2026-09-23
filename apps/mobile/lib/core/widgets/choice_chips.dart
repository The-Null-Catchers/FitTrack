import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// A wrapped set of single-select chips.
class SingleChoiceChips<T> extends StatelessWidget {
  const SingleChoiceChips({
    super.key,
    required this.values,
    required this.selected,
    required this.labelBuilder,
    required this.onSelected,
    this.iconBuilder,
  });

  final List<T> values;
  final T? selected;
  final String Function(T value) labelBuilder;
  final IconData? Function(T value)? iconBuilder;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: values.map((T value) {
        final bool isSelected = value == selected;
        final IconData? icon = iconBuilder?.call(value);
        return ChoiceChip(
          selected: isSelected,
          onSelected: (_) => onSelected(value),
          avatar: icon == null ? null : Icon(icon, size: 16),
          label: Text(labelBuilder(value)),
          showCheckmark: icon == null,
        );
      }).toList(),
    );
  }
}

/// A wrapped set of multi-select chips.
class MultiChoiceChips<T> extends StatelessWidget {
  const MultiChoiceChips({
    super.key,
    required this.values,
    required this.selected,
    required this.labelBuilder,
    required this.onChanged,
  });

  final List<T> values;
  final Set<T> selected;
  final String Function(T value) labelBuilder;
  final ValueChanged<Set<T>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: values.map((T value) {
        final bool isSelected = selected.contains(value);
        return FilterChip(
          selected: isSelected,
          label: Text(labelBuilder(value)),
          onSelected: (bool nowSelected) {
            final Set<T> next = Set<T>.of(selected);
            if (nowSelected) {
              next.add(value);
            } else {
              next.remove(value);
            }
            onChanged(next);
          },
        );
      }).toList(),
    );
  }
}

/// A horizontal segmented selector for short, mutually exclusive options.
class SegmentedSelector<T> extends StatelessWidget {
  const SegmentedSelector({
    super.key,
    required this.values,
    required this.selected,
    required this.labelBuilder,
    required this.onSelected,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) labelBuilder;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      child: SegmentedButton<T>(
        segments: values
            .map(
              (T value) => ButtonSegment<T>(
                value: value,
                label: Text(labelBuilder(value)),
              ),
            )
            .toList(),
        selected: <T>{selected},
        showSelectedIcon: false,
        onSelectionChanged: (Set<T> next) => onSelected(next.first),
      ),
    );
  }
}
