/// User playlist covers: picking from the gallery and storing. The gallery file
/// is copied into the app's directory: what image_picker returns sits in a
/// cache and may vanish, and a cover lives as long as its playlist.
///
/// The playlist stores `local:<file name>`, NOT an absolute path: the iOS app
/// container moves between launches, and today's path points nowhere tomorrow.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show Uint8List;

import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';

import 'app_dirs.dart';
import 'cover_cache.dart';

const String _prefix = 'local:';

Directory? _dir;

/// Prepares the covers directory. Called from `main()` before the first frame:
/// afterwards the path is needed synchronously, in `build`.
Future<void> initCoverStore() async {
  final root = await appPrivateDir();
  final dir = Directory('${root.path}/covers');
  try {
    if (!dir.existsSync()) await dir.create(recursive: true);
    _dir = dir;
  } catch (_) {
    // No write rights: own covers just won't be available.
  }
}

bool isLocalCover(String? cover) => cover != null && cover.startsWith(_prefix);

/// `cover` field value for a picture named [name]. For those placing pictures
/// past these functions: local track covers come out of tags on the native
/// side, and Dart gets a file name.
String localCoverRef(String name) => '$_prefix$name';

/// Directory of own pictures; `null` if it didn't come up. Exposed for the same
/// reason: the native side needs a place to write a tag's cover.
String? coversDirPath() => _dir?.path;

/// Absolute path of an own cover; `null` if it isn't own or the directory
/// didn't come up.
String? localCoverPath(String? cover) {
  final dir = _dir;
  if (dir == null || !isLocalCover(cover)) return null;
  return '${dir.path}/${cover!.substring(_prefix.length)}';
}

/// A cover's picture: one's own from the disk, or a platform's through the
/// cover cache. `null` — no cover.
ImageProvider? coverImage(String? cover) {
  if (cover == null || cover.isEmpty) return null;
  final path = localCoverPath(cover);
  if (path != null) return FileImage(File(path));
  if (isLocalCover(cover)) return null; // one's own, but no folder
  return coverCacheReady ? CachedCover(cover) : NetworkImage(cover);
}

/// Photo metadata (EXIF, date, location) isn't needed. This isn't cosmetic:
/// with `true`, image_picker on iOS 13 goes to `PHPhotoLibrary
/// requestAuthorization`, a system prompt for the WHOLE library that requires
/// `NSPhotoLibraryUsageDescription`. With `false`, iOS 13 opens a plain file
/// picker and iOS 14+ uses `PHPickerViewController`, which asks for no
/// permission.
///
/// If this ever goes back to `true`, add that key to Info.plist, or iOS kills
/// the app on the request.
const bool kPickMetadata = false;

/// Picks a gallery picture and stores it. Returns the `cover` value
/// (`local:...`), or `null` if cancelled. Side capped at 1024 px: a cover needs
/// no more.
Future<String?> pickCover() async {
  final dir = _dir;
  if (dir == null) return null;
  final XFile? picked;
  try {
    picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 90,
      requestFullMetadata: kPickMetadata,
    );
  } catch (_) {
    return null; // gallery access denied
  }
  if (picked == null) return null;
  try {
    final name = 'cover_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await picked.saveTo('${dir.path}/$name');
    return '$_prefix$name';
  } catch (_) {
    return null;
  }
}

/// Picks a gallery picture WITHOUT storing: the path image_picker returned. For
/// pictures still to be cropped (profile avatar and banner): the source is
/// larger than a cover, and only the crop gets stored.
Future<String?> pickImageFile({int maxSide = 2048}) async {
  try {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: maxSide.toDouble(),
      maxHeight: maxSide.toDouble(),
      requestFullMetadata: kPickMetadata,
    );
    return picked?.path;
  } catch (_) {
    return null; // gallery access denied
  }
}

/// Parses `data:image/...;base64,...` into bytes and a file extension. `null`
/// if it isn't a base64 data URL.
///
/// An own picture in a transfer file (presets, playlist cover) travels like
/// this: a file name means nothing on another device.
({Uint8List bytes, String ext})? decodeDataUrl(String value) {
  if (!value.startsWith('data:')) return null;
  final comma = value.indexOf(',');
  if (comma < 0) return null;
  final header = value.substring(5, comma);
  if (!header.contains('base64')) return null;
  try {
    return (
      bytes: base64Decode(value.substring(comma + 1)),
      ext: switch (header.split(';').first) {
        'image/png' => 'png',
        'image/gif' => 'gif',
        'image/webp' => 'webp',
        _ => 'jpg',
      },
    );
  } catch (_) {
    return null;
  }
}

/// The reverse of [decodeDataUrl]: an own picture to a `data:` string. `null`
/// if it isn't own or the file is gone.
Future<String?> encodeLocalImage(String? cover) async {
  final path = localCoverPath(cover);
  if (path == null) return null;
  try {
    final bytes = await File(path).readAsBytes();
    return 'data:${_mimeOfPath(path)};base64,${base64Encode(bytes)}';
  } catch (_) {
    return null;
  }
}

String _mimeOfPath(String path) => switch (path.split('.').last.toLowerCase()) {
  'png' => 'image/png',
  'gif' => 'image/gif',
  'webp' => 'image/webp',
  _ => 'image/jpeg',
};

/// Separates file names written in one millisecond: picking several at once is
/// common, and the second would overwrite the first.
int _copySeq = 0;

/// Stores ready bytes as an app picture. Returns the field value (`local:...`),
/// or `null` on failure. The extension is only for an honest name: Flutter
/// recognises a picture by its bytes, but preset export takes the mime type
/// from the name.
Future<String?> saveLocalImage(
  Uint8List bytes, {
  String prefix = 'img',
  String ext = 'png',
}) async {
  final dir = _dir;
  if (dir == null) return null;
  try {
    final name =
        '${prefix}_${DateTime.now().millisecondsSinceEpoch}_${_copySeq++}.$ext';
    await File('${dir.path}/$name').writeAsBytes(bytes, flush: true);
    return '$_prefix$name';
  } catch (_) {
    return null;
  }
}

/// Copies a ready file AS IS, keeping its extension. Returns the field value,
/// or `null` on failure. Unlike [pickCover], which recompresses to JPEG through
/// `image_picker` with `maxWidth`: a GIF's animation doesn't survive that, and
/// customization pictures need it.
Future<String?> copyLocalFile(File source, {String prefix = 'img'}) async {
  final dir = _dir;
  if (dir == null) return null;
  try {
    final ext = source.path.split('.').last.toLowerCase();
    // I take the extension only if it looks like one: a gallery file may have
    // none, and the whole path would end up in the name.
    final suffix = ext.isNotEmpty && ext.length <= 5 && !ext.contains('/')
        ? '.$ext'
        : '.img';
    final name =
        '${prefix}_${DateTime.now().millisecondsSinceEpoch}_${_copySeq++}$suffix';
    await source.copy('${dir.path}/$name');
    return '$_prefix$name';
  } catch (_) {
    return null;
  }
}

/// Whether something in the database still uses this picture. Set by `main()`:
/// a picture from another device has a hash name, and two playlists or a
/// playlist and the profile may share it.
bool Function(String cover)? coverInUse;

/// Removes an own cover's file, when its playlist is deleted or the cover
/// changes.
Future<void> deleteCover(String? cover) async {
  final path = localCoverPath(cover);
  if (path == null || (coverInUse?.call(cover!) ?? false)) return;
  try {
    final file = File(path);
    if (file.existsSync()) await file.delete();
  } catch (_) {
    // Not removed is no disaster, just junk in the directory.
  }
}
