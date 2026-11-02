/// Offline track copies. It resolves a direct FILE link from the platform
/// ([MusicProvider.resolveDownload]), downloads it to `offline/` in the app's
/// data and remembers track id to file. Then the player plays the copy from
/// disk (see `PlaybackController._load`).
///
/// The index keeps a FILE NAME, not an absolute path: the iOS app container
/// moves between launches. No tags go in the file: only Bloom reads it, and the
/// metadata is in the library.
///
/// A downloaded track goes in the library, or `_prune` drops it from the track
/// store, leaving a file with no row.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../app/providers.dart';
import '../../core/entities/entities.dart';
import '../../core/store/app_dirs.dart';
import '../../core/store/json_store.dart';
import '../../core/store/library_store.dart';

Directory? _dir;

/// Prepares the offline directory. Called from `main()` before the first frame:
/// afterwards the path is needed synchronously, in `build`.
Future<void> initOfflineStore() async {
  final root = await appPrivateDir();
  final dir = Directory('${root.path}/offline');
  try {
    if (!dir.existsSync()) await dir.create(recursive: true);
    _dir = dir;
  } catch (_) {
    // No write rights: offline is just unavailable, and the app works.
  }
}

/// Progress of a batch download (a whole playlist).
class OfflineBatch {
  /// Whose batch this is: the id of the list it started from. There's one
  /// indicator for the app, or the saving line would hang on EVERY playlist.
  final String sourceId;
  final int done;
  final int total;
  final int failed;

  const OfflineBatch({
    required this.sourceId,
    required this.done,
    required this.total,
    this.failed = 0,
  });

  OfflineBatch copyWith({int? done, int? failed}) => OfflineBatch(
    sourceId: sourceId,
    done: done ?? this.done,
    total: total,
    failed: failed ?? this.failed,
  );
}

class OfflineState {
  /// Track id to file name in `offline/`.
  final Map<String, String> files;

  /// What's downloading now: track id to share 0..1 (`-1` if size unknown).
  final Map<String, double> pending;

  /// A batch download, if running.
  final OfflineBatch? batch;

  const OfflineState({
    this.files = const {},
    this.pending = const {},
    this.batch,
  });

  bool has(String trackId) => files.containsKey(trackId);
  bool isPending(String trackId) => pending.containsKey(trackId);

  /// Share downloaded (`null` if the track isn't downloading now).
  double? progressOf(String trackId) {
    final p = pending[trackId];
    return (p == null || p < 0) ? null : p;
  }

  OfflineState copyWith({
    Map<String, String>? files,
    Map<String, double>? pending,
    OfflineBatch? batch,
    bool clearBatch = false,
  }) => OfflineState(
    files: files ?? this.files,
    pending: pending ?? this.pending,
    batch: clearBatch ? null : (batch ?? this.batch),
  );
}

final offlineProvider = NotifierProvider<OfflineController, OfflineState>(
  OfflineController.new,
);

/// Pause between tracks in a batch: under a stream of resolves SoundCloud's
/// api-v2 starts giving 401 and 403.
const Duration _betweenTracks = Duration(milliseconds: 250);

class OfflineController extends Notifier<OfflineState> {
  JsonStore get _store => ref.read(jsonStoreProvider);

  @override
  OfflineState build() {
    final files = <String, String>{};
    _store.readMap('offline').forEach((id, name) {
      // Entries whose file didn't survive a reinstall or clearing aren't shown,
      // but the index itself isn't rewritten.
      if (name is String && _fileOf(name)?.existsSync() == true) {
        files[id] = name;
      }
    });
    return OfflineState(files: files);
  }

  static File? _fileOf(String name) {
    final dir = _dir;
    return dir == null ? null : File('${dir.path}/$name');
  }

  /// Path to an offline copy; `null` if there's none.
  String? pathOf(String trackId) {
    final name = state.files[trackId];
    return name == null ? null : _fileOf(name)?.path;
  }

  bool has(String trackId) => state.has(trackId);

  /// Whether this track can be saved at all, asked of its platform.
  bool canDownload(Track track) =>
      ref.read(registryProvider).forEntity(track.id)?.canDownload(track) ??
      false;

