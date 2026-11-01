/// Saving as a file. An offline copy lives inside the app, while this file
/// lands where the user finds it without Bloom.
///
/// The platform decides where. On Android, shared Music/Bloom: system players
/// see it and it survives uninstalling. Shared storage takes writes only
/// through MediaStore, so Kotlin does it ([MediaStoreSaver]). On iOS, the app's
/// `Documents`, shown in Files: there's no shared library for third-party apps,
/// so the file stays in the sandbox but in view. No native code, it's an
/// ordinary directory.
///
/// No where to save dialog on purpose: it's painful on a phone and works badly
/// for a whole playlist, so there's one folder.
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../app/providers.dart';
import '../../core/entities/entities.dart';
import '../../core/store/app_dirs.dart';
import '../../core/store/cover_store.dart';
import '../../core/l10n/l10n.dart';
import 'offline_store.dart';

const MethodChannel _channel = MethodChannel('bloom/downloads');

/// Whether this platform has anywhere outside to save a file.
bool get canSaveFiles => Platform.isAndroid || Platform.isIOS;

/// Where, in plain words, for the snack bar and captions.
String saveTargetLabel(AppLocalizations l) =>
    Platform.isIOS ? l.fdPathIos : l.fdPathAndroid;

/// Saves a track as a file. Returns a path to show the user; `null` means it
/// landed in the default place, and the UI names that (see [saveTargetLabel]).
/// An already downloaded offline track isn't fetched again: the file just
/// copies from the cache, staying there.
Future<String?> saveTrackAsFile(
  WidgetRef ref,
  Track track, {
  void Function(double)? onProgress,
}) async {
  final offline = ref.read(offlineProvider.notifier);
  final cached = offline.pathOf(track.id);

  final String sourcePath;
  final bool deleteSource;
  if (cached != null) {
    sourcePath = cached;
    deleteSource = false;
  } else {
    final provider = ref.read(registryProvider).forEntity(track.id);
    if (provider == null || !provider.canDownload(track)) {
      throw const DownloadFailure(DownloadFailureKind.notDownloadable);
    }
    final stream = await provider.resolveDownload(track);
    if (stream == null) {
      throw const DownloadFailure(DownloadFailureKind.notDownloadable);
    }
    // Temp directory: the file lives until moved to the media library, and the
    // system may clean it up if that doesn't happen.
    final tmp = await getTemporaryDirectory();
    final file = await fetchAudioToFile(
      url: stream.url,
      headers: stream.headers,
      dir: tmp,
      base: trackFileBase(track),
      onProgress: onProgress,
    );
    sourcePath = file.path;
    deleteSource = true;
  }

  // My own name: an offline copy's already has duplicate numbering, and the
  // target folder separates duplicates anew.
  final ext = sourcePath.split('.').last.toLowerCase();
  final filename = '${trackFileBase(track)}.$ext';

  if (Platform.isIOS) {
    return _saveToVisibleDir(File(sourcePath), filename, deleteSource);
  }
  final saved = await _channel.invokeMethod<String>('save', {
    'sourcePath': sourcePath,
    'filename': filename,
    'mime': ext == 'm4a' ? 'audio/mp4' : 'audio/mpeg',
    'title': track.name,
    'artist': track.artist,
    'deleteSource': deleteSource,
  });
  return saved;
}

/// Saves a cover, next to tracks: on Android Pictures/Bloom (a gallery doesn't
/// show pictures in Music), on iOS the same folder in Files. Returns a path as
/// [saveTrackAsFile] does.
///
/// A track keeps a small cover for list rows, so I ask for a large version of
/// the picture first, and take it as is if that fails.
Future<String?> saveCoverAsFile(Track track) async {
  final cover = track.cover;
  if (cover == null || cover.isEmpty) {
    throw const DownloadFailure(DownloadFailureKind.notDownloadable);
  }

  final Uint8List bytes;
  final localPath = localCoverPath(cover);
  if (localPath != null) {
    bytes = await File(localPath).readAsBytes();
  } else if (isLocalCover(cover)) {
    throw const DownloadFailure(DownloadFailureKind.notDownloadable);
  } else if (cover.startsWith('data:')) {
    final decoded = decodeDataUrl(cover);
    if (decoded == null) {
      throw const DownloadFailure(DownloadFailureKind.notDownloadable);
    }
    bytes = decoded.bytes;
  } else {
    bytes = await _fetchCover(cover);
  }

  final ext = _imageExt(bytes);
  final filename = '${trackFileBase(track)}.$ext';
  final tmp = File('${(await getTemporaryDirectory()).path}/$filename');
  await tmp.writeAsBytes(bytes, flush: true);

  if (Platform.isIOS) return _saveToVisibleDir(tmp, filename, true);
  return _channel.invokeMethod<String>('save', {
    'sourcePath': tmp.path,
    'filename': filename,
    'mime': switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    },
    'deleteSource': true,
  });
}

