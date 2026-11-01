/// Listener's level. XP: 10 per counted play; 50 per day Bloom was opened or
/// something played, +10 for each day in a row before it (up to +50); 100, 250
/// and 500 for an achievement's bronze, silver and gold. From level L to L + 1
/// takes 100·L. XP isn't stored: it recounts from rows, so a stats clear can
/// bank what they gave (kv `level.banked`).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/db.dart';
import '../../core/store/days_store.dart';
import '../../core/store/play_log.dart';
import '../../core/store/play_stats.dart';
import '../../core/sync/sync_log.dart';
import '../home/for_you.dart';
import '../home/similar_to.dart';
import 'achievements.dart';
import 'stats.dart';

const int kXpPerPlay = 10;
const int kXpPerDay = 50;
const int _kXpPerRunDay = 10; // each day in a row before this…
const int _kRunCap = 5; // …but no more than this many
const List<int> kTierXp = [100, 250, 500];

const String _kBanked = 'level.banked';

@immutable
class LevelInfo {
  const LevelInfo({
    required this.level,
    required this.xp,
    required this.from,
    required this.to,
    required this.plays,
    required this.days,
    required this.ach,
    required this.banked,
  });

  final int level;
  final int xp;

  /// XP this level began at, and where the next begins.
  final int from;
  final int to;

  /// What plays, days, achievements and the banked at clearing gave.
  final int plays;
  final int days;
  final int ach;
  final int banked;
}

/// Level by rows: [plays] plays, days [days] (`YYYY-MM-DD`, when opened or
/// played), tiers taken [achievements], banked [banked].
LevelInfo computeLevel({
  required int plays,
  required Iterable<String> days,
  required List<AchProgress> achievements,
  required int banked,
}) {
  var dayXp = 0, run = 0;
  DateTime? prev;
  for (final d in sortedDays(days.toSet())) {
    run = prev != null && nextDay(prev) == d ? run + 1 : 0;
    prev = d;
    dayXp += kXpPerDay + _kXpPerRunDay * (run < _kRunCap ? run : _kRunCap);
  }
  var achXp = 0;
  for (final a in achievements) {
    for (var t = 0; t < a.tierReached; t++) {
      achXp += kTierXp[t];
    }
  }
  final playXp = kXpPerPlay * plays;
  final xp = playXp + dayXp + achXp + banked;

  var level = 1, from = 0;
  while (xp >= from + 100 * level) {
    from += 100 * level;
    level++;
  }
  return LevelInfo(
    level: level,
    xp: xp,
    from: from,
    to: from + 100 * level,
    plays: playXp,
    days: dayXp,
    ach: achXp,
    banked: banked,
  );
}

final levelProvider = Provider<LevelInfo>(
  (ref) => computeLevel(
    plays: ref.watch(playLogProvider).events.length,
    // A day counts if the app was opened or something played.
    days: [
      ...ref.watch(playStatsProvider).perDay.keys,
      ...ref.watch(daysProvider).visited,
    ],
    achievements: ref.watch(achievementsProvider),
    banked: ref.watch(levelBankedProvider),
  ),
);

/// Banked XP (kv `level.banked`), written only by [StatsClearController].
final levelBankedProvider = NotifierProvider<LevelBankedController, int>(
  LevelBankedController.new,
);

class LevelBankedController extends Notifier<int> {
  BloomDb get _db => ref.read(dbProvider);

  @override
  int build() => (_db.get(_kBanked, 0) as num?)?.toInt() ?? 0;

  void _bank(int xp) {
    _db.set(_kBanked, xp);
    state = xp;
  }
}

/// Clear stats, in the stats sheet.
final statsClearProvider = NotifierProvider<StatsClearController, void>(
  StatsClearController.new,
);

class StatsClearController extends Notifier<void> {
  @override
  void build() {}

  /// In one transaction: plays, days and achievement marks. [keepLevel] banks
  /// the XP they gave, so the level stays.
  void clear({required bool keepLevel}) {
    final banked = keepLevel ? ref.read(levelProvider).xp : 0;
    final db = ref.read(dbProvider);
    db.tx(() {
      ref.read(playLogProvider.notifier).clear();
      ref.read(daysProvider.notifier).clear();
      ref.read(unlockedAchievementsProvider.notifier).clear();
      ref.read(levelBankedProvider.notifier)._bank(banked);
      SyncLog(db).markCleared(banked);
    });
    // Home shelves are built on seeds from the erased top, so they rebuild at
    // once.
    ref.read(forYouProvider.notifier).reset();
    ref.read(similarToProvider.notifier).reset();
  }
}
