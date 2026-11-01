/// Sync with the computer. The phone pairs with Bloom there (a QR or a code
/// from its Connect phone screen) and then goes to it by itself: at launch, on
/// return and on leaving, every couple of minutes while open, and by a button.
/// With the computer offline, a round quietly skips. The round itself is
/// [syncWithPc].
///
/// While the app is on screen and the computer answers, the phone holds its
/// event stream: `sync` means it has something new and a round goes at once; an
/// own edit goes a couple of seconds after writes settle.
///
/// The link lies in kv `sync.pc` (the phone's key only here, the computer holds
/// its hash), the last good round's time in `sync.at`. Reset everything takes
/// both with the database.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteUpdate;

import '../../core/db/db.dart';
import '../../core/log/bloom_log.dart';
import '../../core/store/cover_store.dart';
import '../../core/store/days_store.dart';
import '../../core/store/library_store.dart';
import '../../core/store/play_log.dart';
import '../../core/store/text_files.dart';
import '../../core/sync/pc_client.dart';
import '../../core/sync/pc_sync.dart';
import '../../core/sync/sync_log.dart';
import '../home/for_you.dart';
import '../home/similar_to.dart';
import '../profile/achievements.dart';
import '../profile/level.dart';
import '../profile/profile_store.dart';
import 'pc_remote.dart';

const String _kLink = 'sync.pc';
const String _kAt = 'sync.at';

/// How often to go to the computer while the app is on screen.
const Duration _kEvery = Duration(minutes: 2);

/// An own edit goes when database writes have been quiet this long.
const Duration _kEditSettle = Duration(seconds: 2);

/// How soon to retry after the event stream dropped.
const Duration _kRetry = Duration(seconds: 15);

enum PcStatus {
  /// Not paired, or no round yet.
  idle,
  syncing,

  /// The last round passed.
  ok,

  /// The computer wasn't found on the network.
  offline,

  /// The computer won't let in any more: it disconnected the phone, was reset
  /// or is another computer.
  repair,

  /// Something broke mid-round.
  failed,
}

/// How pairing ended.
enum PairResult { ok, notBloom, unreachable, wrong, closed, tooMany, failed }

@immutable
class PcState {
  const PcState({
    this.link,
    this.status = PcStatus.idle,
    this.lastSync = 0,
    this.live = false,
  });

  final PcLink? link;
  final PcStatus status;

  /// The event stream is open: the computer is connected right now (Connect).
  final bool live;

  /// Last good round, ms; 0 if none.
  final int lastSync;

  bool get paired => link != null;

  PcState copyWith({
    PcLink? link,
    bool unlink = false,
    PcStatus? status,
    int? lastSync,
    bool? live,
  }) => PcState(
    link: unlink ? null : (link ?? this.link),
    status: status ?? this.status,
    lastSync: lastSync ?? this.lastSync,
    live: live ?? this.live,
  );
}

final pcProvider = NotifierProvider<PcController, PcState>(PcController.new);

class PcController extends Notifier<PcState> {
  BloomDb get _db => ref.read(dbProvider);
  Timer? _timer;
  AppLifecycleListener? _life;

  /// The computer's event stream; `null` if not held (no answer, or the app
  /// hidden).
  StreamSubscription<PcEvent>? _live;
  StreamSubscription<SqliteUpdate>? _writes;
  Timer? _settle, _retry;
  bool _shown = true;

  /// A round was asked for while another ran: go again right after.
  bool _again = false;

  /// How far the computer took ours after the last round.
  ({int seq, int play})? _pushed;

  @override
  PcState build() {
    ref.onDispose(() {
      _timer?.cancel();
      _life?.dispose();
      _writes?.cancel();
      _settle?.cancel();
      _retry?.cancel();
      _live?.cancel();
    });
    return PcState(
      link: PcLink.fromJson(_db.get(_kLink)),
      lastSync: (_db.get(_kAt, 0) as num?)?.toInt() ?? 0,
    );
  }

