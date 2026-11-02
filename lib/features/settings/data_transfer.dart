/// Playlists to a `.bloomplaylist` file and back: `{bloom: "playlist", version:
/// 2, exportedAt, playlists, tracks}`, a playlist is `{name, description,
/// sources, cover | coverData, tracks: [id…]}`, a track is its database row
/// ([Track.toJson]). One's own cover goes inside as base64: its file exists
/// only on this device.
///
/// Import makes new playlists with new ids and doesn't merge with ones of the
/// same name: the file and the library have their own histories.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../core/entities/entities.dart';
import '../../core/store/cover_store.dart';
import '../../core/store/library_store.dart';

const String kPlaylistExt = 'bloomplaylist';

/// "This is Bloom's file" and the format's version.
const String _mark = 'playlist';
const int kBundleVersion = 2;

enum ImportFailure {
  /// Not a Bloom playlist file.
  bad,

  /// An older Bloom's file: that format isn't read.
  oldFormat,

  /// From a newer version: update the app.
  newer,
}

class ImportResult {
  const ImportResult({required this.playlists, required this.tracks})
    : failure = null;

  const ImportResult.failed(this.failure) : playlists = 0, tracks = 0;

  final int playlists;

  /// How many came into the library for the first time.
  final int tracks;
  final ImportFailure? failure;
}

/// All playlists, as the file's text.
Future<String> buildExportAllBundle(LibraryState lib, {DateTime? at}) =>
    _bundle(lib.playlists, lib, at);

/// One playlist; the same import reads it.
Future<String> buildExportBundle(
  UserPlaylist playlist,
  LibraryState lib, {
  DateTime? at,
}) => _bundle([playlist], lib, at);

Future<String> _bundle(
  List<UserPlaylist> playlists,
  LibraryState lib,
  DateTime? at,
) async {
  final tracks = <Map<String, dynamic>>[];
  final seen = <String>{};
  final out = <Map<String, dynamic>>[];
  for (final pl in playlists) {
    final ids = <String>[];
    for (final t in lib.tracksOf(pl)) {
      ids.add(t.id);
      if (!seen.add(t.id)) continue;
      final m = t.toJson();
      // A track's own cover is a file of this device: means nothing elsewhere.
      if (isLocalCover(t.cover)) m['cover'] = '';
      tracks.add(m);
    }
    out.add({
      'name': pl.name,
      'description': pl.description ?? '',
      'sources': [for (final s in pl.sources) s.toJson()],
      ...await _coverOut(pl.cover),
      'tracks': ids,
    });
  }
  return const JsonEncoder.withIndent('    ').convert({
    'bloom': _mark,
    'version': kBundleVersion,
    'exportedAt': (at ?? DateTime.now()).toUtc().toIso8601String(),
    'playlists': out,
    'tracks': tracks,
  });
}

/// One's own goes inside (`coverData`), a link as it is.
Future<Map<String, dynamic>> _coverOut(String? cover) async {
  if (cover == null || cover.isEmpty) return const {};
  if (!isLocalCover(cover)) return {'cover': cover};
  final path = localCoverPath(cover);
  if (path == null) return const {};
  try {
    return {'coverData': base64Encode(await File(path).readAsBytes())};
  } catch (_) {
    // The file is gone: without a cover then.
    return const {};
  }
}

String playlistFileName(String name) {
  var safe = name.trim().replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_');
  if (safe.length > 80) safe = safe.substring(0, 80);
  return '${safe.isEmpty ? 'playlist' : safe}.$kPlaylistExt';
}

/// Parses a file and makes its playlists.
Future<ImportResult> importPlaylistBundle(
  String content,
  LibraryState lib,
  LibraryController library,
) async {
  Object? doc;
  try {
    doc = jsonDecode(content);
  } catch (_) {
    return const ImportResult.failed(ImportFailure.bad);
  }
  if (doc is! Map) return const ImportResult.failed(ImportFailure.bad);
  if (doc['bloom'] != _mark) {
    return ImportResult.failed(
      doc.containsKey('playlists')
          ? ImportFailure.oldFormat
          : ImportFailure.bad,
    );
  }
  if ((doc['version'] as num? ?? 0) > kBundleVersion) {
    return const ImportResult.failed(ImportFailure.newer);
  }

  final byId = <String, Track>{};
  for (final raw in (doc['tracks'] as List?) ?? const []) {
    final t = Track.fromJson(raw);
    if (t != null) byId[t.id] = t;
  }

  var made = 0;
  final fresh = <String>{};
  for (final raw in (doc['playlists'] as List?) ?? const []) {
    if (raw is! Map) continue;
    final tracks = [
      for (final id in (raw['tracks'] as List?) ?? const [])
        if (id is String) ?byId[id],
    ];
    for (final t in tracks) {
      if (!lib.isInLib(t.id)) fresh.add(t.id);
    }
    final description = raw['description'];
    final pl = library.createPlaylist(
      raw['name'] as String? ?? '',
      tracks: tracks,
      cover: await _coverIn(raw),
      description: description is String ? description : null,
    );
    final sources = [
      for (final s in (raw['sources'] as List?) ?? const [])
        ?PlSourceRef.fromJson(s),
    ];
    if (sources.isNotEmpty) library.setPlaylistSources(pl.id, sources);
    made++;
  }
  return ImportResult(playlists: made, tracks: fresh.length);
}

/// A picture inside becomes a file of its own, a link stays. `null` is fine: a
/// collage of its tracks shows.
Future<String?> _coverIn(Map raw) async {
  final data = raw['coverData'];
  if (data is String && data.isNotEmpty) {
    try {
      final bytes = base64Decode(data);
      return saveLocalImage(bytes, prefix: 'cover', ext: _extOf(bytes));
    } catch (_) {
      return null;
    }
  }
  final cover = raw['cover'];
  return cover is String && cover.isNotEmpty ? cover : null;
}

/// By the first bytes: the name is just for honesty.
String _extOf(Uint8List b) {
  if (b.length > 3 && b[0] == 0x89 && b[1] == 0x50) return 'png';
  if (b.length > 3 && b[0] == 0x47 && b[1] == 0x49) return 'gif';
  if (b.length > 11 && b[8] == 0x57 && b[9] == 0x45) return 'webp';
  return 'jpg';
}
