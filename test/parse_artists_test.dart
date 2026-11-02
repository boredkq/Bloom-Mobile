/// Parsing an artists string: where I cut and where a name stays whole.
library;

import 'package:bloom/shared/util/artists.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('символы и слова-связки режут строку', () {
    expect(parseArtists('Artist A, Artist B feat. Artist C'), [
      'Artist A',
      'Artist B',
      'Artist C',
    ]);
    expect(parseArtists('A & B'), ['A', 'B']);
    expect(parseArtists('A, B × C'), ['A', 'B', 'C']);
    expect(parseArtists('A vs. B ft C'), ['A', 'B', 'C']);
  });

  test('«and», «x», «и» — часть имени, как на ПК', () {
    expect(parseArtists('Florence and the Machine'), [
      'Florence and the Machine',
    ]);
    expect(parseArtists('Sasha x Digweed'), ['Sasha x Digweed']);
    expect(parseArtists('Один и Другой'), ['Один и Другой']);
  });

  test('слово внутри имени именем и остаётся', () {
    // Joiners cut only between spaces: otherwise "Swiftft" would become "Swift"
    // and "Sandvs" would become "Sand".
    expect(parseArtists('Swiftft Fixt'), ['Swiftft Fixt']);
    expect(parseArtists('Sandvs'), ['Sandvs']);
  });

  test('один артист возвращается одним куском', () {
    expect(parseArtists('AC/DC'), ['AC/DC']);
    expect(parseArtists('  Onda  '), ['Onda']);
  });

  test('пустая строка — пустой список, из одних разделителей — как есть', () {
    expect(parseArtists(null), isEmpty);
    expect(parseArtists('   '), isEmpty);
    expect(parseArtists('&'), ['&']);
  });
}