  /// The schedule, from `main()`, for the process's whole life.
  void start() {
    _timer ??= Timer.periodic(_kEvery, (_) => sync());
    _life ??= AppLifecycleListener(
      onResume: () {
        _shown = true;
        sync();
      },
      // Leaving the app sends what's done at once: Android may kill a
      // background process, and the computer wouldn't see it until the next
      // launch. The event stream isn't held in background.
      onHide: () {
        _shown = false;
        _closeLive();
        sync();
      },
    );
    _writes ??= _db.updates.listen(_onWrite);
    unawaited(Future<void>.delayed(const Duration(seconds: 3), sync));
  }

  /// One round. Nothing with no link or when the computer already refused;
  /// during another round, one more right after.
  Future<void> sync({bool force = false}) async {
    final link = state.link;
    if (link == null) return;
    if (state.status == PcStatus.syncing) {
      _again = true;
      return;
    }
    if (state.status == PcStatus.repair && !force) return;
    _retry?.cancel();
    final dir = coversDirPath();
    if (dir == null) return;
    state = state.copyWith(status: PcStatus.syncing);
    final clearedBefore = _db.get('stats.cleared');
    try {
      final round = await syncWithPc(link, _db, dir);
      final now = BloomDb.now();
      _db.set(_kLink, round.link.toJson());
      _db.set(_kAt, now);
      state = state.copyWith(
        link: round.link,
        status: PcStatus.ok,
        lastSync: now,
      );
      _pushed = round.pushed;
      _reread(round.touched, '${_db.get('stats.cleared')}' != '$clearedBefore');
      _openLive(round.link);
      if (_again) {
        _again = false;
        unawaited(sync());
      }
      return;
    } on PcUnreachable {
      state = state.copyWith(status: PcStatus.offline);
    } on PcPrintMismatch {
      logWarn('sync', 'сертификат ПК не тот — нужно подключить заново');
      state = state.copyWith(status: PcStatus.repair);
    } on PcChanged {
      logWarn('sync', 'по адресу ответил другой ПК — нужно подключить заново');
      state = state.copyWith(status: PcStatus.repair);
    } on PcHttpError catch (e) {
      logWarn('sync', 'ПК ответил ${e.status} ${e.code}');
      state = state.copyWith(
        status: e.status == 401 ? PcStatus.repair : PcStatus.failed,
      );
    } catch (e, st) {
      logError('sync', 'круг с ПК сломался: $e', st);
      state = state.copyWith(status: PcStatus.failed);
    }
    // Didn't get there: what was asked to follow goes with the next scheduled
    // round.
    _again = false;
  }

  void _openLive(PcLink link) {
    if (_live != null || !_shown) return;
    final client = PcClient(
      link.addresses.first,
      link.port,
      print: link.print,
      token: link.token,
    );
    _live = client.events().listen(
      _onEvent,
      onError: (Object e) => _liveLost('$e'),
      onDone: () => _liveLost('closed'),
      cancelOnError: true,
    );
    ref.read(pcRemoteProvider.notifier).attach(client);
    state = state.copyWith(live: true);
  }

  void _closeLive() {
    _retry?.cancel();
    _live?.cancel();
    _live = null;
    ref.read(pcRemoteProvider.notifier).detach();
    if (state.live) state = state.copyWith(live: false);
  }

  /// The link dropped: the computer closed, the network went or the phone was
  /// disconnected there. While the app is on screen a round comes after
  /// [_kRetry]: it says what happened, and reopens the stream if the computer
  /// is there.
  void _liveLost(String why) {
    _live = null;
    ref.read(pcRemoteProvider.notifier).detach();
    state = state.copyWith(live: false);
    logInfo('sync', 'поток событий ПК оборвался: $why');
    if (!_shown || !state.paired) return;
    _retry?.cancel();
    _retry = Timer(_kRetry, sync);
  }