  void _saveIndex() => _store.write('offline', state.files);

  void _setPending(String id, double value) {
    state = state.copyWith(pending: {...state.pending, id: value});
  }

  void _clearPending(String id) {
    final next = {...state.pending}..remove(id);
    state = state.copyWith(pending: next);
  }

  /// Downloads a track. Returns `null` on success or a REASON for refusal, not
  /// a phrase: the store doesn't know the language, and the UI builds the text
  /// (`describeOfflineFailure`). Idempotent: a track cached or downloading
  /// isn't fetched twice.
  Future<OfflineFailure?> download(Track track) async {
    if (state.has(track.id) || state.isPending(track.id)) return null;
    if (_dir == null) return const OfflineFailure(OfflineFailureKind.noStorage);
    final provider = ref.read(registryProvider).forEntity(track.id);
    if (provider == null || !provider.canDownload(track)) {
      return const OfflineFailure(OfflineFailureKind.notSavable);
    }

    _setPending(track.id, -1);
    try {
      final stream = await provider.resolveDownload(track);
      if (stream == null) {
        return const OfflineFailure(OfflineFailureKind.notSavable);
      }
      final file = await fetchAudioToFile(
        url: stream.url,
        headers: stream.headers,
        dir: _dir!,
        base: trackFileBase(track),
        onProgress: (p) => _setPending(track.id, p),
      );
      state = state.copyWith(
        files: {...state.files, track.id: file.uri.pathSegments.last},
      );
      _saveIndex();
      // What's downloaded must be in the library, or `_prune` cleans the track
      // and the file is an orphan.
      ref.read(libraryProvider.notifier).addToLibrary([track]);
      return null;
    } catch (e) {
      return _readableError(e);
    } finally {
      _clearPending(track.id);
    }
  }

  /// Removes an offline copy: file and index entry. The track stays in the
  /// library.
  Future<void> remove(String trackId) async {
    final name = state.files[trackId];
    if (name == null) return;
    state = state.copyWith(files: {...state.files}..remove(trackId));
    _saveIndex();
    try {
      final file = _fileOf(name);
      if (file != null && file.existsSync()) await file.delete();
    } catch (_) {
      // The file wasn't removed: the index is free of it, and it's just junk in
      // the directory.
    }
  }

  Future<OfflineFailure?> toggle(Track track) async {
    if (state.has(track.id)) {
      await remove(track.id);
      return null;
    }
    return download(track);
  }

  /// Downloads all a list's downloadable tracks. Links resolve one at a time
  /// right before each track: a signed CDN URL lives minutes, and a batch of
  /// links taken ahead goes stale by the list's end. Returns a count for the
  /// final snack bar; `null` if there's nothing to download. `busy`: another
  /// batch is running.
  Future<BatchResult?> downloadAll(String sourceId, List<Track> tracks) async {
    final pending = tracks
        .where((t) => !state.has(t.id) && canDownload(t))
        .toList();
    if (pending.isEmpty) return null;
    if (!beginBatch(sourceId, pending.length)) {
      return const BatchResult(total: 0, failed: 0, busy: true);
    }

    var failed = 0;
    for (var i = 0; i < pending.length; i++) {
      final err = await download(pending[i]);
      if (err != null) failed++;
      // The batch may have been cancelled while a track downloaded.
      if (!advanceBatch(failed: err != null)) break;
      if (i < pending.length - 1) await Future<void>.delayed(_betweenTracks);
    }
    endBatch();
    return BatchResult(total: pending.length, failed: failed);
  }

  /// Takes the batch indicator. `false` if another batch is running: two counts
  /// don't fit one indicator, and parallel resolves strain a platform. Public
  /// because saving a list as files shares it.
  bool beginBatch(String sourceId, int total) {
    if (state.batch != null || total == 0) return false;
    state = state.copyWith(
      batch: OfflineBatch(sourceId: sourceId, done: 0, total: total),
    );
    return true;
  }

  /// Marks a track processed. `false` if the batch was cancelled, stopping
  /// there.
  bool advanceBatch({bool failed = false}) {
    final batch = state.batch;
    if (batch == null) return false;
    state = state.copyWith(
      batch: batch.copyWith(
        done: batch.done + 1,
        failed: batch.failed + (failed ? 1 : 0),
      ),
    );
    return true;
  }

