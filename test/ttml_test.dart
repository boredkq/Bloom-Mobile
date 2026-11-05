import 'package:bloom/features/lyrics/ttml.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseTtml', () {
    test('parses basic TTML with word-level spans', () {
      const ttml = '''
<tt xmlns="http://www.w3.org/ns/ttml">
  <body>
    <div songPart="Chorus">
      <p begin="00:08.06" end="00:12.16">
        <span begin="00:08.06" end="00:08.48">All</span>
        <span begin="00:08.48" end="00:08.99">your</span>
        <span begin="00:08.99" end="00:10.23">novels</span>
      </p>
    </div>
  </body>
</tt>
''';

      final lines = parseTtml(ttml);
      expect(lines.length, 1);
      expect(lines.first.time, 8.06);
      expect(lines.first.endTime, 12.16);
      expect(lines.first.text, 'All your novels');
      expect(lines.first.section, 'Chorus');
      expect(lines.first.words.length, 3);
      expect(lines.first.words[0].text, 'All');
      expect(lines.first.words[0].start, 8.06);
      expect(lines.first.words[0].end, 8.48);
      expect(lines.first.words[1].text, 'your');
      expect(lines.first.words[2].text, 'novels');
    });

    test('parses TTML seconds format and unescapes XML entities', () {
      const ttml = '''
<tt xmlns="http://www.w3.org/ns/ttml">
  <body>
    <p begin="10.5" end="15.0">
      <span begin="10.5" end="11.2">Rock</span>
      <span begin="11.2" end="12.0">&amp;</span>
      <span begin="12.0" end="13.0">Roll</span>
    </p>
  </body>
</tt>
''';

      final lines = parseTtml(ttml);
      expect(lines.length, 1);
      expect(lines.first.time, 10.5);
      expect(lines.first.text, 'Rock & Roll');
      expect(lines.first.words.length, 3);
      expect(lines.first.words[1].text, '&');
    });

    test('returns empty list for empty string', () {
      expect(parseTtml(''), isEmpty);
    });
  });
}