  void _onEvent(PcEvent e) {
    final link = state.link;
    if (e.name != 'sync') {
      ref.read(pcRemoteProvider.notifier).onEvent(e);
      return;
    }
    if (link == null) return;
    final got = SyncLog(_db).got(link.device);
    final seq = e.data['seq'], play = e.data['play'];
    if ((seq is num && seq > got.seq) || (play is num && play > got.play)) {
      sync();
    }
  }

  /// A database write: an own edit or play goes when writes settle. With no
  /// event stream the computer is likely unavailable, so I wait for the
  /// schedule rather than search on every edit.
  void _onWrite(SqliteUpdate u) {
    if (_live == null) return;
    if (u.tableName != 'changes' && u.tableName != 'plays') return;
    _settle?.cancel();
    _settle = Timer(_kEditSettle, () {
      final link = state.link, pushed = _pushed;
      if (link == null || pushed == null) return;
      // A round's writes (what came from the computer) land here too, but they
      // aren't mine.
      final own = SyncLog(_db).head(link.device, ownOnly: true);
      if (own.seq > pushed.seq || own.play > pushed.play) sync();
    });
  }

  /// Pairing by the QR's text from the computer's screen.
  Future<PairResult> pairQr(String text) async {
    final offer = PairOffer.parse(text);
    if (offer == null) return PairResult.notBloom;
    return _pair(
      () async => pairPc(
        addresses: offer.addresses,
        port: offer.port,
        print: offer.print,
        secret: offer.secret,
        name: await _name(),
        device: SyncLog(_db).device(),
      ),
    );
  }

  /// A computer with Connect phone open, for entering a code.
  Future<List<FoundPc>> findForCode() =>
      findPcs(wait: const Duration(seconds: 2));

  Future<PairResult> pairCode(FoundPc pc, String code) => _pair(
    () async => pairPc(
      addresses: [pc.address],
      port: pc.port,
      code: code,
      name: await _name(),
      device: SyncLog(_db).device(),
    ),
  );

  /// Forgets the computer. There the phone stays listed until disconnected.
  void unpair() {
    _closeLive();
    _pushed = null;
    _db.set(_kLink, null);
    _db.set(_kAt, null);
    state = const PcState();
    logInfo('sync', 'ПК забыт');
  }

  Future<PairResult> _pair(Future<PcLink?> Function() run) async {
    try {
      final link = await run();
      if (link == null) return PairResult.unreachable;
      _db.set(_kLink, link.toJson());
      state = PcState(link: link, lastSync: state.lastSync, live: state.live);
      logInfo('sync', 'сопряжён с ПК «${link.name}»');
      unawaited(sync());
      return PairResult.ok;
    } on PcHttpError catch (e) {
      return switch (e.code) {
        'wrong' => PairResult.wrong,
        'not_pairing' => PairResult.closed,
        'too_many' => PairResult.tooMany,
        _ => PairResult.failed,
      };
    } on PcPrintMismatch {
      return PairResult.notBloom;
    } catch (e) {
      logWarn('sync', 'сопряжение не вышло: $e');
      return PairResult.failed;
    }
  }

  static Future<String> _name() async => (await deviceName()) ?? 'Phone';

  /// What a round changed, to re-read in memory.
  void _reread(Set<String> touched, bool cleared) {
    bool any(List<String> kinds) => kinds.any(touched.contains);
    // The wave re-reads dislikes itself after the library.
    if (any(['list', 'item', 'follow', 'track', 'rekey', 'dislike']) ||
        cleared) {
      ref.read(libraryProvider.notifier).reload();
    }
    if (any(['plays', 'rekey', 'track']) || cleared) {
      ref.read(playLogProvider.notifier).reload();
    }
    if (any(['days']) || cleared) ref.read(daysProvider.notifier).reload();
    if (any(['kv'])) {
      ref.read(profileProvider.notifier).reload();
      ref.invalidate(profileSinceProvider);
    }
    if (cleared) {
      ref.invalidate(levelBankedProvider);
      ref.invalidate(unlockedAchievementsProvider);
      ref.read(forYouProvider.notifier).reset();
      ref.read(similarToProvider.notifier).reset();
    }
  }
}
