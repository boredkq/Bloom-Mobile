/// Parsing an artists string: where I cut and where a name stays whole.
library;

import 'package:bloom/shared/util/artists.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('symbols and joining words split the string', () {
    expect(parseArtists('Artist A, Artist B feat. Artist C'), [
      'Artist A',
      'Artist B',
      'Artist C',
    ]);
    expect(parseArtists('A & B'), ['A', 'B']);
    expect(parseArtists('A, B × C'), ['A', 'B', 'C']);
    expect(parseArtists('A vs. B ft C'), ['A', 'B', 'C']);
  });

  test('"and", "x", "и" are part of a name', () {
    expect(parseArtists('Florence and the Machine'), [
      'Florence and the Machine',
    ]);
    expect(parseArtists('Sasha x Digweed'), ['Sasha x Digweed']);
    expect(parseArtists('Один и Другой'), ['Один и Другой']);
  });

  test('a word inside a name stays a name', () {
    // Joiners cut only between spaces: otherwise "Swiftft" would become "Swift"
    // and "Sandvs" would become "Sand".
    expect(parseArtists('Swiftft Fixt'), ['Swiftft Fixt']);
    expect(parseArtists('Sandvs'), ['Sandvs']);
  });

  test('one artist comes back as one piece', () {
    expect(parseArtists('AC/DC'), ['AC/DC']);
    expect(parseArtists('  Onda  '), ['Onda']);
  });

  test(
    'an empty string gives an empty list, only separators stay as they are',
    () {
      expect(parseArtists(null), isEmpty);
      expect(parseArtists('   '), isEmpty);
      expect(parseArtists('&'), ['&']);
    },
  );
}
