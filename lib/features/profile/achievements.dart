/// Profile achievements. The list is declarative: each has three thresholds
/// (bronze, silver, gold) and a function getting its number from computed
/// stats. Values AREN'T stored; only unlock dates go in database kv (`ach.at`,
/// keys `id:tier`), to show when earned and pop up once.
///
/// The first run seeds what's done silently (`ach.seeded`), or a listener with
/// history gets a pile of notifications at once.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/db.dart';
import '../../core/l10n/l10n.dart';
import '../../shared/ui/bloom_icon.dart';
import 'stats.dart';

enum AchTier { bronze, silver, gold }

const List<AchTier> kTierOrder = AchTier.values;

String tierLabel(AppLocalizations l, AchTier tier) => switch (tier) {
  AchTier.bronze => l.achTierBronze,
  AchTier.silver => l.achTierSilver,
  AchTier.gold => l.achTierGold,
};

Color tierColor(AchTier tier) => switch (tier) {
  AchTier.bronze => const Color(0xFFCD7F32),
  AchTier.silver => const Color(0xFFC8C8D2),
  AchTier.gold => const Color(0xFFFFD24A),
};

/// Metric unit; affects only the progress caption.
enum AchUnit { count, time }

const int _h = 3600;

class AchDef {
  const AchDef({
    required this.id,
    required this.icon,
    required this.name,
    required this.description,
    required this.unit,
    required this.tiers,
    required this.value,
  });

  final String id;
  final BloomGlyph icon;

  /// Name and caption resolve at paint time: the table builds once per process
  /// and must outlive a language change.
  final String Function(AppLocalizations l) name;
  final String Function(AppLocalizations l) description;
  final AchUnit unit;

  /// Three thresholds, ascending.
  final List<int> tiers;

  final int Function(ProfileStats stats) value;
}

/// The achievement list.
final List<AchDef> kAchievements = [
  AchDef(
    id: 'listener',
    icon: Bi.play,
    name: (l) => l.achListenerName,
    description: (l) => l.achListenerDesc,
    unit: AchUnit.count,
    tiers: const [100, 1000, 10000],
    value: (s) => s.totalPlays,
  ),
  AchDef(
    id: 'time',
    icon: Bi.clockCircle,
    name: (l) => l.achTimeName,
    description: (l) => l.achTimeDesc,
    unit: AchUnit.time,
    tiers: const [10 * _h, 100 * _h, 500 * _h],
    value: (s) => s.listenSec,
  ),
  AchDef(
    id: 'streak',
    icon: Bi.fire,
    name: (l) => l.achStreakName,
    description: (l) => l.achStreakDesc,
    unit: AchUnit.count,
    tiers: const [3, 7, 30],
    value: (s) => s.longestStreak,
  ),
  AchDef(
    id: 'marathon',
    icon: Bi.star,
    name: (l) => l.achMarathonName,
    description: (l) => l.achMarathonDesc,
    unit: AchUnit.count,
    tiers: const [20, 50, 100],
    value: (s) => s.recordDay,
  ),
  AchDef(
    id: 'veteran',
    icon: Bi.medalStar,
    name: (l) => l.achVeteranName,
    description: (l) => l.achVeteranDesc,
    unit: AchUnit.time,
    tiers: const [5 * _h, 50 * _h, 200 * _h],
    value: (s) => s.appSec,
  ),
  AchDef(
    id: 'devotee',
    icon: Bi.calendar,
    name: (l) => l.achDevoteeName,
    description: (l) => l.achDevoteeDesc,
    unit: AchUnit.count,
    tiers: const [7, 30, 100],
    value: (s) => s.activeDays,
  ),
];

/// A computed achievement, all a card needs.
class AchProgress {
  const AchProgress({
    required this.def,
    required this.value,
    required this.tierReached,
    required this.ratio,
  });

  final AchDef def;
  final int value;

  /// Thresholds passed, 0..3.
  final int tierReached;

  /// Share to the next threshold; 1 when fully taken.
  final double ratio;

  AchTier? get tier => tierReached > 0 ? kTierOrder[tierReached - 1] : null;

  bool get unlocked => tierReached > 0;
  bool get maxed => tierReached >= def.tiers.length;
  int? get nextTarget => maxed ? null : def.tiers[tierReached];
}

List<AchProgress> buildAchievements(ProfileStats stats) => [
  for (final def in kAchievements) _progress(def, stats),
];

AchProgress _progress(AchDef def, ProfileStats stats) {
  final value = def.value(stats);
  var reached = 0;
  for (final target in def.tiers) {
    if (value >= target) reached++;
  }
  final maxed = reached >= def.tiers.length;
  final prev = reached > 0 ? def.tiers[reached - 1] : 0;
  final next = maxed ? 0 : def.tiers[reached];
  return AchProgress(
    def: def,
    value: value,
    tierReached: reached,
    ratio: maxed ? 1 : ((value - prev) / (next - prev)).clamp(0.0, 1.0),
  );
}

final achievementsProvider = Provider<List<AchProgress>>(
  (ref) => buildAchievements(ref.watch(profileStatsProvider)),
);

/// Unlock key: achievement and threshold number.
String tierKey(String id, int tierIndex) => '$id:$tierIndex';

@immutable
class UnlockedAchievements {
  const UnlockedAchievements({this.at = const {}, this.seeded = false});

  /// `id:tier` to when earned.
  final Map<String, int> at;

  /// Whether the silent first run passed.
  final bool seeded;
}

final unlockedAchievementsProvider =
    NotifierProvider<AchievementsController, UnlockedAchievements>(
      AchievementsController.new,
    );

const String _kAt = 'ach.at';
const String _kSeeded = 'ach.seeded';

class AchievementsController extends Notifier<UnlockedAchievements> {
  BloomDb get _db => ref.read(dbProvider);

  @override
  UnlockedAchievements build() => UnlockedAchievements(
    at: {
      for (final e in _db.getMap(_kAt).entries)
        if (e.value is num) e.key: (e.value as num).toInt(),
    },
    seeded: _db.get(_kSeeded) == true,
  );

  void _save() {
    _db.tx(() {
      _db.set(_kAt, state.at);
      _db.set(_kSeeded, state.seeded);
    });
  }

  /// Reconciles what's stored with current progress. Returns NEW unlocks
  /// (achievement and tier taken); on the first run the list is empty, however
  /// much got seeded.
  List<({AchProgress ach, AchTier tier})> sync(List<AchProgress> list) {
    final next = {...state.at};
    final fresh = <({AchProgress ach, AchTier tier})>[];
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final a in list) {
      for (var i = 0; i < a.tierReached; i++) {
        final key = tierKey(a.def.id, i);
        if (next.containsKey(key)) continue;
        next[key] = now;
        fresh.add((ach: a, tier: kTierOrder[i]));
      }
    }
    if (fresh.isEmpty && state.seeded) return const [];

    final wasSeeded = state.seeded;
    state = UnlockedAchievements(at: next, seeded: true);
    _save();
    return wasSeeded ? fresh : const [];
  }

  /// Reset with the stats. The first run mark stays: tiers taken anew are news.
  void clear() {
    state = UnlockedAchievements(seeded: state.seeded);
    _save();
  }
}
