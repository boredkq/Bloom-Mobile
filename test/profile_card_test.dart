/// The profile card: kv `profile` with "#hex" colors, "Auto" cover mode by
/// default, lengths 32/300/80, the since date in `profile.since`.
library;

import 'package:bloom/core/db/db.dart';
import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/play_log.dart';
import 'package:bloom/features/profile/profile_store.dart';
import 'package:bloom/features/profile/stats.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ProviderContainer _container(BloomDb db) {
  var now = DateTime(2026, 9, 1).millisecondsSinceEpoch;
  final c = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(JsonStore.memory()),
      dbProvider.overrideWithValue(db),
      playLogClockProvider.overrideWithValue(
        () => DateTime.fromMillisecondsSinceEpoch(now += 60000),
      ),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Track _track(String id, {String? cover}) => Track(
  id: id,
  name: 'Song $id',
  artist: 'Artist',
  duration: const Duration(seconds: 100),
  source: MusicSource.soundcloud,
  cover: cover,
);

void main() {
  test('пустой профиль — «Авто», цвета ПК по умолчанию', () {
    final p = _container(BloomDb.memory()).read(profileProvider);
    expect(p.bannerMode, BannerColorMode.auto);
    expect(p.toJson(), {
      'name': '',
      'bio': '',
      'status': '',
      'avatar': '',
      'banner': '',
      'bannerMode': 'auto',
      'bannerColor': '#1a1a1a',
      'bannerColor2': '#0d0d0d',
      'bannerAngle': 135,
    });
  });

  test('сохраняется в kv базы видом ПК и читается после перезапуска', () {
    final db = BloomDb.memory();
    _container(db)
        .read(profileProvider.notifier)
        .save(
          const UserProfile(
            name: 'Онига',
            bannerMode: BannerColorMode.gradient,
            bannerColor: Color(0xFFFF8800),
            bannerColor2: Color(0xFF0011AA),
            bannerAngle: 45,
            avatar: 'local:ava-1.png',
          ),
        );

    final card = db.getMap('profile');
    expect(card['bannerColor'], '#ff8800');
    expect(card['bannerColor2'], '#0011aa');
    expect(card['bannerMode'], 'gradient');
    expect(card['banner'], '');

    final again = _container(db).read(profileProvider);
    expect(again.name, 'Онига');
    expect(again.bannerColor, const Color(0xFFFF8800));
    expect(again.bannerAngle, 45);
    expect(again.avatar, 'local:ava-1.png');
    expect(again.banner, isNull);
  });

  test('чужая карточка приводится, как normalized ПК', () {
    final p = UserProfile.fromJson({
      'name': '  ${'н' * 40}  ',
      'bio': 'б' * 400,
      'status': 'с' * 100,
      'bannerMode': 'rainbow',
      'bannerColor': 'not a colour',
      'bannerColor2': '#abc',
      'bannerAngle': -45,
    });
    expect(p.name.length, kNickMax);
    expect(p.bio.length, kBioMax);
    expect(p.status.length, kStatusMax);
    expect(p.bannerMode, BannerColorMode.auto);
    expect(p.bannerColor, const Color(0xFF1A1A1A));
    expect(p.bannerColor2, const Color(0xFFAABBCC));
    expect(p.bannerAngle, 315);
  });

  test('«С нами с» ставится один раз и переживает перезапуск', () {
    final db = BloomDb.memory();
    final first = _container(db).read(profileSinceProvider);
    expect(db.get('profile.since'), first.millisecondsSinceEpoch);
    expect(_container(db).read(profileSinceProvider), first);
  });

  test('обложка для «Авто» — самого слушаемого трека с обложкой', () {
    final c = _container(BloomDb.memory());
    final log = c.read(playLogProvider.notifier);
    // The most heard one has no cover, so it doesn't count.
    for (var i = 0; i < 5; i++) {
      log.log(_track('sc:0'));
    }
    for (var i = 0; i < 3; i++) {
      log.log(_track('sc:1', cover: 'https://a/1.jpg'));
    }
    for (var i = 0; i < 2; i++) {
      log.log(_track('sc:2', cover: 'https://a/2.jpg'));
    }
    expect(c.read(profileStatsProvider).topCover, 'https://a/1.jpg');

    // A tie goes to the one heard later.
    log.log(_track('sc:2', cover: 'https://a/2.jpg'));
    expect(c.read(profileStatsProvider).topCover, 'https://a/2.jpg');
  });
}
