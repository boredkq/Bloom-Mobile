/// UI font catalogue. Two built in: Inter (default) and Minecraft Rus. User
/// files come on top.
///
/// Settings store the family itself (`Inter`, `bloomfont-…`); the fallback
/// comes from the theme.
library;

class BloomFont {
  const BloomFont(this.name, this.family);

  final String name;

  final String family;
}

const String kDefaultFont = 'Inter';

const List<BloomFont> kBuiltinFonts = [
  BloomFont('Inter', 'Inter'),
  BloomFont('Minecraft', 'Minecraft Rus'),
];

/// Replaced fonts: a saved choice moves over instead of resetting.
const Map<String, String> _replaced = {'Monocraft': 'Minecraft Rus'};

/// First family of a font stack, unquoted, so
/// `'Inter',system-ui,sans-serif` is recognised too.
String firstFontFamily(String value) =>
    value.split(',').first.trim().replaceAll(RegExp(r'''^['"]|['"]$'''), '');

/// Saved value to a drawable family. Anything not in the catalogue or
/// [userFamilies], and junk, becomes Inter, or the UI would silently fall to
/// the system font.
String normalizeFont(Object? raw, Iterable<String> userFamilies) {
  if (raw is! String) return kDefaultFont;
  final first = firstFontFamily(raw);
  final family = _replaced[first] ?? first;
  if (userFamilies.contains(family)) return family;
  return kBuiltinFonts.any((f) => f.family == family) ? family : kDefaultFont;
}