  void endBatch() => state = state.copyWith(clearBatch: true);

  /// Stops the batch. A track downloading now finishes: no reason to break a
  /// file write midway.
  void cancelBatch() => endBatch();

  /// Removes all a list's tracks from offline.
  Future<int> removeAll(List<Track> tracks) async {
    var n = 0;
    for (final t in tracks) {
      if (!state.has(t.id)) continue;
      await remove(t.id);
      n++;
    }
    return n;
  }

  /// Tracks and bytes in the cache, for the storage section.
  Future<({int count, int bytes})> stats() async {
    var count = 0;
    var bytes = 0;
    for (final name in state.files.values) {
      final file = _fileOf(name);
      if (file == null || !file.existsSync()) continue;
      count++;
      try {
        bytes += await file.length();
      } catch (_) {
        // The file vanished between check and read, so it just doesn't count.
      }
    }
    return (count: count, bytes: bytes);
  }

  /// Erases the whole cache. Returns the number of files removed.
  Future<int> clearAll() async {
    final names = state.files.values.toList();
    state = state.copyWith(files: const {});
    _saveIndex();
    var deleted = 0;
    for (final name in names) {
      try {
        final file = _fileOf(name);
        if (file != null && file.existsSync()) {
          await file.delete();
          deleted++;
        }
      } catch (_) {
        // Not removed: the others still get cleared.
      }
    }
    return deleted;
  }
}

/// Chunk size from the CDN. googlevideo won't give one long download: the
/// connection breaks mid-track, especially on iOS. A megabyte chunk lives
/// seconds with little to break, and if it does, only it is requested again.
const int _chunkBytes = 1 << 20;

/// Retries in a row for a chunk that didn't arrive. Reset on each chunk where
/// any byte came, or a long download with rare breaks would hit a total limit.
const int _chunkRetries = 3;

const Duration _retryPause = Duration(milliseconds: 400);

/// How long to wait for the next byte. A broken connection doesn't always come
/// as an error: it may just go silent, and with no limit the download hangs
/// forever.
const Duration _stallTimeout = Duration(seconds: 20);

