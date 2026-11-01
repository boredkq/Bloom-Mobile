/// Romanization engine for lyrics: transliterates Cyrillic, Korean Hangul,
/// and Japanese Kana into readable Latin characters for singing along.
library;

/// Transliterates text into Latin characters. Returns `null` if the text
/// contains no characters that need romanization (e.g., already English/Latin).
String? romanize(String text) {
  if (text.trim().isEmpty) return null;
  final sb = StringBuffer();
  var changed = false;

  int i = 0;
  while (i < text.length) {
    final code = text.codeUnitAt(i);

    // 1. Korean Hangul Syllables (AC00..D7A3)
    if (code >= 0xAC00 && code <= 0xD7A3) {
      sb.write(_romanizeHangulSyllable(code));
      changed = true;
      i++;
      continue;
    }

    // 2. Japanese Hiragana (3041..3096) and Katakana (30A1..30FA)
    if ((code >= 0x3041 && code <= 0x3096) || (code >= 0x30A1 && code <= 0x30FA)) {
      final (romaji, consumed) = _romanizeKana(text, i);
      sb.write(romaji);
      changed = true;
      i += consumed;
      continue;
    }

    // 3. Cyrillic (0400..04FF)
    if ((code >= 0x0400 && code <= 0x04FF)) {
      final ch = text[i];
      final mapped = _cyrillicMap[ch];
      if (mapped != null) {
        sb.write(mapped);
        changed = true;
      } else {
        sb.write(ch);
      }
      i++;
      continue;
    }

    // Default: pass through unchanged
    sb.write(text[i]);
    i++;
  }

  return changed ? sb.toString() : null;
}

// ============================ Cyrillic ============================

const Map<String, String> _cyrillicMap = {
  'А': 'A', 'Б': 'B', 'В': 'V', 'Г': 'G', 'Д': 'D', 'Е': 'E', 'Ё': 'Yo',
  'Ж': 'Zh', 'З': 'Z', 'И': 'I', 'Й': 'Y', 'К': 'K', 'Л': 'L', 'М': 'M',
  'Н': 'N', 'О': 'O', 'П': 'P', 'Р': 'R', 'С': 'S', 'Т': 'T', 'У': 'U',
  'Ф': 'F', 'Х': 'Kh', 'Ц': 'Ts', 'Ч': 'Ch', 'Ш': 'Sh', 'Щ': 'Shch',
  'Ъ': '', 'Ы': 'Y', 'Ь': "'", 'Э': 'E', 'Ю': 'Yu', 'Я': 'Ya',
  'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e', 'ё': 'yo',
  'ж': 'zh', 'з': 'z', 'и': 'i', 'й': 'y', 'к': 'k', 'л': 'l', 'м': 'm',
  'н': 'n', 'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u',
  'ф': 'f', 'х': 'kh', 'ц': 'ts', 'ч': 'ch', 'ш': 'sh', 'щ': 'shch',
  'ъ': '', 'ы': 'y', 'ь': "'", 'э': 'e', 'ю': 'yu', 'я': 'ya',
  // Ukrainian / Belarusian extensions
  'І': 'I', 'і': 'i', 'Ї': 'Yi', 'ї': 'yi', 'Є': 'Ye', 'є': 'ye',
  'Ґ': 'G', 'ґ': 'g', 'Ў': 'W', 'ў': 'w',
};

// ============================ Korean Hangul ============================

const List<String> _hangulInitial = [
  'g', 'kk', 'n', 'd', 'tt', 'r', 'm', 'b', 'pp', 's', 'ss', '',
  'j', 'jj', 'ch', 'k', 't', 'p', 'h',
];

const List<String> _hangulVowel = [
  'a', 'ae', 'ya', 'yae', 'eo', 'e', 'yeo', 'ye', 'o', 'wa', 'wae', 'oe',
  'yo', 'u', 'wo', 'we', 'wi', 'yu', 'eu', 'ui', 'i',
];

