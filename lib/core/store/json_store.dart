/// The app's JSON file store. One file (`bloom.json`) in the app's directory.
/// Writes are deferred: a like or an added track hits the store in bursts.
///
/// The file goes through a temp file and a rename: a cut mid-write won't leave
/// broken JSON that makes the library look empty.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_dirs.dart';

/// File store, overridden in `main()` with the real one (in tests, memory).
final jsonStoreProvider = Provider<JsonStore>(
  (ref) =>
      throw UnimplementedError('jsonStoreProvider должен быть переопределён'),
);

const Duration _saveDelay = Duration(milliseconds: 400);

class JsonStore {
  JsonStore._(this._file, this._data);

  final File _file;
  final Map<String, dynamic> _data;
  Timer? _debounce;

  static Future<JsonStore> open({String name = 'bloom.json'}) async {
    final dir = await appPrivateDir();
    final file = File('${dir.path}/$name');
    Map<String, dynamic> data = {};
    try {
      if (file.existsSync()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) data = decoded.cast<String, dynamic>();
      }
    } catch (_) {
      // A broken or foreign file: start clean, but DON'T delete it; it stays on
      // disk in case the user wants a look.
    }
    return JsonStore._(file, data);
  }

  /// Store in memory, for tests and a first launch with no file system.
  factory JsonStore.memory([Map<String, dynamic>? seed]) =>
      JsonStore._(File(''), seed ?? {});

  Object? read(String key) => _data[key];

  List<Object?> readList(String key) {
    final v = _data[key];
    return v is List ? v : const [];
  }

  Map<String, dynamic> readMap(String key) {
    final v = _data[key];
    return v is Map ? v.cast<String, dynamic>() : {};
  }

  /// What's in the file, for a full reset: it wipes all but one key, and has no
  /// way to list stores by name.
  Iterable<String> get keys => _data.keys.toList();

  /// Erases the listed keys at once, for settings and full resets.
  void removeAll(Iterable<String> keys) {
    var changed = false;
    for (final key in keys) {
      changed = _data.remove(key) != null || changed;
    }
    if (changed) _schedule();
  }

  void write(String key, Object? value) {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
    _schedule();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(_saveDelay, flush);
  }

  /// Writes at once (app close, tests).
  Future<void> flush() async {
    _debounce?.cancel();
    if (_file.path.isEmpty) return; // in-memory
    try {
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(jsonEncode(_data), flush: true);
      await tmp.rename(_file.path);
    } catch (_) {
      // No space or rights: the library keeps working in memory.
    }
  }
}
