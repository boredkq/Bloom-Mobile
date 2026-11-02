/// Sync in the database: [SyncLog]. Two "devices" are two databases, and
/// packets go between them through JSON, as over the network. The fixture and
/// the packet this test writes check the format against the computer's side.
library;

import 'dart:convert';
import 'dart:io';

import 'package:bloom/core/db/db.dart';
import 'package:bloom/core/db/track_store.dart';
import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/library_store.dart';
import 'package:bloom/core/sync/sync_log.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_db.dart';

Track _track(String id, {String name = 'Song'}) => Track(
  id: id,
  name: name,
  artist: 'Artist',
  duration: const Duration(seconds: 100),
  source: id.startsWith('ytm:') ? MusicSource.ytmusic : MusicSource.soundcloud,
);

/// A device: its own database and its own library over it.
class _Device {
  _Device() : store = JsonStore.memory() {
    db = testDb(store);
    c = ProviderContainer(
      overrides: [
        jsonStoreProvider.overrideWithValue(store),
        dbProvider.overrideWithValue(db),
      ],
    );
    addTearDown(c.dispose);
  }

  final JsonStore store;
  late final BloomDb db;
  late final ProviderContainer c;

  LibraryController get lib => c.read(libraryProvider.notifier);
  SyncLog get log => SyncLog(db);
  String get id => log.device();

  int count(String sql, [List<Object?> args = const []]) =>
      db.value(sql, args) as int;

  Set<String> ids(String list) => {
    for (final r in db.select(
      'SELECT track_id FROM list_tracks WHERE list_id = ?',
      [list],
    ))
      r['track_id'] as String,
  };

  List<String> ordered(String list) => [
    for (final r in db.select(
      'SELECT track_id FROM list_tracks WHERE list_id = ? ORDER BY pos',
      [list],
    ))
      r['track_id'] as String,
  ];

  void play(String id, int ts) {
    TrackStore(db).put([_track(id)]);
    db.exec('INSERT INTO plays (ts, track_id) VALUES (?, ?)', [ts, id]);
  }

  int get plays => count('SELECT count(*) FROM plays');
  int marks(String kind) =>
      count('SELECT count(*) FROM changes WHERE kind = ?', [kind]);
}

Map<String, Object?> _wire(Map<String, Object?> m) =>
    jsonDecode(jsonEncode(m)) as Map<String, Object?>;

/// One sync of the phone with the computer: the phone's changes go up, then
/// everything the phone lacks comes down. Returns the number of rounds.
int _sync(_Device pc, _Device phone, {int limit = 2000, Set<String>? touched}) {
  var rounds = 0;
  for (var more = true; more; rounds++) {
    final at = pc.log.got(phone.id);
    final out = _wire(
      phone.log.outgoing(
        pc.id,
        seq: at.seq,
        play: at.play,
        ownOnly: true,
        limit: limit,
      ),
    );
    expect(pc.log.apply(out, touched: touched), isTrue);
    more = out['more'] as bool;
  }
  for (var more = true; more; rounds++) {
    final at = phone.log.got(pc.id);
    final out = _wire(
      pc.log.outgoing(phone.id, seq: at.seq, play: at.play, limit: limit),
    );
    expect(phone.log.apply(out, touched: touched), isTrue);
    more = out['more'] as bool;
  }
  return rounds;
}

