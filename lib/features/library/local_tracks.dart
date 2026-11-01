/// Local tracks: files from the phone, added by the plus in the all tracks
/// header.
///
/// No folders: an app has no shared file system to watch, so only single files
/// picked in the system dialog.
///
/// Dart doesn't read tags: on Android it's `MediaMetadataRetriever`, on iOS
/// `AVAsset`, both handle mp3, flac, m4a and ogg and give the embedded cover.
/// No bytes over the channel: the native side stores the cover and Dart gets a
/// file name.
///
/// The id is stable but not from a path: `lf` plus md5 of the KEY (see
/// [localTrackKey]). In remember path mode that's the system's `content://`, in
/// copy mode the source's name and size. Otherwise adding a file again gives a
/// second track, since a copy gets a new name each time.
///
/// The file lives in one of two places ([LocalImportMode]). `sourceData` keeps
/// the copy's NAME, not a path: the iOS app container moves between launches.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/entities/entities.dart';
import '../../core/l10n/l10n.dart';
import '../../core/store/app_dirs.dart';
import '../../core/store/cover_store.dart';
import '../../core/store/library_store.dart';
import '../../core/store/settings_store.dart';

/// The same channel as preset files: both are system file dialogs, and two
/// methods don't merit a second one.
const MethodChannel _channel = MethodChannel('bloom/files');

Directory? _dir;

/// Prepares the local tracks directory. Called from `main()` before the first
/// frame: afterwards the path is needed synchronously, in the player's `_load`.
Future<void> initLocalTracks() async {
  final root = await appPrivateDir();
  final dir = Directory('${root.path}/tracks');
  try {
    if (!dir.existsSync()) await dir.create(recursive: true);
    _dir = dir;
  } catch (_) {
    // No write rights: copy mode just won't work, the rest lives.
  }
}

/// Copies directory; `null` if it didn't come up.
String? localTracksDirPath() => _dir?.path;

/// Whether this is a local track, by source AND data: `MusicSource.fromId`
/// gives `local` to any id with no platform prefix, and only what has a file
/// behind it can play.
bool isLocalTrack(Track track) =>
    track.source == MusicSource.local && track.sourceData?['key'] is String;

/// Dedupe key: the id is computed from it, and the native side filters out
/// what's already added by it.
String? localTrackKey(Track track) {
  final key = track.sourceData?['key'];
  return key is String ? key : null;
}

/// A local track's global id: `lf:` plus md5 of the key. Local files don't
/// travel between devices.
String localTrackId(String key) =>
    'lf:${md5.convert(utf8.encode(key.toLowerCase()))}';

/// Keys of all that's added, so the native side doesn't copy or parse a file
/// already in the library.
///
/// Counted over all tracks rather than the whole store: a deleted local track
/// stays in `tracks` while history refers to it, and by the store a file would
/// look added, so import would silently drop it with no way to bring it back.
/// The library is a full list here: a like or a playlist puts a track in it.
List<String> knownLocalKeys(LibraryState lib) => [
  for (final id in lib.inLib.keys)
    if (lib.tracks[id] case final track?) ?localTrackKey(track),
];

/// Where a local track's file is: a copy's `file://` or the source's
/// `content://`. `null` if it isn't local, the directory didn't come up or the
/// copy was erased.
///
/// No existence check for `content://`: that means opening a stream, and doing
/// so on every `_load` costs more than failing once in a player error.
Uri? localTrackUri(Track track) {
  if (!isLocalTrack(track)) return null;
  final file = track.sourceData?['file'];
  if (file is String) {
    final dir = _dir;
    if (dir == null) return null;
    final path = '${dir.path}/$file';
    return File(path).existsSync() ? Uri.file(path) : null;
  }
  final uri = track.sourceData?['uri'];
  return uri is String ? Uri.tryParse(uri) : null;
}

/// Artist and title from a file name: for a file with no tags the name is often
/// all that's known.
({String artist, String name}) splitFileName(String fileName) {
  var stem = fileName;
  final dot = stem.lastIndexOf('.');
  // A dot in first place isn't an extension but a hidden file.
  if (dot > 0) stem = stem.substring(0, dot);
  final sep = stem.indexOf(' - ');
  if (sep < 0) return (artist: '', name: stem.trim());
  return (
    artist: stem.substring(0, sep).trim(),
    name: stem.substring(sep + 3).trim(),
  );
}

String? _norm(Object? value) {
  if (value is! String) return null;
  final s = value.trim();
  return s.isEmpty ? null : s;
}

/// Year from a tag: vorbis and mp4 usually hold a full date (2019-04-05), so I
/// take the first four digits.
String? _year(Object? value) {
  final raw = _norm(value);
  if (raw == null) return null;
  final match = RegExp(r'\d{4}').firstMatch(raw);
  return match?.group(0);
}

