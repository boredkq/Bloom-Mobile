/// Tests for LRC section headers and automatic romanization integration.
library;

import 'package:bloom/features/lyrics/lrc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseLrc with sections and romanization', () {
    test('extracts inline section headers', () {
      final lines = parseLrc('[00:10.00][Chorus] In the end it matters\n');
      expect(lines.length, 1);
      expect(lines.first.time, 10.0);
      expect(lines.first.text, 'In the end it matters');
      expect(lines.first.section, 'Chorus');
      expect(lines.first.romanized, isNull);
    });

    test('extracts standalone section headers for subsequent lines', () {
      final lines = parseLrc(
        '[Verse 1]\n'
        '[00:15.00]First line of verse\n'
        '[00:20.00]Second line of verse\n'
        '[Chorus]\n'
        '[00:30.00]Chorus line\n',
      );
      expect(lines.length, 3);
      expect(lines[0].time, 15.0);
      expect(lines[0].text, 'First line of verse');
      expect(lines[0].section, 'Verse 1');

      // The standalone header attaches to the immediately following line:
      expect(lines[1].time, 20.0);
      expect(lines[1].text, 'Second line of verse');
      expect(lines[1].section, isNull);

      expect(lines[2].time, 30.0);
      expect(lines[2].text, 'Chorus line');
      expect(lines[2].section, 'Chorus');
    });

    test('supports Russian section headers and transliterates Cyrillic text', () {
      final lines = parseLrc('[00:12.00][Припев] Я лечу над землёй\n');
      expect(lines.length, 1);
      expect(lines.first.time, 12.0);
      expect(lines.first.text, 'Я лечу над землёй');
      expect(lines.first.section, 'Припев');
      expect(lines.first.romanized, "Ya lechu nad zemlyoy");
    });

    test('supports Asian scripts romanization alongside timestamps', () {
      final lines = parseLrc(
        '[00:05.00][Intro] こんにちは\n'
        '[00:10.00]사랑해요\n',
      );
      expect(lines.length, 2);
      expect(lines[0].section, 'Intro');
      expect(lines[0].text, 'こんにちは');
      expect(lines[0].romanized, 'konnichiha');

      expect(lines[1].section, isNull);
      expect(lines[1].text, '사랑해요');
      expect(lines[1].romanized, 'saranghaeyo');
    });

    test('handles multiple timestamps with section header', () {
      final lines = parseLrc('[00:10.00][00:40.00][Chorus] Sing along\n');
      expect(lines.length, 2);
      expect(lines[0].time, 10.0);
      expect(lines[0].text, 'Sing along');
      expect(lines[0].section, 'Chorus');

      expect(lines[1].time, 40.0);
      expect(lines[1].text, 'Sing along');
      expect(lines[1].section, 'Chorus');
    });
  });
}
