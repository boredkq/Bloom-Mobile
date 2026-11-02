/// One's own fonts stand beside the built-in ones. A file is COPIED inside
/// (`<private>/fonts/<id>.<ext>`): access to a picked file is temporary on
/// Android and the font would die with the next launch. Meta is in `bloom.json`
/// under [kUserFontsKey].
///
/// Only .ttf and .otf: the engine doesn't read .woff. They're registered before
/// the first frame ([initUserFonts]).
library;

import 'dart:io';
import 'dart:math' show Random;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/fonts.dart';
import '../../core/log/bloom_log.dart';
import '../../core/store/app_dirs.dart';
import '../../core/store/json_store.dart';
import '../../core/store/settings_store.dart';

const String kUserFontsKey = 'userFonts';

/// A CJK font can be 20 MB.
const int kMaxFontBytes = 12 * 1024 * 1024;

const Set<String> _fontExts = {'ttf', 'otf'};

class UserFont {
  const UserFont({
    required this.id,
    required this.name,
    required this.family,
    required this.file,
    required this.bytes,
    required this.addedAt,
  });

  final String id;

  /// The file name without extension, the tile's caption.
  final String name;

  /// `bloomfont-<id>`, so as not to clash with built-in ones.
  final String family;

  /// In the `fonts` folder.
  final String file;

  final int bytes;
  final int addedAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'family': family,
    'file': file,
    'bytes': bytes,
    'addedAt': addedAt,
  };

  static UserFont? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'], name = raw['name'], family = raw['family'];
    final file = raw['file'];
    if (id is! String || name is! String || family is! String) return null;
    if (file is! String) return null;
    return UserFont(
      id: id,
      name: name,
      family: family,
      file: file,
      bytes: (raw['bytes'] as num?)?.toInt() ?? 0,
      addedAt: (raw['addedAt'] as num?)?.toInt() ?? 0,
    );
  }
}

List<UserFont> readUserFonts(JsonStore store) {
  final raw = store.read(kUserFontsKey);
  return [
    for (final item in raw is List ? raw : const []) ?UserFont.fromJson(item),
  ];
}

Future<Directory> _fontsDir() async {
  final root = await appPrivateDir();
  final dir = Directory('${root.path}/fonts');
  if (!dir.existsSync()) await dir.create(recursive: true);
  return dir;
}

/// By signature: TrueType (`00 01 00 00`, `true`), OpenType (`OTTO`), a
/// collection (`ttcf`). The engine doesn't throw on a broken file, it just
/// draws a fallback, so I filter here.
bool looksLikeFont(List<int> bytes) {
  if (bytes.length < 12) return false;
  final tag = String.fromCharCodes(bytes.sublist(0, 4));
  return (bytes[0] == 0 && bytes[1] == 1 && bytes[2] == 0 && bytes[3] == 0) ||
      tag == 'true' ||
      tag == 'OTTO' ||
      tag == 'ttcf';
}

String fontNameFromFile(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final base = dot > 0 ? fileName.substring(0, dot) : fileName;
  final name = base.length > 40 ? base.substring(0, 40) : base;
  return name.isEmpty ? 'Font' : name;
}

String _extOf(String fileName) {
  final dot = fileName.lastIndexOf('.');
  return dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
}

Future<void> _register(String family, Uint8List bytes) async {
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
}

/// Before the first frame, or a chosen font flashes as Inter. A missing file
/// doesn't stop the launch: it just isn't registered.
Future<void> initUserFonts(JsonStore store) async {
  final fonts = readUserFonts(store);
  if (fonts.isEmpty) return;
  final dir = await _fontsDir();
  for (final font in fonts) {
    try {
      await _register(
        font.family,
        await File('${dir.path}/${font.file}').readAsBytes(),
      );
    } catch (e) {
      logWarn('fonts', 'font "${font.name}" did not load: $e');
    }
  }
}