/// Native answer to a library track. An empty tag gives way to what the file
/// name yields, and a nameless artist gets the unknown label. `null` for a
/// broken entry: with no key there's nothing to play.
Track? localTrackFromEntry(Object? raw, {required String unknownArtist}) {
  if (raw is! Map) return null;
  final key = _norm(raw['key']);
  if (key == null) return null;

  final fileName = raw['name'] as String? ?? '';
  final fallback = splitFileName(fileName);
  final cover = _norm(raw['cover']);
  final genre = _norm(raw['genre']);
  final size = raw['size'];
  final uri = _norm(raw['uri']);
  final file = _norm(raw['file']);

  return Track(
    id: localTrackId(key),
    name:
        _norm(raw['title']) ??
        (fallback.name.isEmpty ? fileName : fallback.name),
    artist:
        _norm(raw['artist']) ??
        (fallback.artist.isEmpty ? unknownArtist : fallback.artist),
    duration: Duration(milliseconds: (raw['durationMs'] as num?)?.toInt() ?? 0),
    source: MusicSource.local,
    cover: cover == null ? null : localCoverRef(cover),
    album: _norm(raw['album']),
    year: _year(raw['year']),
    // Several genres in a tag are split by `;` or a null.
    genres: genre == null
        ? const []
        : [
            for (final g in genre.split(RegExp(r'[;\x00]')))
              if (g.trim().isNotEmpty) g.trim(),
          ],
    sourceData: {
      'key': key,
      'name': fileName,
      if (size is num) 'size': size.toInt(),
      'uri': ?uri,
      'file': ?file,
    },
  );
}

/// How the trip to the system dialog ended.
enum LocalImportStatus {
  /// The dialog was closed with nothing picked: nothing to say.
  cancelled,

  /// Files were picked, with nothing to add: all already in the library or
  /// unreadable.
  nothing,

  /// Added.
  added,

  /// No dialog, or it answered with an error.
  failed,
}

typedef LocalImportResult = ({LocalImportStatus status, int added});

/// Picks local files and puts them in the library. The native side does the
/// heavy work (copying, tags, cover) and filters duplicates by
/// [knownLocalKeys], so megabytes don't move for a track already there.
Future<LocalImportResult> importLocalTracks(
  WidgetRef ref,
  AppLocalizations l,
) async {
  final covers = coversDirPath();
  final tracks = localTracksDirPath();
  if (covers == null || tracks == null) {
    return (status: LocalImportStatus.failed, added: 0);
  }

  final mode = ref.read(settingsProvider).localImport;
  final known = knownLocalKeys(ref.read(libraryProvider));

  final List<Object?>? entries;
  try {
    entries = await _channel.invokeMethod<List<Object?>>('pickAudio', {
      'mode': mode.name,
      'tracksDir': tracks,
      'coversDir': covers,
      'known': known,
    });
  } on PlatformException {
    return (status: LocalImportStatus.failed, added: 0);
  } on MissingPluginException {
    // A platform with no native side (tests).
    return (status: LocalImportStatus.failed, added: 0);
  }
  if (entries == null) return (status: LocalImportStatus.cancelled, added: 0);

  final batch = [
    for (final entry in entries)
      ?localTrackFromEntry(entry, unknownArtist: l.commonUnknownArtist),
  ];
  if (batch.isEmpty) return (status: LocalImportStatus.nothing, added: 0);

  // New tracks go on top of all tracks: it's sorted by add time, and
  // `addToLibrary` gives them a later time than any before.
  final added = ref.read(libraryProvider.notifier).addToLibrary(batch);
  return added == 0
      ? (status: LocalImportStatus.nothing, added: 0)
      : (status: LocalImportStatus.added, added: added);
}

/// Cleans up after a deleted local track: the app's copy and its cover from
/// disk, and the permission to the user's file back to the system. The user's
/// file itself is NOT touched.
Future<void> forgetLocalTracks(Iterable<Track> tracks) async {
  for (final track in tracks) {
    if (!isLocalTrack(track)) continue;
    final file = track.sourceData?['file'];
    if (file is String) {
      final dir = _dir;
      if (dir != null) {
        try {
          final copy = File('${dir.path}/$file');
          if (copy.existsSync()) await copy.delete();
        } catch (_) {
          // Not removed is just junk in the directory, no reason to crash.
        }
      }
    }
    final uri = track.sourceData?['uri'];
    if (uri is String) {
      try {
        await _channel.invokeMethod<void>('releaseAudio', {'uri': uri});
      } on PlatformException {
        // Permission already revoked or never there: doesn't matter.
      } on MissingPluginException {
        // A platform with no native side.
      }
    }
    await deleteCover(track.cover);
  }
}

/// Local tracks among [ids]: a caller usually knows only the ids.
List<Track> localTracksOf(LibraryState lib, Iterable<String> ids) => [
  for (final id in ids)
    if (lib.tracks[id] case final Track track when isLocalTrack(track)) track,
];

/// File gone error: `content://` went stale (file deleted, card removed), or
/// the copy was erased outside the app. Its own type for the text:
/// `state.error` shows as is, and `StateError` would add "Bad state:".
class LocalFileGone implements Exception {
  const LocalFileGone();

  @override
  String toString() => globalL10n?.ltFileGone ?? 'File is not available';
}
