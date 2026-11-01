/// One sync round with the computer, driven by the phone: (1) `GET /v1/sync`:
/// the computer's id and clock, and how far it took ours (`got`); (2) ours from
/// that cursor (`ownOnly`): first pictures it lacks, then `POST /v1/sync/push`,
/// while `more`; (3) `POST /v1/sync/pull` from our cursors, pictures we lack
/// and [SyncLog.apply], while `more`.
///
/// Clocks: a change wins by its `mod`, the device's clock. The difference is
/// measured at the start of a round; if noticeable, `mod` of outgoing changes
/// converts to the computer's clock and of incoming to ours. Plays don't shift:
/// they recognise their duplicates by time.
library;

import 'dart:typed_data';

import '../db/db.dart';
import '../log/bloom_log.dart';
import 'pc_client.dart';
import 'sync_log.dart';
import 'sync_pictures.dart';

/// A clock difference below this isn't one (the network alone gives tens of
/// ms).
const int _kSkewMs = 2000;

/// How a round ended.
class SyncRound {
  const SyncRound({
    required this.link,
    required this.touched,
    required this.sent,
    required this.took,
    required this.pushed,
  });

  /// The link with the address the computer answered at, worth saving.
  final PcLink link;

  /// How far the computer took ours, compared with [SyncLog.head] (`ownOnly`).
  final ({int seq, int play}) pushed;

  /// Kinds changed here ([SyncLog.apply]).
  final Set<String> touched;
  final int sent, took;
}

/// The computer wasn't found at any address or by discovery.
class PcUnreachable implements Exception {
  const PcUnreachable();
}

/// Another computer answered at the address (its database is new, so a new id).
class PcChanged implements Exception {
  const PcChanged();
}

Future<SyncRound> syncWithPc(PcLink link, BloomDb db, String coversDir) async {
  final reached = await reachPc(link);
  final client = reached.client;
  link = reached.link;
  final hello = reached.hello;
  if (hello['device'] != link.device) throw const PcChanged();
  final skew = reached.skew;

  final log = SyncLog(db);
  final pictures = SyncPictures(db, coversDir);

  // ── ours to the computer ──
  var sent = 0;
  var cursor = hello['got'] is Map ? hello['got'] as Map : const {};
  while (true) {
    final out = log.outgoing(
      link.device,
      seq: _int(cursor['seq']),
      play: _int(cursor['play']),
      ownOnly: true,
    );
    final names = pictures.toWire(out);
    _shift(out, skew);
    if (names.isNotEmpty) {
      final ask = await client.json(
        'POST',
        '/v1/sync/pictures',
        body: {'names': names.toList()},
      );
      for (final name in (ask['missing'] as List?) ?? const []) {
        final bytes = name is String ? pictures.read(name) : null;
        if (bytes != null) {
          await client.send('PUT', '/v1/sync/picture/$name', body: bytes);
        }
      }
    }
    final res = await client.json(
      'POST',
      '/v1/sync/push',
      body: out,
      timeout: const Duration(seconds: 60),
    );
    sent += (out['changes'] as List).length + (out['plays'] as List).length;
    cursor = res['got'] is Map ? res['got'] as Map : const {};
    if (out['more'] != true) break;
  }

  // ── the computer's to here ──
  var took = 0;
  final touched = <String>{};
  while (true) {
    final from = log.got(link.device);
    final payload = await client.json(
      'POST',
      '/v1/sync/pull',
      body: {'seq': from.seq, 'play': from.play},
      timeout: const Duration(seconds: 60),
    );
    for (final name in pictures.wanted(payload)) {
      if (pictures.has(name)) continue;
      try {
        final bytes = await client.send('GET', '/v1/sync/picture/$name');
        pictures.put(name, Uint8List.fromList(bytes));
      } on PcHttpError catch (e) {
        // It no longer has it: the change comes with no picture.
        if (e.status != 404) rethrow;
      }
    }
    pictures.fromWire(payload);
    _shift(payload, -skew);
    if (!log.apply(payload, touched: touched)) {
      throw const PcHttpError(0, 'refused');
    }
    took +=
        ((payload['changes'] as List?) ?? const []).length +
        ((payload['plays'] as List?) ?? const []).length;
    if (payload['more'] != true) break;
  }
  logInfo(
    'sync',
    'с ПК «${link.name}»: отдал $sent, взял $took · ${touched.join(' ')}',
  );
  return SyncRound(
    link: link,
    touched: touched,
    sent: sent,
    took: took,
    pushed: (seq: _int(cursor['seq']), play: _int(cursor['play'])),
  );
}

/// Where the computer is now: the last answering address, then the rest at
/// once, then discovery by print.
Future<({PcClient client, PcLink link, Map<String, Object?> hello, int skew})>
reachPc(PcLink link) async {
  Future<({PcClient client, Map<String, Object?> hello, int skew})?> hello(
    String address,
    int port,
  ) async {
    final c = PcClient(address, port, print: link.print, token: link.token);
    try {
      final t0 = DateTime.now().millisecondsSinceEpoch;
      final h = await c.json(
        'GET',
        '/v1/sync',
        timeout: const Duration(seconds: 5),
      );
      final t1 = DateTime.now().millisecondsSinceEpoch;
      final skew = _int(h['now']) - (t0 + t1) ~/ 2;
      return (client: c, hello: h, skew: skew.abs() < _kSkewMs ? 0 : skew);
    } on PcHttpError {
      rethrow; // it answered but refused: no point searching further
    } on PcPrintMismatch {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  if (link.addresses.isNotEmpty) {
    final first = await hello(link.addresses.first, link.port);
    if (first != null) {
      return (
        client: first.client,
        link: link,
        hello: first.hello,
        skew: first.skew,
      );
    }
  }
  final rest = link.addresses.skip(1).toList();
  if (rest.isNotEmpty) {
    final tries = await Future.wait([
      for (final a in rest) hello(a, link.port),
    ]);
    for (var i = 0; i < rest.length; i++) {
      final r = tries[i];
      if (r != null) {
        return (
          client: r.client,
          link: link.at(rest[i], link.port),
          hello: r.hello,
          skew: r.skew,
        );
      }
    }
  }
  for (final pc in await findPcs(print: link.print, to: link.addresses)) {
    if (pc.device != link.device) continue;
    final r = await hello(pc.address, pc.port);
    if (r != null) {
      return (
        client: r.client,
        link: link.at(pc.address, pc.port),
        hello: r.hello,
        skew: r.skew,
      );
    }
  }
  throw const PcUnreachable();
}

void _shift(Map<String, Object?> payload, int by) {
  if (by == 0) return;
  for (final c in (payload['changes'] as List?) ?? const []) {
    if (c is Map && c['mod'] is num) c['mod'] = (c['mod'] as num).toInt() + by;
  }
}

int _int(Object? v) => v is num ? v.toInt() : 0;
