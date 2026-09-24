import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Renders a progress photo from wherever it actually lives.
///
/// Online, photos come back as short-lived signed https URLs. Offline they are
/// files in the app's own storage, addressed with `file://` — and
/// [CachedNetworkImage] cannot read those, so it would show a broken image.
/// Switching on the scheme keeps one widget working for both.
class ProgressImage extends StatelessWidget {
  const ProgressImage({
    required this.url,
    this.fit = BoxFit.cover,
    super.key,
  });

  final String url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    Widget broken() => ColoredBox(
          color: theme.colorScheme.surfaceContainerHighest,
          child: Icon(Icons.broken_image_outlined,
              color: theme.colorScheme.onSurfaceVariant),
        );

    if (url.startsWith('file://') || url.startsWith('/')) {
      final String path =
          url.startsWith('file://') ? Uri.parse(url).toFilePath() : url;
      final File file = File(path);
      if (!file.existsSync()) return broken();
      return Image.file(file, fit: fit, errorBuilder: (_, __, ___) => broken());
    }

    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      placeholder: (_, __) =>
          ColoredBox(color: theme.colorScheme.surfaceContainerHighest),
      errorWidget: (_, __, ___) => broken(),
    );
  }
}
