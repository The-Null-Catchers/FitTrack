import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/widgets/progress_image.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/state_views.dart';
import '../application/progress_providers.dart';
import '../domain/progress_models.dart';

/// Progress photos.
///
/// Photos are private: the API returns short-lived signed URLs, so nothing
/// here is cached beyond the image cache and no raw storage path is ever seen.
class ProgressPhotosScreen extends ConsumerStatefulWidget {
  const ProgressPhotosScreen({super.key});

  @override
  ConsumerState<ProgressPhotosScreen> createState() =>
      _ProgressPhotosScreenState();
}

class _ProgressPhotosScreenState extends ConsumerState<ProgressPhotosScreen> {
  String? _pose;
  bool _isUploading = false;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<List<ProgressPhoto>> photos =
        ref.watch(progressPhotosProvider(_pose));
    final String locale = Localizations.localeOf(context).languageCode;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('progressPhotos')),
        actions: <Widget>[
          IconButton(
            onPressed: () => context.pushNamed(Routes.photoCompare),
            tooltip: l10n.t('progressCompare'),
            icon: const Icon(Icons.compare_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isUploading ? null : _addPhoto,
        icon: _isUploading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add_a_photo_outlined),
        label: Text(l10n.t('progressTakePhoto')),
      ),
      body: Column(
        children: <Widget>[
          Container(
            width: double.infinity,
            color: context.fitColors.info.withValues(alpha: 0.1),
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: <Widget>[
                Icon(Icons.lock_outline_rounded,
                    size: 16, color: context.fitColors.info),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    l10n.t('progressPhotosPrivate'),
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: context.fitColors.info),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenPadding,
                vertical: AppSpacing.sm,
              ),
              children: <Widget>[
                for (final String? pose in <String?>[
                  null,
                  'front',
                  'side',
                  'back',
                ])
                  Padding(
                    padding:
                        const EdgeInsetsDirectional.only(end: AppSpacing.sm),
                    child: FilterChip(
                      label: Text(_poseLabel(pose)),
                      selected: _pose == pose,
                      onSelected: (_) => setState(() => _pose = pose),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: photos.when(
              loading: () => const SkeletonList(itemHeight: 160),
              error: (Object error, StackTrace _) => ErrorStateView(
                message: l10n.t('errorGeneric'),
                onRetry: () => ref.invalidate(progressPhotosProvider(_pose)),
              ),
              data: (List<ProgressPhoto> list) {
                if (list.isEmpty) {
                  return EmptyStateView(
                    icon: Icons.photo_camera_outlined,
                    title: l10n.t('progressPhotos'),
                    message: l10n.t('progressNoDataBody'),
                  );
                }
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenPadding,
                    AppSpacing.md,
                    AppSpacing.screenPadding,
                    96,
                  ),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: AppSpacing.md,
                    crossAxisSpacing: AppSpacing.md,
                    childAspectRatio: 0.72,
                  ),
                  itemCount: list.length,
                  itemBuilder: (BuildContext context, int index) {
                    final ProgressPhoto photo = list[index];
                    return _PhotoTile(photo: photo, locale: locale);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _poseLabel(String? pose) => switch (pose) {
        'front' => context.l10n.t('progressPoseFront'),
        'side' => context.l10n.t('progressPoseSide'),
        'back' => context.l10n.t('progressPoseBack'),
        _ => context.l10n.t('actionSeeAll'),
      };

  Future<void> _addPhoto() async {
    final AppLocalizations l10n = context.l10n;
    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(l10n.t('progressTakePhoto')),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l10n.t('progressChooseFromGallery')),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final XFile? picked = await ImagePicker().pickImage(
      source: source,
      // The server downscales too; sending less over a phone connection is
      // simply faster.
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 88,
    );
    if (picked == null || !mounted) return;

    setState(() => _isUploading = true);
    try {
      await ref.read(progressRepositoryProvider).uploadPhoto(
            file: File(picked.path),
            takenOn: DateTime.now(),
            pose: _pose ?? 'front',
          );
      ref.invalidate(progressPhotosProvider(_pose));
      ref.invalidate(progressPhotosProvider(null));
    } on Object {
      if (mounted) AppToast.error(context, l10n.t('errorSaveFailed'));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.photo, required this.locale});

  final ProgressPhoto photo;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (photo.thumbnailUrl != null || photo.url != null)
            ProgressImage(url: photo.thumbnailUrl ?? photo.url!)
          else
            ColoredBox(color: theme.colorScheme.surfaceContainerHighest),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: <Color>[
                    Colors.black.withValues(alpha: 0.7),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    Formatters.dayMonth(photo.takenOn, locale),
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: Colors.white),
                  ),
                  if (photo.weightKg != null)
                    Text(
                      '${photo.weightKg!.toStringAsFixed(1)} kg',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: Colors.white70),
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