/// The name, the size if known without reading, and reading the bytes.
typedef PickedFontFile = ({
  String name,
  int? size,
  Future<Uint8List> Function() read,
});

enum FontAddError { format, size, read }

class FontAddResult {
  const FontAddResult(this.added, this.errors);

  final int added;
  final Set<FontAddError> errors;
}

final userFontsProvider = NotifierProvider<UserFontsController, List<UserFont>>(
  UserFontsController.new,
);

class UserFontsController extends Notifier<List<UserFont>> {
  @override
  List<UserFont> build() => readUserFonts(ref.read(jsonStoreProvider));

  void _save() => ref.read(jsonStoreProvider).write(kUserFontsKey, [
    for (final f in state) f.toJson(),
  ]);

  /// Unfit ones go to [FontAddResult.errors], the screen words them. A single
  /// added file applies at once: it was uploaded to be used.
  Future<FontAddResult> addFiles(List<PickedFontFile> files) async {
    final errors = <FontAddError>{};
    final settings = ref.read(settingsProvider.notifier);
    var added = 0;
    UserFont? last;
    for (final picked in files) {
      final ext = _extOf(picked.name);
      if (!_fontExts.contains(ext)) {
        errors.add(FontAddError.format);
        continue;
      }
      if ((picked.size ?? 0) > kMaxFontBytes) {
        errors.add(FontAddError.size);
        continue;
      }
      final Uint8List bytes;
      try {
        bytes = await picked.read();
      } catch (e) {
        logWarn('fonts', 'could not read ${picked.name}: $e');
        errors.add(FontAddError.read);
        continue;
      }
      if (bytes.length > kMaxFontBytes) {
        errors.add(FontAddError.size);
        continue;
      }
      if (!looksLikeFont(bytes)) {
        errors.add(FontAddError.read);
        continue;
      }
      final name = fontNameFromFile(picked.name);
      // The same file again: no equal tiles; a single pick just applies the
      // loaded one.
      final dup = state
          .where((f) => f.name == name && f.bytes == bytes.length)
          .firstOrNull;
      if (dup != null) {
        if (files.length == 1) settings.setFontFamily(dup.family);
        continue;
      }
      final id =
          'uf${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}'
          '${Random().nextInt(1 << 30).toRadixString(36)}';
      final font = UserFont(
        id: id,
        name: name,
        family: 'bloomfont-$id',
        file: '$id.$ext',
        bytes: bytes.length,
        addedAt: DateTime.now().millisecondsSinceEpoch,
      );
      try {
        final dir = await _fontsDir();
        await File('${dir.path}/${font.file}').writeAsBytes(bytes, flush: true);
        await _register(font.family, bytes);
      } catch (e) {
        logWarn('fonts', 'could not save ${picked.name}: $e');
        errors.add(FontAddError.read);
        continue;
      }
      state = [...state, font];
      _save();
      last = font;
      added++;
    }
    if (added == 1 && last != null) settings.setFontFamily(last.family);
    return FontAddResult(added, errors);
  }

  /// If it was chosen, the interface goes back to Inter.
  Future<void> remove(String id) async {
    final font = state.where((f) => f.id == id).firstOrNull;
    if (font == null) return;
    state = [
      for (final f in state)
        if (f.id != id) f,
    ];
    _save();
    final settings = ref.read(settingsProvider.notifier);
    if (ref.read(settingsProvider).fontFamily == font.family) {
      settings.setFontFamily(kDefaultFont);
    }
    try {
      final dir = await _fontsDir();
      final file = File('${dir.path}/${font.file}');
      if (file.existsSync()) await file.delete();
    } catch (e) {
      logWarn('fonts', 'font file "${font.name}" not deleted: $e');
    }
  }
}

/// The choice in settings, checked against the catalogue and one's own fonts.
final uiFontProvider = Provider<String>(
  (ref) => normalizeFont(ref.watch(settingsProvider).fontFamily, [
    for (final f in ref.watch(userFontsProvider)) f.family,
  ]),
);
