/// Customization picture library. `bloom.json` is rewritten whole per edit, and
/// a couple of base64 wallpapers would turn each library save into megabytes.
/// So the file is copied to the app's directory and JSON keeps just a link,
/// `local:<file name>`, the scheme `coverImage` understands. A picture by link
/// stays its http(s) address.
///
/// Blur and dim belong to EACH PICTURE: its page shows them beside its preview,
/// and a wallpaper remembers its setup even while another is the background.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/store/cover_store.dart';
import '../../core/store/json_store.dart' show jsonStoreProvider;

/// Slider bounds on the picture's page.
const double kBgBlurMax = 80;
const double kBgDimMax = 100;

/// A library picture.
class MediaItem {
  const MediaItem({
    required this.id,
    required this.name,
    required this.src,
    this.blur = 0,
    this.dim = 0,
    this.addedAt = 0,
  });

  final String id;

  /// File name or the link's last segment, the caption under the preview.
  final String name;

  /// `local:<name>` (a file in the app's directory) or an http(s) link;
  /// `coverImage` expands both.
  final String src;

  /// Background blur, 0…[kBgBlurMax] px. Works only when this picture is the
  /// background.
  final double blur;

  /// Background dim, 0…[kBgDimMax] %.
  final double dim;

  final int addedAt;

  bool get isLocal => isLocalCover(src);

  MediaItem copyWith({double? blur, double? dim}) => MediaItem(
    id: id,
    name: name,
    src: src,
    blur: blur ?? this.blur,
    dim: dim ?? this.dim,
    addedAt: addedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'src': src,
    'blur': blur,
    'dim': dim,
    'addedAt': addedAt,
  };

  /// `null` for an entry with no picture link: nothing to show.
  static MediaItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final src = raw['src'];
    if (id is! String || src is! String || src.isEmpty) return null;
    final name = raw['name'];
    final blur = raw['blur'];
    final dim = raw['dim'];
    final addedAt = raw['addedAt'];
    return MediaItem(
      id: id,
      name: name is String && name.isNotEmpty ? name : 'image',
      src: src,
      blur: blur is num ? blur.toDouble().clamp(0, kBgBlurMax) : 0,
      dim: dim is num ? dim.toDouble().clamp(0, kBgDimMax) : 0,
      addedAt: addedAt is num ? addedAt.toInt() : 0,
    );
  }
}

/// An http(s) link to a picture; only those are allowed.
bool isImageUrl(String value) =>
    RegExp(r'^https?://.+', caseSensitive: false).hasMatch(value.trim());

/// Name from a link: the last segment with no query.
String urlName(String url) {
  final tail = url.split('/').last.split('?').first;
  return tail.isEmpty ? 'image' : tail;
}

final mediaLibProvider = NotifierProvider<MediaLibController, List<MediaItem>>(
  MediaLibController.new,
);

class MediaLibController extends Notifier<List<MediaItem>> {
  static const _key = 'media';

  @override
  List<MediaItem> build() => [
    for (final raw in ref.read(jsonStoreProvider).readList(_key))
      ?MediaItem.fromJson(raw),
  ];

  MediaItem? byId(String? id) {
    if (id == null) return null;
    for (final item in state) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// Picks gallery pictures and stores them. Returns how many were added (0 if
  /// cancelled or denied).
  ///
  /// No size limit and no quality change: `image_picker` with `maxWidth` or
  /// `imageQuality` recompresses to JPEG and a GIF arrives as one frame, and
  /// GIFs are the point here. Wallpapers come one at a time, not by the hundred
  /// like covers.
  Future<int> addFromGallery() async {
    final List<XFile> picked;
    try {
      picked = await ImagePicker().pickMultiImage(
        requestFullMetadata: kPickMetadata,
      );
    } catch (_) {
      return 0; // gallery access denied
    }
    if (picked.isEmpty) return 0;
    final added = <MediaItem>[];
    for (final file in picked) {
      final src = await copyLocalFile(File(file.path), prefix: 'media');
      if (src == null) continue;
      added.add(
        MediaItem(
          id: _genId(),
          name: file.name,
          src: src,
          addedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }
    if (added.isEmpty) return 0;
    state = [...state, ...added];
    _save();
    return added.length;
  }

  /// Adds by link. `false` if the link doesn't look like a picture.
  bool addUrl(String url) {
    final value = url.trim();
    if (!isImageUrl(value)) return false;
    state = [
      ...state,
      MediaItem(
        id: _genId(),
        name: urlName(value),
        src: value,
        addedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    ];
    _save();
    return true;
  }

  /// Puts a picture from a preset file in the library: a `data:` string goes to
  /// a file, a link as is. Duplicates separate by `src`, so importing one file
  /// twice makes no copies. Returns the picture's library id; `null` if
  /// unparseable.
  Future<String?> ensureImage(
    String data, {
    String name = 'preset',
    double blur = 0,
    double dim = 0,
  }) async {
    String? src;
    var itemName = name;
    if (isImageUrl(data)) {
      src = data.trim();
      itemName = urlName(src);
    } else if (data.startsWith('data:')) {
      final comma = data.indexOf(',');
      if (comma < 0) return null;
      final header = data.substring(5, comma);
      if (!header.contains('base64')) return null;
      try {
        final bytes = base64Decode(data.substring(comma + 1));
        final mime = header.split(';').first;
        src = await saveLocalImage(
          bytes,
          prefix: 'media',
          ext: _extOfMime(mime),
        );
      } catch (_) {
        return null;
      }
    }
    if (src == null) return null;

    for (final item in state) {
      if (item.src == src) return item.id;
    }
    final item = MediaItem(
      id: _genId(),
      name: itemName,
      src: src,
      blur: blur.clamp(0, kBgBlurMax),
      dim: dim.clamp(0, kBgDimMax),
      addedAt: DateTime.now().millisecondsSinceEpoch,
    );
    state = [...state, item];
    _save();
    return item.id;
  }

  void setBlur(String id, double px) =>
      _patch(id, (item) => item.copyWith(blur: px.clamp(0, kBgBlurMax)));

  void setDim(String id, double pct) =>
      _patch(id, (item) => item.copyWith(dim: pct.clamp(0, kBgDimMax)));

  /// Deletes a picture. The file goes too, but the caller does the cascade over
  /// contexts and presets (`removeMedia`): stores don't know about each other.
  void remove(String id) {
    final item = byId(id);
    if (item == null) return;
    state = [
      for (final other in state)
        if (other.id != id) other,
    ];
    _save();
    if (item.isLocal) unawaited(deleteCover(item.src));
  }

  void _patch(String id, MediaItem Function(MediaItem) f) {
    if (byId(id) == null) return;
    state = [
      for (final item in state)
        if (item.id == id) f(item) else item,
    ];
    _save();
  }

  void _save() => ref.read(jsonStoreProvider).write(_key, [
    for (final item in state) item.toJson(),
  ]);
}

String _extOfMime(String mime) => switch (mime) {
  'image/png' => 'png',
  'image/gif' => 'gif',
  'image/webp' => 'webp',
  _ => 'jpg',
};

/// Separates ids of pictures added in one millisecond: picking several at once
/// is common, with no need for `Random`.
int _seq = 0;

String _genId() => 'ml${DateTime.now().millisecondsSinceEpoch}_${_seq++}';