/// Downloads a track by direct link into [dir] and returns the file. A stream
/// to a temp `.part`: tracks are megabytes, not to be held in memory, and a
/// broken download mustn't leave a stub passing as a finished file. Shared by
/// offline copies and saving files.
///
/// The file comes in `Range` chunks (see [_chunkBytes]). A platform that
/// doesn't know Range answers with an ordinary 200 and the whole body, which
/// just gets read to the end.
Future<File> fetchAudioToFile({
  required String url,
  required Map<String, String> headers,
  required Directory dir,
  required String base,
  void Function(double)? onProgress,
}) async {
  final client = http.Client();
  final uri = Uri.parse(url);
  final part = File(
    '${dir.path}/.part_${DateTime.now().microsecondsSinceEpoch}',
  );
  final sink = part.openWrite();
  // Extension by the first bytes: SoundCloud serves mp3 and m4a, and a URL
  // can't tell.
  String? ext;
  var received = 0;
  int? total;
  var done = false;
  var fails = 0;

  try {
    try {
      while (!done) {
        final request = http.Request('GET', uri)
          ..followRedirects = true
          ..headers.addAll(headers)
          ..headers['Range'] = 'bytes=$received-${received + _chunkBytes - 1}';

        http.StreamedResponse response;
        try {
          response = await client.send(request).timeout(_stallTimeout);
        } on Exception {
          if (++fails > _chunkRetries) rethrow;
          await Future<void>.delayed(_retryPause);
          continue;
        }

        if (response.statusCode == 200) {
          // Range unsupported, so the body is the whole file from zero.
          // Mid-download that would duplicate what's written, so only at the
          // start.
          if (received > 0) {
            throw const HttpException('the CDN lost the file position');
          }
          total = response.contentLength;
          done = true;
        } else if (response.statusCode == 206) {
          total ??= _rangeTotal(response.headers['content-range']);
        } else if (response.statusCode == 416) {
          // Asked past the end of the file: I didn't ask the CDN for a length,
          // so the end may match a chunk boundary.
          break;
        } else {
          throw HttpException('the CDN answered ${response.statusCode}');
        }

        final before = received;
        try {
          await for (final chunk in response.stream.timeout(_stallTimeout)) {
            if (ext == null && chunk.length >= 8) ext = _audioExt(chunk);
            sink.add(chunk);
            received += chunk.length;
            onProgress?.call(
              total != null && total > 0 ? received / total : -1,
            );
          }
        } on Exception {
          // A chunk broke midway: what's written stays, and I retry from the
          // position reached.
          if (received > before) fails = 0;
          if (++fails > _chunkRetries) rethrow;
          await Future<void>.delayed(_retryPause);
          continue;
        }

        fails = 0;
        if (total != null) {
          done = received >= total;
        } else if (received - before < _chunkBytes) {
          // Length unknown: the end shows as a short chunk.
          done = true;
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    if (received == 0) {
      await part.delete();
      throw const HttpException('empty answer');
    }
    if (total != null && received < total) {
      await part.delete();
      throw const HttpException('the file arrived incomplete');
    }

    final name = _uniqueName(dir, base, ext ?? 'mp3');
    return part.rename('${dir.path}/$name');
  } catch (_) {
    // An unfinished stub mustn't outlive an error: it's useless and takes cache
    // space.
    if (part.existsSync()) {
      try {
        await part.delete();
      } catch (_) {
        // Not removed: I'll live, and report the download error itself above.
      }
    }
    rethrow;
  } finally {
    client.close();
  }
}

/// Total file size from the `Content-Range: bytes 0-1048575/3283727` header.
int? _rangeTotal(String? header) {
  final size = header?.split('/').last;
  return size == null ? null : int.tryParse(size);
}

/// A batch's result, shared by both downloads. `batchSummary` makes a phrase
/// from it, where the language is.
class BatchResult {
  const BatchResult({
    required this.total,
    required this.failed,
    this.busy = false,
  });

  final int total;
  final int failed;

  /// The batch didn't start: another list is downloading.
  final bool busy;

  int get ok => total - failed;
}

/// Why a track wasn't saved offline.
enum OfflineFailureKind {
  noStorage,
  notSavable,
  streamOnly,
  drm,
  noFileLink,
  noConnection,
  unknown,
}

/// Refusal reason, plus raw data for `unknown` (the platform's exception text).
class OfflineFailure {
  const OfflineFailure(this.kind, [this.detail]);

  final OfflineFailureKind kind;
  final String? detail;
}

/// "Artist - Title", the file name.
String trackFileBase(Track track) {
  final raw = (track.artist.isEmpty ? '' : '${track.artist} - ') + track.name;
  final safe = raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  return safe.isEmpty ? 'track' : safe;
}

/// m4a for files with an `ftyp` box at the start, otherwise mp3.
String _audioExt(List<int> bytes) {
  if (bytes.length > 8 &&
      bytes[4] == 0x66 &&
      bytes[5] == 0x74 &&
      bytes[6] == 0x79 &&
      bytes[7] == 0x70) {
    return 'm4a';
  }
  return 'mp3';
}

/// A free name like `Base.ext`, `Base (2).ext`, …: two different tracks may
/// share a name.
String _uniqueName(Directory dir, String base, String ext) {
  var name = '$base.$ext';
  var i = 2;
  while (File('${dir.path}/$name').existsSync()) {
    name = '$base ($i).$ext';
    i++;
  }
  return name;
}

/// Platform codes mean something only to a developer, so I parse them into a
/// reason, and the UI builds the text.
OfflineFailure _readableError(Object e) {
  final msg = e is Exception ? e.toString() : '$e';
  if (msg.contains('hlsOnly')) {
    return const OfflineFailure(OfflineFailureKind.streamOnly);
  }
  if (msg.contains('drm')) return const OfflineFailure(OfflineFailureKind.drm);
  if (msg.contains('noStream')) {
    return const OfflineFailure(OfflineFailureKind.noFileLink);
  }
  if (e is SocketException) {
    return const OfflineFailure(OfflineFailureKind.noConnection);
  }
  return OfflineFailure(OfflineFailureKind.unknown, msg);
}
