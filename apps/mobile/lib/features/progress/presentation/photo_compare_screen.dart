import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/progress_image.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/fit_card.dart';
import '../../../core/widgets/state_views.dart';
import '../application/progress_providers.dart';
import '../domain/progress_models.dart';

/// Side-by-side comparison of two progress photos.
class PhotoCompareScreen extends ConsumerStatefulWidget {
  const PhotoCompareScreen({super.key});

  @override
  ConsumerState<PhotoCompareScreen> createState() => _PhotoCompareScreenState();
}

class _PhotoCompareScreenState extends ConsumerState<PhotoCompareScreen> {
  ProgressPhoto? _before;
  ProgressPhoto? _after;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<List<ProgressPhoto>> photos =
        ref.watch(progressPhotosProvider(null));
    final String locale = Localizations.localeOf(context).languageCode;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('progressCompare'))),
      body: photos.when(
        loading: () => const SkeletonList(itemHeight: 120),
        error: (Object error, StackTrace _) => ErrorStateView(
          message: l10n.t('errorGeneric'),
          onRetry: () => ref.invalidate(progressPhotosProvider(null)),
        ),
        data: (List<ProgressPhoto> list) {
          if (list.length < 2) {
            return EmptyStateView(
              icon: Icons.compare_rounded,
              title: l10n.t('progressNoData'),
              message: l10n.t('progressNoDataBody'),
            );
          }

          // Default to the oldest and newest, which is the comparison people
          // almost always want first.
          final List<ProgressPhoto> sorted = List<ProgressPhoto>.of(list)
            ..sort((ProgressPhoto a, ProgressPhoto b) =>
                a.takenOn.compareTo(b.takenOn));
          _before ??= sorted.first;
          _after ??= sorted.last;

          final int days = _after!.takenOn.difference(_before!.takenOn).inDays;
          final double? weightChange =
              (_before!.weightKg != null && _after!.weightKg != null)
                  ? _after!.weightKg! - _before!.weightKg!
                  : null;

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: _ComparePane(
                      photo: _before!,
                      locale: locale,
                      onPick: () => _pick(sorted, isBefore: true),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _ComparePane(
                      photo: _after!,
                      locale: locale,
                      onPick: () => _pick(sorted, isBefore: false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              FitCard(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: <Widget>[
                    StatTile(
                      label: l10n.t('progressCompare'),
                      value: '$days ${l10n.t('daysPerWeek', <String, Object?>{
                            'count': ''
                          }).trim()}',
                    ),
                    if (weightChange != null)
                      StatTile(
                        label: l10n.t('progressWeight'),
                        value:
                            '${weightChange > 0 ? '+' : ''}${weightChange.toStringAsFixed(1)} kg',
                        tone: weightChange < 0
                            ? context.fitColors.success
                            : context.fitColors.info,
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _pick(
    List<ProgressPhoto> photos, {
    required bool isBefore,
  }) async {
    final String locale = Localizations.localeOf(context).languageCode;
    final ProgressPhoto? picked = await showModalBottomSheet<ProgressPhoto>(
      context: context,
      builder: (BuildContext sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: photos
              .map(
                (ProgressPhoto photo) => ListTile(
                  title: Text(Formatters.fullDate(photo.takenOn, locale)),
                  subtitle: Text(photo.pose),
                  onTap: () => Navigator.of(sheetContext).pop(photo),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isBefore) {
        _before = picked;
      } else {
        _after = picked;
      }
    });
  }
}

class _ComparePane extends StatelessWidget {
  const _ComparePane({
    required this.photo,
    required this.locale,
    required this.onPick,
  });

  final ProgressPhoto photo;
  final String locale;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AspectRatio(
          aspectRatio: 0.72,
          child: GestureDetector(
            onTap: onPick,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: photo.url == null
                  ? ColoredBox(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                    )
                  : ProgressImage(url: photo.url!),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          Formatters.dayMonth(photo.takenOn, locale),
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ],
    );
  }
}
