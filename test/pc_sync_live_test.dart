/// Syncing with a real computer: [syncWithPc] against a running Bloom on the
/// home network. Two "phones" are two databases paired with the computer by its
/// QR code.
///
/// A normal run skips it: it needs a pairing file in `BLOOM_LIVE_PC` (`{"a":
/// {"id", "link"}, "b": {...}}`), written by a helper that starts Bloom, reads
/// the QR code off a window snapshot and pairs both ids.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:bloom/core/db/db.dart';
import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/library_store.dart';
import 'package:bloom/core/sync/pc_client.dart';
import 'package:bloom/core/sync/pc_sync.dart';
import 'package:bloom/core/sync/sync_pictures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Phone {
  _Phone(Map raw) : link = PcLink.fromJson(raw['link'])! {
    db = BloomDb.memory();
    db.set('sync.device', raw['id'] as String);
    dir = Directory.systemTemp.createTempSync('bloom_live_').path;
    store = JsonStore.memory();
    c = ProviderContainer(
      overrides: [
        jsonStoreProvider.overrideWithValue(store),
        dbProvider.overrideWithValue(db),
      ],
    );
  }

  PcLink link;
  late final BloomDb db;
  late final String dir;
  late final JsonStore store;
  late final ProviderContainer c;

  LibraryController get lib => c.read(libraryProvider.notifier);

  Future<SyncRound> sync() async {
    final r = await syncWithPc(link, db, dir);
    link = r.link;
    return r;
  }

  Map<String, Object?>? list(String name) {
    final rows = db.select('SELECT * FROM lists WHERE name = ?', [name]);
    return rows.isEmpty ? null : Map.of(rows.first);
  }
}

void main() {
  final path = Platform.environment['BLOOM_LIVE_PC'];

  test(
    'phone A sends a playlist, a picture, a play; phone B gets them through the PC',
    () async {
      // flutter_test swaps HttpClient for a stub, and this needs the real
      // network.
      HttpOverrides.global = null;
      final links = jsonDecode(File(path!).readAsStringSync()) as Map;
      final a = _Phone(links['a'] as Map), b = _Phone(links['b'] as Map);

      // ── A: its playlist with its cover, a profile with the same picture, a
      // play. A real 1×1 PNG: the computer will show it too.
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
      );
      File('${a.dir}/cover_1.png').writeAsBytesSync(png);
      const track = Track(
        id: 'sc:live1',
        name: 'Live song',
        artist: 'Live artist',
        duration: Duration(seconds: 180),
        source: MusicSource.soundcloud,
      );
      a.lib.createPlaylist(
        'Live A',
        tracks: [track],
        cover: 'local:cover_1.png',
      );
      a.db.set('profile', {
        'name': 'Phone A',
        'bio': '',
        'status': 'live',
        'avatar': 'local:cover_1.png',
        'banner': '',
        'bannerMode': 'auto',
        'bannerColor': '#1a1a1a',
        'bannerColor2': '#0d0d0d',
        'bannerAngle': 135,
      });
      final ts = DateTime.now().millisecondsSinceEpoch - 60000;
      a.db.exec('INSERT INTO plays (ts, track_id) VALUES (?, ?)', [
        ts,
        track.id,
      ]);

      final ra = await a.sync();
      expect(ra.sent, greaterThan(0));

      // ── On the computer: its own playlist, made through its API with the
      // device key
      final pcLink = a.link;
      final pc = PcClient(
        pcLink.addresses.first,
        pcLink.port,
        print: pcLink.print,
        token: pcLink.token,
      );
      await pc.json('POST', '/v1/library/create', body: {'name': 'Made on PC'});

      // ── B: everything arrived, the picture as the same file
      final rb = await b.sync();
      expect(rb.touched, containsAll(['list', 'item', 'kv', 'plays']));
      final live = b.list('Live A');
      expect(live, isNotNull);
      final cover = live!['cover'] as String;
      final name = pictureName(png);
      expect(cover, 'local:$name');
      expect(File('${b.dir}/$name').readAsBytesSync(), png);
      final card = b.db.getMap('profile');
      expect(card['avatar'], 'local:$name');
      expect(card['status'], 'live');
      expect(
        b.db.value(
          'SELECT count(*) FROM plays WHERE track_id = ? AND ts = ? AND device = ?',
          [track.id, ts, a.db.get('sync.device')],
        ),
        1,
      );
      expect(b.list('Made on PC'), isNotNull);
      expect(
        b.db.value(
          "SELECT count(*) FROM list_tracks lt JOIN lists l ON l.id = lt.list_id WHERE l.name = 'Live A'",
        ),
        1,
      );

      // ── A: takes the computer's playlist, its own doesn't come back
      final again = await a.sync();
      expect(a.list('Made on PC'), isNotNull);
      expect(a.db.value("SELECT count(*) FROM lists WHERE name = 'Live A'"), 1);
      expect(again.touched.contains('plays'), isFalse);

      // ── B renamed A's playlist, and A sees it
      final id = live['id'] as String;
      b.lib.renamePlaylist(id, 'Live A (renamed on B)');
      await b.sync();
      await a.sync();
      expect(a.list('Live A (renamed on B)'), isNotNull);
      // The cover survived the trip there and back.
      expect(a.list('Live A (renamed on B)')!['cover'], 'local:cover_1.png');
    },
    skip: path == null ? 'BLOOM_LIVE_PC is not set' : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