/// A larger version of a network cover; on refusal, the original link.
Future<Uint8List> _fetchCover(String url) async {
  // Referer: SoundCloud's CDN sometimes answers 403 without it.
  const headers = {'Referer': 'https://soundcloud.com/'};
  final big = largeCoverUrl(url);
  if (big != url) {
    try {
      final r = await http
          .get(Uri.parse(big), headers: headers)
          .timeout(const Duration(seconds: 15));
      if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) return r.bodyBytes;
    } catch (_) {
      // No large one: below I take the one shown.
    }
  }
  final r = await http
      .get(Uri.parse(url), headers: headers)
      .timeout(const Duration(seconds: 15));
  if (r.statusCode != 200 || r.bodyBytes.isEmpty) {
    throw DownloadFailure(DownloadFailureKind.unknown, 'HTTP ${r.statusCode}');
  }
  return r.bodyBytes;
}

/// A link to the same cover, larger. All three platforms keep size right in the
/// URL: Yandex `/400x400`, SoundCloud `-t500x500`, YouTube `=w544-h544`.
@visibleForTesting
String largeCoverUrl(String url) {
  if (url.contains('avatars.yandex.net')) {
    return url.replaceFirst(RegExp(r'/\d+x\d+$'), '/1000x1000');
  }
  if (url.contains('sndcdn.com')) {
    return url.replaceFirst(RegExp(r'-(t\d+x\d+|large|crop)\.'), '-original.');
  }
  if (url.contains('googleusercontent.com') || url.contains('ggpht.com')) {
    return url.replaceFirst(RegExp(r'=w\d+-h\d+'), '=w1200-h1200');
  }
  return url;
}

/// Extension by the bytes' signature.
String _imageExt(Uint8List b) {
  if (b.length >= 4 && b[0] == 0x89 && b[1] == 0x50) return 'png';
  if (b.length >= 12 &&
      b[0] == 0x52 &&
      b[1] == 0x49 &&
      b[8] == 0x57 &&
      b[9] == 0x45) {
    return 'webp';
  }
  return 'jpg';
}

/// iOS: the file goes to the app's `Documents`, the folder the system shows in
/// Files (`UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` make
/// that so). It's an ordinary directory with no native code, and the user moves
/// the file on from here.
Future<String?> _saveToVisibleDir(
  File source,
  String filename,
  bool deleteSource,
) async {
  final dir = await appVisibleDir();
  if (!dir.existsSync()) await dir.create(recursive: true);

  // Two tracks may share a name, so they're separated, as in the offline cache.
  final dot = filename.lastIndexOf('.');
  final base = dot > 0 ? filename.substring(0, dot) : filename;
  final ext = dot > 0 ? filename.substring(dot) : '';
  var target = File('${dir.path}/$filename');
  var i = 2;
  while (target.existsSync()) {
    target = File('${dir.path}/$base ($i)$ext');
    i++;
  }

  // A copy, not a move: the source may be an offline copy the player needs in
  // place.
  await source.copy(target.path);
  if (deleteSource) {
    try {
      await source.delete();
    } catch (_) {
      // The temp file wasn't removed, so the system will clean it up.
    }
  }
  return null;
}

/// Saves a whole list as files. Returns the number of failures. Links resolve
/// one at a time with pauses, as in an offline batch: a signed CDN URL lives
/// minutes, and a platform starts refusing a stream of resolves.
Future<({int total, int failed})> saveListAsFiles(
  WidgetRef ref,
  String sourceId,
  List<Track> tracks,
) async {
  final offline = ref.read(offlineProvider.notifier);
  final pending = tracks.where(offline.canDownload).toList();
  if (pending.isEmpty || !offline.beginBatch(sourceId, pending.length)) {
    return (total: pending.length, failed: 0);
  }

  var failed = 0;
  for (var i = 0; i < pending.length; i++) {
    var ok = true;
    try {
      await saveTrackAsFile(ref, pending[i]);
    } catch (_) {
      ok = false;
      failed++;
    }
    if (!offline.advanceBatch(failed: !ok)) break;
    if (i < pending.length - 1) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }
  offline.endBatch();
  return (total: pending.length, failed: failed);
}

/// Why a file wasn't saved. No text on purpose: only the UI knows the language
/// (`describeSaveError`).
enum DownloadFailureKind {
  notDownloadable,
  needPermission,
  noConnection,
  unknown,
}

class DownloadFailure implements Exception {
  const DownloadFailure(this.kind, [this.detail]);

  final DownloadFailureKind kind;

  /// The platform's text for `unknown`: Android sends its own message.
  final String? detail;
}

/// Parses a caught exception into a reason.
DownloadFailure readableSaveError(Object e) {
  if (e is DownloadFailure) return e;
  if (e is PlatformException) {
    if (e.code == 'permission') {
      return const DownloadFailure(DownloadFailureKind.needPermission);
    }
    return DownloadFailure(DownloadFailureKind.unknown, e.message);
  }
  if (e is SocketException) {
    return const DownloadFailure(DownloadFailureKind.noConnection);
  }
  return DownloadFailure(DownloadFailureKind.unknown, '$e');
}
