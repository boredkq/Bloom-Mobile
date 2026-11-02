/// A playback error: code to phrase.
///
/// I check what breaks quietly. Providers throw dictionary codes and the player
/// shows text under the title: a miss here shows "search.err.drm" instead of a
/// phrase. Plus `StateError`, which prepends its "Bad state: " and keeps the
/// code from matching.
library;

import 'package:bloom/core/l10n/l10n.dart';
import 'package:bloom/features/player/play_error.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppLocalizations ru;

  setUpAll(() async {
    ru = await AppLocalizations.delegate.load(const Locale('ru'));
  });

  group('код из исключения', () {
    test('«Bad state:» от StateError до словаря не доезжает', () {
      expect(
        playErrorCode(StateError('search.err.noStream')),
        'search.err.noStream',
      );
    });

    test('своё исключение площадки отдаёт голый код', () {
      expect(playErrorCode(const _Code('search.err.drm')), 'search.err.drm');
    });
  });

  group('DRM', () {
    test('коды площадок разные, признак один', () {
      expect(isDrmError('search.err.drm'), isTrue);
      expect(isDrmError('sc.err.drm'), isTrue);
      expect(isDrmError('search.err.noStream'), isFalse);
    });
  });

  group('фраза', () {
    test('знакомый код разворачивается', () {
      expect(describePlayError(ru, 'search.err.drm'), ru.errDrm);
      expect(describePlayError(ru, 'sc.err.drm'), ru.errDrm);
      expect(describePlayError(ru, 'ytm.err.noAudio'), ru.errYtmNoAudio);
    });

    test('коды Яндекса идут в свой словарь, а не мимо', () {
      expect(describePlayError(ru, 'ym.err.needPlus'), ru.ymErrNeedPlus);
    });

    test('незнакомое — текст самой площадки, показываем как есть', () {
      expect(describePlayError(ru, 'SC API error'), 'SC API error');
    });
  });
}

/// A platform exception: `toString` is the code itself.
class _Code implements Exception {
  const _Code(this.code);

  final String code;

  @override
  String toString() => code;
}