const List<String> _hangulFinal = [
  '', 'k', 'k', 'ks', 'n', 'nj', 'nh', 't', 'l', 'lg', 'lm', 'lb', 'ls',
  'lt', 'lp', 'lh', 'm', 'p', 'ps', 't', 't', 'ng', 't', 't', 'k', 't',
  'p', 'h',
];

String _romanizeHangulSyllable(int code) {
  final sIndex = code - 0xAC00;
  final lIndex = sIndex ~/ 588;
  final vIndex = (sIndex % 588) ~/ 28;
  final tIndex = sIndex % 28;

  final initial = _hangulInitial[lIndex];
  final vowel = _hangulVowel[vIndex];
  final fin = _hangulFinal[tIndex];

  return '$initial$vowel$fin';
}

// ============================ Japanese Kana ============================

(String, int) _romanizeKana(String text, int index) {
  // Check 2-character digraphs first (e.g., きゃ -> kya)
  if (index + 1 < text.length) {
    final pair = text.substring(index, index + 2);
    final mappedPair = _kanaDigraphs[pair];
    if (mappedPair != null) return (mappedPair, 2);
  }

  // Small tsu gemination (っ / ッ)
  final ch = text[index];
  if (ch == 'っ' || ch == 'ッ') {
    if (index + 1 < text.length) {
      final (nextRomaji, _) = _romanizeKana(text, index + 1);
      if (nextRomaji.isNotEmpty && !'aeiou'.contains(nextRomaji[0])) {
        return (nextRomaji[0], 1);
      }
    }
    return ('t', 1);
  }

  final single = _kanaSingle[ch];
  return (single ?? ch, 1);
}

const Map<String, String> _kanaSingle = {
  // Hiragana
  'あ': 'a', 'い': 'i', 'う': 'u', 'え': 'e', 'お': 'o',
  'か': 'ka', 'き': 'ki', 'く': 'ku', 'け': 'ke', 'こ': 'ko',
  'さ': 'sa', 'し': 'shi', 'す': 'su', 'せ': 'se', 'そ': 'so',
  'た': 'ta', 'ち': 'chi', 'つ': 'tsu', 'て': 'te', 'と': 'to',
  'な': 'na', 'に': 'ni', 'ぬ': 'nu', 'ね': 'ne', 'の': 'no',
  'は': 'ha', 'ひ': 'hi', 'ふ': 'fu', 'へ': 'he', 'ほ': 'ho',
  'ま': 'ma', 'み': 'mi', 'む': 'mu', 'め': 'me', 'も': 'mo',
  'や': 'ya', 'ゆ': 'yu', 'よ': 'yo',
  'ら': 'ra', 'り': 'ri', 'る': 'ru', 'れ': 're', 'ろ': 'ro',
  'わ': 'wa', 'ゐ': 'wi', 'ゑ': 'we', 'を': 'wo', 'ん': 'n',
  'が': 'ga', 'ぎ': 'gi', 'ぐ': 'gu', 'げ': 'ge', 'ご': 'go',
  'ざ': 'za', 'じ': 'ji', 'ず': 'zu', 'ぜ': 'ze', 'ぞ': 'zo',
  'だ': 'da', 'ぢ': 'ji', 'づ': 'zu', 'で': 'de', 'ど': 'do',
  'ば': 'ba', 'び': 'bi', 'ぶ': 'bu', 'べ': 'be', 'ぼ': 'bo',
  'ぱ': 'pa', 'ぴ': 'pi', 'ぷ': 'pu', 'ぺ': 'pe', 'ぽ': 'po',
  // Katakana
  'ア': 'a', 'イ': 'i', 'ウ': 'u', 'エ': 'e', 'オ': 'o',
  'カ': 'ka', 'キ': 'ki', 'ク': 'ku', 'ケ': 'ke', 'コ': 'ko',
  'サ': 'sa', 'シ': 'shi', 'ス': 'su', 'セ': 'se', 'ソ': 'so',
  'タ': 'ta', 'チ': 'chi', 'ツ': 'tsu', 'テ': 'te', 'ト': 'to',
  'ナ': 'na', 'ニ': 'ni', 'ヌ': 'nu', 'ネ': 'ne', 'ノ': 'no',
  'ハ': 'ha', 'ヒ': 'hi', 'フ': 'fu', 'ヘ': 'he', 'ホ': 'ho',
  'マ': 'ma', 'ミ': 'mi', 'ム': 'mu', 'メ': 'me', 'モ': 'mo',
  'ヤ': 'ya', 'ユ': 'yu', 'ヨ': 'yo',
  'ラ': 'ra', 'リ': 'ri', 'ル': 'ru', 'レ': 're', 'ロ': 'ro',
  'ワ': 'wa', 'ヰ': 'wi', 'ヱ': 'we', 'ヲ': 'wo', 'ン': 'n',
  'ガ': 'ga', 'ギ': 'gi', 'グ': 'gu', 'ゲ': 'ge', 'ゴ': 'go',
  'ザ': 'za', 'ジ': 'ji', 'ズ': 'zu', 'ゼ': 'ze', 'ゾ': 'zo',
  'ダ': 'da', 'ヂ': 'ji', 'ヅ': 'zu', 'デ': 'de', 'ド': 'do',
  'バ': 'ba', 'ビ': 'bi', 'ブ': 'bu', 'べ': 'be', 'ボ': 'bo',
  'パ': 'pa', 'ピ': 'pi', 'プ': 'pu', 'ペ': 'pe', 'ポ': 'po',
};