void main() {
  test("listener edits are marked, service ones aren't", () {
    final d = _Device();
    final pl = d.lib.createPlaylist(
      'P',
      tracks: [_track('sc:1'), _track('sc:2')],
    );
    expect(d.marks('list'), 1);
    expect(d.marks('item'), 4); // in the playlist and in All tracks
    final top = d.db.value('SELECT max(seq) FROM changes');
    d.db.exec('UPDATE lists SET updated_at = 5 WHERE id = ?', [pl.id]);
    expect(d.db.value('SELECT max(seq) FROM changes'), top);
    d.lib.renamePlaylist(pl.id, 'Q');
    expect(
      d.db.value('SELECT kind FROM changes ORDER BY seq DESC LIMIT 1'),
      'list',
    );
    d.lib.setPlaylistTracks(pl.id, ['sc:2', 'sc:1']); // a reorder
    expect(d.marks('item'), 4);
    d.db.set('profile', {'nick': 'a'});
    d.db.set('other', 1);
    expect(d.marks('kv'), 1);
    d.lib.replaceTrack('sc:1', _track('ytm:1'));
    expect(d.marks('rekey'), 1);
    d.lib.deletePlaylist(pl.id);
    expect(d.marks('list'), 1); // a deleted one keeps its mark
    expect(d.id, hasLength(32));
    expect(d.log.device(), d.id);
  });

  test("Reset all doesn't mark what it erased as deletions", () {
    final d = _Device();
    d.lib.toggleFav(_track('sc:1'));
    d.db.set('profile', {'nick': 'a'});
    d.db.wipe();
    expect(d.count('SELECT count(*) FROM changes'), 0);
  });

  test('phone and computer converge', () {
    final pc = _Device(), phone = _Device();
    final pl = pc.lib.createPlaylist(
      'Road',
      tracks: [_track('sc:1'), _track('sc:2')],
    );
    pc.lib.toggleFav(_track('sc:1'));
    pc.lib.addToLibrary([_track('lf:x')]);
    pc.db.exec(
      "INSERT INTO follows (id, provider, name, at) VALUES ('sc:artist:9', 'sc', 'Nine', 1)",
    );
    pc.db.exec("INSERT INTO dislikes (track_id, at) VALUES ('sc:2', 7)");
    pc.db.set('profile', {'nick': 'pc'});
    pc.db.set('profile.since', 5000);
    pc.play('sc:1', 1000);
    pc.play('sc:2', 2000);
    pc.play('lf:x', 2500);
    pc.db.exec("INSERT INTO days (day, app_ms) VALUES ('2026-10-01', 100)");
    phone.lib.toggleFav(_track('ytm:5'));
    phone.db.set('profile.since', 3000);
    phone.play('ytm:5', 1500);
    phone.db.exec("INSERT INTO days (day, app_ms) VALUES ('2026-10-01', 40)");

    _sync(pc, phone);
    for (final d in [pc, phone]) {
      final isPc = identical(d, pc);
      expect(d.ids(kFavList), {'sc:1', 'ytm:5'});
      expect(d.ids(kLibList).contains('lf:x'), isPc);
      expect(d.ordered(pl.id), pc.ordered(pl.id));
      expect(
        d.db.value('SELECT name FROM lists WHERE id = ?', [pl.id]),
        'Road',
      );
      expect(
        d.db.value("SELECT name FROM follows WHERE id = 'sc:artist:9'"),
        'Nine',
      );
      expect(d.db.value("SELECT at FROM dislikes WHERE track_id = 'sc:2'"), 7);
      expect(d.db.getMap('profile')['nick'], 'pc');
      expect(d.db.get('profile.since'), 3000);
      expect(d.plays, isPc ? 4 : 3); // a file's play stays on the computer
      expect(d.count('SELECT sum(app_ms) FROM days'), 140);
      expect(
        d.count("SELECT count(*) FROM tracks WHERE id LIKE 'lf:%'"),
        isPc ? 1 : 0,
      );
    }
    final touched = <String>{};
    _sync(pc, phone, touched: touched);
    expect(touched, isEmpty); // nothing new, nothing taken
  });

  test(
    'deletions, a later change, a move, tags and a clear get across',
    () async {
      final pc = _Device(), phone = _Device();
      final pl = pc.lib.createPlaylist(
        'P',
        tracks: [_track('sc:1'), _track('sc:2'), _track('sc:3')],
      );
      pc.lib.toggleFav(_track('sc:1'));
      _sync(pc, phone);

      phone.lib.removeTrackFromPlaylist(pl.id, 'sc:2');
      _sync(pc, phone);
      expect(pc.ids(pl.id), {'sc:1', 'sc:3'});

      // Renamed on both: the later one stays everywhere.
      pc.lib.renamePlaylist(pl.id, 'A');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      phone.lib.renamePlaylist(pl.id, 'B');
      _sync(pc, phone);
      for (final d in [pc, phone]) {
        expect(d.db.value('SELECT name FROM lists WHERE id = ?', [pl.id]), 'B');
      }

      // A removed like doesn't come back from the side that still had it.
      phone.lib.toggleFav(_track('sc:1'));
      _sync(pc, phone);
      _sync(pc, phone);
      for (final d in [pc, phone]) {
        expect(d.ids(kFavList), isEmpty);
      }

      // The track moved to another platform, and its plays follow there too.
      phone.play('sc:1', 1000);
      pc.lib.replaceTrack('sc:1', _track('ytm:1'));
      _sync(pc, phone);
      for (final d in [pc, phone]) {
        expect(d.ids(kLibList).contains('ytm:1'), isTrue);
        expect(d.ids(kLibList).contains('sc:1'), isFalse);
        expect(d.ordered(pl.id).first, 'ytm:1');
        expect(
          d.count("SELECT count(*) FROM plays WHERE track_id = 'ytm:1'"),
          1,
        );
      }

      // Tags fixed by hand get across; a refresh from the platform leaves them
      // alone.
      pc.db.exec(
        "UPDATE tracks SET title = 'Mine', extra = json_set(extra, '\$.edited', json('true')) WHERE id = 'sc:3'",
      );
      _sync(pc, phone);
      TrackStore(phone.db).put([_track('sc:3', name: 'Platform')]);
      expect(TrackStore(phone.db).getOne('sc:3')!.name, 'Mine');

      // Clearing stats: plays before it go everywhere, level XP stays.
      pc.play('sc:3', 2000);
      pc.db.exec("INSERT INTO days (day, app_ms) VALUES ('2020-01-01', 100)");
      _sync(pc, phone);
      expect(phone.plays, 2);
      pc.db.tx(() {
        pc.db.exec('DELETE FROM plays');
        pc.db.exec('DELETE FROM days');
        pc.log.markCleared(123);
      });
      await Future<void>.delayed(const Duration(milliseconds: 5));
      phone.play('sc:3', BloomDb.now()); // after the clear, so it stays
      _sync(pc, phone);
      for (final d in [pc, phone]) {
        expect(d.plays, 1);
        expect(
          d.count("SELECT count(*) FROM days WHERE day = '2020-01-01'"),
          0,
        );
      }
      expect(phone.db.get('level.banked'), 123);
    },
  );

  test('small rounds and a second phone through the computer', () {
    final pc = _Device(), a = _Device(), b = _Device();
    pc.lib.addToLibrary([for (var i = 0; i < 30; i++) _track('sc:$i')]);
    for (var i = 0; i < 25; i++) {
      pc.play('sc:$i', 1000 + i);
    }
    a.lib.addToFavorites([_track('ytm:1'), _track('ytm:2'), _track('ytm:3')]);
    a.play('ytm:1', 5000);
    expect(_sync(pc, a, limit: 10), greaterThan(4));
    expect(a.ids(kLibList), hasLength(33));
    expect(a.plays, 26);

    _sync(pc, b, limit: 10);
    expect(b.ids(kFavList), contains('ytm:2'));
    expect(b.plays, 26);
    b.lib.toggleFav(_track('ytm:2'));
    _sync(pc, b);
    _sync(pc, a);
    for (final d in [pc, a, b]) {
      expect(d.ids(kFavList), {'ytm:1', 'ytm:3'});
      expect(d.plays, 26);
    }
    // The phone's own plays don't come back to it as foreign.
    expect(a.count('SELECT count(*) FROM plays WHERE device = ?', [a.id]), 0);
  });

  test("the computer's packet is accepted, mine goes to the computer", () {
    final payload =
        jsonDecode(File('test/fixtures/sync_from_pc.json').readAsStringSync())
            as Map<String, Object?>;
    final phone = _Device();
    phone.lib.toggleFav(_track('sc:4')); // moved to ytm:4 on the computer
    final touched = <String>{};
    expect(phone.log.apply(payload, touched: touched), isTrue);
    expect(
      touched,
      containsAll([
        'list',
        'item',
        'follow',
        'dislike',
        'kv',
        'track',
        'rekey',
        'plays',
        'days',
      ]),
    );

    final road =
        phone.db.value("SELECT id FROM lists WHERE name = 'Road'") as String;
    expect(phone.ordered(road), ['sc:2', 'sc:1']);
    expect(phone.ids(kFavList), {'sc:1', 'ytm:4'});
    expect(phone.ids(kLibList), containsAll(['sc:1', 'sc:2', 'sc:3', 'ytm:4']));
    expect(phone.ids(kLibList), isNot(contains('sc:4')));
    expect(
      phone.db.value("SELECT name FROM follows WHERE id = 'sc:artist:9'"),
      'Nine',
    );
    expect(
      phone.db.value("SELECT at FROM dislikes WHERE track_id = 'sc:2'"),
      7,
    );
    expect(phone.db.getMap('profile')['nick'], 'pc');
    expect(phone.db.get('profile.since'), 5000);
    expect(
      phone.count('SELECT count(*) FROM plays WHERE device = ?', [
        payload['device'],
      ]),
      2,
    );
    expect(
      phone.count('SELECT app_ms FROM days WHERE device = ?', [
        payload['device'],
      ]),
      100,
    );
    expect(TrackStore(phone.db).getOne('sc:3')!.name, 'Mine');
    expect(phone.log.got(payload['device'] as String).seq, payload['seq']);

    // The other way: a like, a playlist, a play, a day and the sc:1 move, for
    // the computer's side to apply.
    phone.lib.toggleFav(_track('ytm:7'));
    phone.lib.createPlaylist('Phone list', tracks: [_track('ytm:7')]);
    phone.play('ytm:7', 9000);
    phone.db.exec("INSERT INTO days (day, app_ms) VALUES ('2026-10-02', 77)");
    phone.lib.replaceTrack('sc:1', _track('ytm:1'));
    final out = phone.log.outgoing(payload['device'] as String, ownOnly: true);
    File(
      '${Directory.systemTemp.path}/bloom_sync_from_phone.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
    // Only what was made here: what the computer sent doesn't go back to it
    // (except a playlist that travels with its track).
    for (final c in (out['changes'] as List).cast<Map>()) {
      if (c['kind'] != 'list') expect(c['device'], phone.id);
    }
  });
}
