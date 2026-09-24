import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

/// Backing data for demo mode.
///
/// `assets/demo/seed.json` is a capture of real responses from the FitTrack
/// API, so every payload the app parses here has exactly the shape the server
/// produces. Anything the user changes is written into [_overlay] and saved to
/// the app's documents directory, which is what makes edits survive closing
/// and reopening the app.
///
/// Nothing here touches the network.
class DemoStore {
  DemoStore._(this._seed, this._overlay, this._file);

  final Map<String, dynamic> _seed;
  Map<String, dynamic> _overlay;
  final File _file;

  static const String _asset = 'assets/demo/seed.json';
  static const String _fileName = 'fittrack_demo_state.json';

  static Future<DemoStore> open() async {
    final Map<String, dynamic> seed =
        jsonDecode(await rootBundle.loadString(_asset)) as Map<String, dynamic>;
    final Directory dir = await getApplicationDocumentsDirectory();
    final File file = File('${dir.path}/$_fileName');
    Map<String, dynamic> overlay = <String, dynamic>{};
    if (file.existsSync()) {
      try {
        overlay = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      } on Object {
        // A truncated or hand-edited file should not brick the demo; start
        // from the seed instead.
        overlay = <String, dynamic>{};
      }
    }
    return DemoStore._(seed, overlay, file);
  }

  Future<void> _save() async {
    await _file.writeAsString(jsonEncode(_overlay), flush: true);
  }

  /// Drop every local change and go back to the bundled data.
  ///
  /// Photo files are removed too — leaving them would orphan the bytes and
  /// quietly consume storage forever.
  Future<void> reset() async {
    _overlay = <String, dynamic>{};
    if (_file.existsSync()) await _file.delete();
    final Directory photos = Directory('${_file.parent.path}/photos');
    if (photos.existsSync()) await photos.delete(recursive: true);
  }

  /// Everything the user has changed, as a portable JSON document.
  ///
  /// Photos are included as base64 so a restore on a reinstalled app — or a
  /// different phone — brings the images back too, not just the records.
  Future<String> exportJson() async {
    final Map<String, dynamic> photos = <String, dynamic>{};
    for (final Map<String, dynamic> photo in list('photos')) {
      final String? url = photo['url'] as String?;
      if (url == null || !url.startsWith('file://')) continue;
      final File f = File(Uri.parse(url).toFilePath());
      if (f.existsSync()) {
        photos[photo['id'] as String] = base64Encode(await f.readAsBytes());
      }
    }
    return jsonEncode(<String, dynamic>{
      'format': 'fittrack-demo-export',
      'version': 1,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'overlay': _overlay,
      'photo_bytes': photos,
    });
  }

  /// Replace local data with a previously exported document.
  ///
  /// Throws [FormatException] if the file is not one of ours, so the caller
  /// can say so rather than silently wiping good data.
  Future<void> importJson(String raw) async {
    final dynamic decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != 'fittrack-demo-export') {
      throw const FormatException('Not a FitTrack export file');
    }
    final Map<String, dynamic> overlay = Map<String, dynamic>.from(
        decoded['overlay'] as Map<dynamic, dynamic>? ?? <String, dynamic>{});

    // Rewrite photo paths: the documents directory differs between installs,
    // so the exported file:// URLs would otherwise point at nothing.
    final Map<String, dynamic> bytes = Map<String, dynamic>.from(
        decoded['photo_bytes'] as Map<dynamic, dynamic>? ??
            <String, dynamic>{});
    if (bytes.isNotEmpty) {
      final Directory dir = Directory('${_file.parent.path}/photos');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final dynamic stored = overlay['photos'];
      final List<dynamic> items = stored is Map && stored.containsKey('items')
          ? stored['items'] as List<dynamic>
          : (stored as List<dynamic>? ?? <dynamic>[]);
      for (final dynamic item in items) {
        final Map<String, dynamic> photo =
            Map<String, dynamic>.from(item as Map<dynamic, dynamic>);
        final String? b64 = bytes[photo['id']] as String?;
        if (b64 == null) continue;
        final File dest = File('${dir.path}/${photo['id']}.jpg');
        await dest.writeAsBytes(base64Decode(b64), flush: true);
        photo['url'] = dest.uri.toString();
        photo['thumbnail_url'] = dest.uri.toString();
        item as Map<dynamic, dynamic>
          ..clear()
          ..addAll(photo);
      }
    }

    _overlay = overlay;
    await _save();
  }

  // --- reads ---------------------------------------------------------------

  /// Seed value for [key], with any saved changes applied.
  dynamic value(String key) =>
      _overlay.containsKey(key) ? _overlay[key] : _seed[key];

  List<Map<String, dynamic>> list(String key) {
    final dynamic v = value(key);
    final dynamic items =
        v is Map<String, dynamic> && v.containsKey('items') ? v['items'] : v;
    if (items is List) {
      return items
          .map((dynamic e) =>
              Map<String, dynamic>.from(e as Map<dynamic, dynamic>))
          .toList();
    }
    return <Map<String, dynamic>>[];
  }

  Map<String, dynamic>? map(String key) {
    final dynamic v = value(key);
    return v is Map ? Map<String, dynamic>.from(v) : null;
  }

  /// Wraps [items] in the `{items, meta}` envelope the API uses, honouring
  /// `page` / `per_page` so the app's paging behaves as it does online.
  Map<String, dynamic> paged(List<Map<String, dynamic>> items,
      {int page = 1, int perPage = 20}) {
    final int total = items.length;
    final int start = (page - 1) * perPage;
    final List<Map<String, dynamic>> slice = start >= total
        ? <Map<String, dynamic>>[]
        : items.sublist(start, (start + perPage).clamp(0, total));
    final int totalPages =
        perPage <= 0 ? 1 : (total / perPage).ceil().clamp(1, 1 << 30);
    return <String, dynamic>{
      'items': slice,
      'meta': <String, dynamic>{
        'page': page,
        'per_page': perPage,
        'total': total,
        'total_pages': totalPages,
        'has_next': page < totalPages,
        'has_previous': page > 1,
      },
    };
  }

  // --- writes --------------------------------------------------------------

  Future<void> put(String key, dynamic value) async {
    _overlay[key] = value;
    await _save();
  }

  /// Replace the list stored at [key], keeping the seed's envelope shape.
  Future<void> putList(String key, List<Map<String, dynamic>> items) async {
    final dynamic seeded = _seed[key];
    if (seeded is Map && seeded.containsKey('items')) {
      await put(key, <String, dynamic>{
        'items': items,
        'meta': <String, dynamic>{
          'page': 1,
          'per_page': items.length,
          'total': items.length,
          'total_pages': 1,
          'has_next': false,
          'has_previous': false,
        },
      });
    } else {
      await put(key, items);
    }
  }

  /// Insert or replace an entry in the map stored at [key].
  Future<void> putInMap(
      String key, String id, Map<String, dynamic> value) async {
    final Map<String, dynamic> current =
        Map<String, dynamic>.from(map(key) ?? <String, dynamic>{});
    current[id] = value;
    await put(key, current);
  }
}