const Map<String, String> _kanaDigraphs = {
  'きゃ': 'kya', 'きゅ': 'kyu', 'きょ': 'kyo',
  'しゃ': 'sha', 'しゅ': 'shu', 'しょ': 'sho',
  'ちゃ': 'cha', 'ちゅ': 'chu', 'ちょ': 'cho',
  'にゃ': 'nya', 'にゅ': 'nyu', 'にょ': 'nyo',
  'ひゃ': 'hya', 'ひゅ': 'hyu', 'ひょ': 'hyo',
  'みゃ': 'mya', 'みゅ': 'myu', 'みょ': 'myo',
  'りゃ': 'rya', 'りゅ': 'ryu', 'りょ': 'ryo',
  'ぎゃ': 'gya', 'ぎゅ': 'gyu', 'ぎょ': 'gyo',
  'じゃ': 'ja', 'じゅ': 'ju', 'じょ': 'jo',
  'びゃ': 'bya', 'びゅ': 'byu', 'びょ': 'byo',
  'ぴゃ': 'pya', 'ぴゅ': 'pyu', 'ぴょ': 'pyo',
  'キャ': 'kya', 'キュ': 'kyu', 'キョ': 'kyo',
  'シャ': 'sha', 'シュ': 'shu', 'ショ': 'sho',
  'チャ': 'cha', 'チュ': 'chu', 'チョ': 'cho',
  'ニャ': 'nya', 'ニュ': 'nyu', 'ニョ': 'nyo',
  'ヒャ': 'hya', 'ヒュ': 'hyu', 'ヒョ': 'hyo',
  'ミャ': 'mya', 'ミュ': 'myu', 'ミョ': 'myo',
  'リャ': 'rya', 'リュ': 'ryu', 'リョ': 'ryo',
  'ギャ': 'gya', 'ギュ': 'gyu', 'ギョ': 'gyo',
  'ジャ': 'ja', 'ジュ': 'ju', 'ジョ': 'jo',
  'ビャ': 'bya', 'ビュ': 'byu', 'ビョ': 'byo',
  'ピャ': 'pya', 'ピュ': 'pyu', 'ピョ': 'pyo',
};
