/// Blank names from a platform: the app supplies the language, and providers
/// work without it.
library;

import 'package:bloom/app/providers.dart';
import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/providers/provider_text.dart';
import 'package:bloom/providers/soundcloud/sc_provider.dart';
import 'package:bloom/providers/yandex/yandex.dart' as ym;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _account = Artist(
  id: 'sc:artist:1',
  name: 'Name',
  source: MusicSource.soundcloud,
);

void main() {
  tearDown(() => providerTextSource = null);

  test('with no language the names are English', () {
    expect(scLikesOf(_account).title, 'Likes · Name');
    final track = ym.parseTrack({'id': 1})!;
    expect(track.title, 'Untitled');
    expect(track.artist, 'Unknown');
  });

  test('the given language reaches the providers', () {
    providerTextSource = () => ProviderText(
      untitled: 'Без названия',
      unknownArtist: 'Неизвестный',
      likesOf: (account) => 'Лайки · $account',
    );
    expect(scLikesOf(_account).title, 'Лайки · Name');
    final track = ym.parseTrack({'id': 1})!;
    expect(track.title, 'Без названия');
    expect(track.artist, 'Неизвестный');
  });

  test('a source with no language yet falls back to English', () {
    providerTextSource = () => null;
    expect(providerText.untitled, 'Untitled');
  });

  test('the registry hooks up the language', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(registryProvider);
    expect(providerTextSource, isNotNull);
  });
}
