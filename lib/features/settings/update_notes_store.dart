/// Version notes: "What's new" after an update and the update history. The
/// manifest is `{"<version>": {date, image, summary, items}}`; a text is a string
/// or `{ru, en}`. It's read from the repository, so the text changes without a
/// release.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../core/log/bloom_log.dart';
import '../../core/store/json_store.dart';
import 'about_store.dart' show compareVersions, isMajorVersion, kUpdateRepo;

const String _base =
    'https://raw.githubusercontent.com/$kUpdateRepo/main/update-notes/';

/// For checking a note before it's in `main`: another manifest's address, and
/// "What's new" opening at each launch.
const String _testNotes = String.fromEnvironment('UPDATE_NOTES');
const bool _force = bool.fromEnvironment('UPDATE_FORCE');

Uri get _manifestUrl =>
    Uri.parse(_testNotes.isEmpty ? '${_base}update-notes.json' : _testNotes);

/// Where the manifest's cache and the last run's version live in `bloom.json`.
const String kNotesCacheKey = 'updateNotes';
const String _lastRunKey = 'lastRun';

/// One version's note, already parsed for the language.
class UpdateNote {
  const UpdateNote({
    required this.version,
    required this.date,
    required this.summary,
    required this.items,
    this.image,
  });

  final String version;

  /// ISO or empty.
  final String date;

  /// A full link, only for a major version.
  final String? image;
  final String summary;
  final List<String> items;

  /// An empty note doesn't open by itself.
  bool get hasContent =>
      summary.isNotEmpty || items.isNotEmpty || image != null;
}

class NoteHeadline {
  const NoteHeadline({required this.version, required this.date});

  final String version;

  /// Formatted when shown, so the cache doesn't depend on the language.
  final String date;
}

/// A provider for tests.
typedef NotesFetch = Future<String> Function(Uri url);

final notesFetchProvider = Provider<NotesFetch>((ref) => _get);

Future<String> _get(Uri url) async {
  final res = await http.get(url);
  if (res.statusCode != 200) {
    throw http.ClientException('HTTP ${res.statusCode}', url);
  }
  return res.body;
}

final updateNotesProvider = Provider<UpdateNotes>(UpdateNotes.new);

class UpdateNotes {
  UpdateNotes(this._ref);

  final Ref _ref;

  /// This session's manifest. The future too: "What's new" and the history
  /// opening after it mustn't fetch twice.
  Map<String, dynamic>? _manifest;
  Future<Map<String, dynamic>>? _loading;

  JsonStore get _store => _ref.read(jsonStoreProvider);

  /// Empty on the first launch.
  String get lastRun {
    final raw = _store.readMap(kNotesCacheKey)[_lastRunKey];
    return raw is String ? raw : '';
  }

  void markRun(String version) {
    if (version.isEmpty) return;
    final data = Map<String, dynamic>.from(_store.readMap(kNotesCacheKey));
    if (data[_lastRunKey] == version) return;
    data[_lastRunKey] = version;
    _store.write(kNotesCacheKey, data);
  }

  /// `null` if the manifest doesn't have it.
  Future<UpdateNote?> note(String version, String locale) async {
    final manifest = await _load();
    return _note(manifest, version, locale);
  }

  /// Newest first.
  Future<List<NoteHeadline>> history(String locale) async {
    final manifest = await _load();
    final versions = manifest.keys.toList()
      ..sort((a, b) => compareVersions(b, a));
    return [
      for (final version in versions)
        if (manifest[version] is Map)
          NoteHeadline(
            version: version,
            date: _iso((manifest[version] as Map)['date']),
          ),
    ];
  }

  /// What opens by itself after an update, or `null`. Silent if the version
  /// didn't change, on the first launch, and if the manifest doesn't know it.
  /// The run is marked in all of these: otherwise the next launch would count
  /// the version as new.
  Future<UpdateNote?> whatsNew(String version, String locale) async {
    final previous = lastRun;
    markRun(version);
    if (version.isEmpty) return null;
    if (!_force && (previous.isEmpty || previous == version)) return null;
    try {
      final fresh = await note(version, locale);
      return fresh != null && fresh.hasContent ? fresh : null;
    } catch (e) {
      // Offline after an update is fine: it opens by hand.
      logWarn('notes', 'note for version $version did not load: $e');
      return null;
    }
  }

  /// Memory, the network, the cache in `bloom.json`.
  Future<Map<String, dynamic>> _load() {
    final cached = _manifest;
    if (cached != null) return Future.value(cached);
    return _loading ??= _fetch()
        .then((manifest) {
          _manifest = manifest;
          return manifest;
        })
        .whenComplete(() => _loading = null);
  }

  Future<Map<String, dynamic>> _fetch() async {
    try {
      final body = await _ref.read(notesFetchProvider)(_manifestUrl);
      final decoded = jsonDecode(body);
      if (decoded is! Map) throw const FormatException('not a JSON object');
      final manifest = decoded.cast<String, dynamic>();
      // The last run's version lives in the same key: not overwritten.
      final data = Map<String, dynamic>.from(_store.readMap(kNotesCacheKey))
        ..['manifest'] = manifest;
      _store.write(kNotesCacheKey, data);
      return manifest;
    } catch (e) {
      final cached = _store.readMap(kNotesCacheKey)['manifest'];
      if (cached is Map) {
        logWarn('notes', 'manifest did not download ($e), using the cache');
        return cached.cast<String, dynamic>();
      }
      rethrow;
    }
  }
}

UpdateNote? _note(
  Map<String, dynamic> manifest,
  String version,
  String locale,
) {
  final raw = manifest[version];
  if (raw is! Map) return null;
  return UpdateNote(
    version: version,
    date: _iso(raw['date']),
    image: isMajorVersion(version) ? _image(raw['image']) : null,
    summary: _text(raw['summary'], locale),
    items: _lines(raw['items'], locale),
  );
}

/// A list of texts, or `{ru: [...], en: [...]}`.
List<String> _lines(Object? raw, String locale) {
  final list = raw is Map ? raw[locale] ?? raw['ru'] ?? raw['en'] : raw;
  if (list is! List) return const [];
  return [
    for (final item in list)
      if (_text(item, locale).isNotEmpty) _text(item, locale),
  ];
}

/// A string as it is; `{ru, en}` by language, else ru, else en.
String _text(Object? raw, String locale) {
  if (raw is String) return raw;
  if (raw is! Map) return '';
  final value = raw[locale] ?? raw['ru'] ?? raw['en'];
  return value is String ? value : '';
}

String _iso(Object? raw) => raw is String ? raw : '';

/// A file in `update-notes/assets/`, or a link as it is.
String? _image(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
  return '${_base}assets/${raw.replaceAll(RegExp(r'^/+'), '')}';
}

/// By language. A broken date stays as it is.
String formatNoteDate(String iso, String locale) {
  if (iso.isEmpty) return '';
  final date = DateTime.tryParse(iso);
  if (date == null) return iso;
  return DateFormat.yMMMMd(locale).format(date);
}
