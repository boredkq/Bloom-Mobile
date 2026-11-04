/// The stats sheet: the top artists as a strip of circles, the top tracks,
/// "Overview" (the other numbers on one plate), and where the plays went (a
/// logo, the plays under it). At the foot: the month's review, copy a summary
/// as text, or clear the stats (asked first, with "reset the level too").
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/bloom_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/l10n/source_label.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/platform_logo.dart';
import '../../../shared/ui/pressable.dart';
import '../../../shared/ui/track_actions.dart';
import '../../detail/artists_sheet.dart';
import '../../player/player_controller.dart';
import '../../wrapped/ui/wrapped_sheet.dart';
import '../../wrapped/wrapped_store.dart';
import '../artist_avatars.dart';
import '../level.dart';
import '../stats.dart';

Future<void> showStatsSheet(BuildContext context) => showBloomSheetChild<void>(
  context: context,
  footer: const _Foot(),
  child: const _StatsBody(),
);

class _StatsBody extends ConsumerWidget {
  const _StatsBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(profileStatsProvider);
    final avatars = ref.watch(artistAvatarsProvider);

    // The avatars load in the background and keep for 30 days; each is asked
    // of the platform it was played on. Not from build: the store changes.
    final refs = [
      for (final a in s.topArtists) (name: a.name, source: a.source),
    ];
    if (refs.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          ref.read(artistAvatarsProvider.notifier).ensure(refs);
        }
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        _Section(
          title: context.l.statsTopArtists,
          // The strip runs edge to edge: circles go under the edges rather
          // than stop short.
          padded: false,
          child: s.topArtists.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: kSheetEdge),
                  child: _Empty(),
                )
              : _ArtistStrip(rows: s.topArtists, avatars: avatars),
        ),
        _Section(
          title: context.l.statsTopTracks,
          child: s.topTracks.isEmpty
              ? const _Empty()
              : Column(
                  children: [
                    for (final row in s.topTracks) _TopTrack(row: row),
                  ],
                ),
        ),
        _Section(
          title: context.l.statsOverview,
          child: _Overview(stats: s),
        ),
        _Section(
          title: context.l.statsSources,
          child: s.bySource.isEmpty
              ? const _Empty()
              : Row(
                  children: [
                    for (final src in s.bySource)
                      Expanded(child: _SourceItem(row: src)),
                  ],
                ),
        ),
      ],
    );
  }
}

/// A section: a big title, then its content right on the sheet.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    this.padded = true,
  });

  final String title;
  final Widget child;
  final bool padded;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(kSheetEdge, 0, kSheetEdge, 14),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: bloomText(
                size: 26,
                weight: 700,
                color: context.bloom.text,
                letterSpacing: -0.6,
              ),
            ),
          ),
          if (padded)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kSheetEdge),
              child: child,
            )
          else
            child,
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Text(
      context.l.statsNoDataYet,
      style: bloomText(size: 13, weight: 500, color: context.bloom.muted),
    ),
  );
}

/// The top artists: their avatar (the best track's cover until it comes),
/// name, how many times. A tap opens the artist on the platform they were
/// played on; only own files — nowhere to go.
class _ArtistStrip extends ConsumerStatefulWidget {
  const _ArtistStrip({required this.rows, required this.avatars});

  final List<ArtistPlays> rows;
  final Map<String, String> avatars;

  static const double size = 108;

  @override
  ConsumerState<_ArtistStrip> createState() => _ArtistStripState();
}

class _ArtistStripState extends ConsumerState<_ArtistStrip> {
  /// Whom the platform is being asked for: a spinner on their circle, and a
  /// second tap meanwhile doesn't go.
  String? _busy;

  Future<void> _open(ArtistPlays row) async {
    if (_busy != null) return;
    setState(() => _busy = row.name);

    await openPlayedArtist(context, ref, row);
    if (mounted) setState(() => _busy = null);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    const side = _ArtistStrip.size;
    return SizedBox(
      height: side + 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: kSheetEdge),
        itemCount: widget.rows.length,
        separatorBuilder: (_, _) => const SizedBox(width: 20),
        itemBuilder: (context, i) {
          final row = widget.rows[i];
          final local = row.source == MusicSource.local;
          return Pressable(
            scale: 0.97,
            onTap: local ? null : () => _open(row),
            child: SizedBox(
              width: side,
              child: Column(
                children: [
                  Cover(
                    url: playedArtistAvatar(row, widget.avatars),
                    size: side,
                    circle: true,
                    overlay: _busy == row.name ? const CoverSpinner() : null,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    row.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: bloomText(size: 14, weight: 700, color: t.text),
                  ),
                  Text(
                    context.l.playsCount(row.plays),
                    maxLines: 1,
                    style: bloomText(size: 12, weight: 500, color: t.text2),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A top track: a tiny cover, "artist — title", the plays. A tap plays it, a
/// long press opens its menu.
class _TopTrack extends ConsumerWidget {
  const _TopTrack({required this.row});

  final TrackPlays row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final track = row.track;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => ref.read(playbackProvider.notifier).play(track),
      onLongPress: () => showTrackActions(context, ref, track),
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            Cover(url: track.cover, size: 20, radius: 5),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    if (track.artist.isNotEmpty)
                      TextSpan(
                        text: '${track.artist} — ',
                        style: bloomText(size: 13, weight: 500, color: t.text2),
                      ),
                    TextSpan(text: track.name),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: bloomText(size: 13, weight: 700, color: t.text),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${row.plays}',
              style: bloomText(size: 13, weight: 500, color: t.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Overview": the rest of the numbers on one plate, rows of three and two
/// with a thin line between.
class _Overview extends StatelessWidget {
  const _Overview({required this.stats});

  final ProfileStats stats;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final s = stats;
    final l = context.l;
    final rows = <List<({String value, String label})>>[
      [
        (value: '${s.totalPlays}', label: l.statsPlays),
        (value: '${s.libraryTracks}', label: l.statsTracks),
        (value: fmtDurLong(context, s.listenSec), label: l.statsTime),
      ],
      [
        (value: '${s.uniqueTracks}', label: l.statsUnique),
        (value: fmtClock(s.avgSec), label: l.statsAvgLength),
        (value: '${s.recordDay}', label: l.statsRecordDay),
      ],
      [
        (value: fmtDurLong(context, s.appSec), label: l.statsAppTime),
        (value: '${s.uniqueArtists}', label: l.statsArtists),
      ],
      [
        (
          value: (s.listenSec / 3600 / s.daySpan).toStringAsFixed(1),
          label: l.statsHoursDay,
        ),
        (
          value: (s.totalPlays / s.daySpan).toStringAsFixed(1),
          label: l.statsTracksDay,
        ),
      ],
      [(value: s.favArtist ?? '—', label: l.statsFavArtist)],
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: sheetPanelColor(context),
        borderRadius: BorderRadius.circular(context.bloom.radius),
        border: Border.all(color: sheetLineColor(context)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(height: 21, thickness: 1, color: sheetLineColor(context)),
            Row(
              children: [
                for (final cell in rows[i])
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          cell.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: bloomText(
                            size: 20,
                            weight: 700,
                            color: t.text,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          cell.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: bloomText(
                            size: 11,
                            weight: 500,
                            color: t.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A platform: its logo (a folder for own files), how many plays went there.
class _SourceItem extends StatelessWidget {
  const _SourceItem({required this.row});

  final SourcePlays row;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final local = row.source == MusicSource.local;
    return Column(
      children: [
        SizedBox.square(
          dimension: 20,
          child: Center(
            child: PlatformLogo(
              row.source,
              size: 20,
              color: local ? t.text2 : null,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${row.plays}',
          style: bloomText(
            size: 20,
            weight: 700,
            color: t.text,
            letterSpacing: -0.4,
          ),
        ),
      ],
    );
  }
}

/// The foot, pinned under the sections: copy / clear; clearing asks first,
/// right here. Above them the month's review, which can always be watched
/// again from here.
class _Foot extends ConsumerStatefulWidget {
  const _Foot();

  @override
  ConsumerState<_Foot> createState() => _FootState();
}

class _FootState extends ConsumerState<_Foot> {
  bool _asking = false;
  bool _resetLevel = false;

  void _copy(ProfileStats s) {
    final l = context.l;
    final lines = <String>[
      l.statsShareTitle,
      '',
      l.statsShareTracks(s.libraryTracks),
      l.statsShareUnique(s.uniqueTracks),
      l.statsSharePlays(s.totalPlays),
      l.statsShareTime(fmtDurLong(context, s.listenSec)),
      l.statsShareAvgLength(fmtClock(s.avgSec)),
      l.statsShareAppTime(fmtDurLong(context, s.appSec)),
      if (s.favArtist != null) l.statsShareFavArtist(s.favArtist!),
      if (s.recordDay > 0) l.statsShareRecordDay(s.recordDay),
      '',
      l.statsShareAvgPerDay,
      '  ${(s.listenSec / 3600 / s.daySpan).toStringAsFixed(1)} ${l.statsHoursDay} · '
          '${(s.totalPlays / s.daySpan).toStringAsFixed(1)} ${l.statsTracksDay} · '
          '${s.uniqueArtists} ${l.statsArtists}',
      if (s.bySource.isNotEmpty) ...[
        '',
        l.statsShareSources,
        for (final (i, src) in s.bySource.take(5).indexed)
          '  ${i + 1}. ${src.source.label10n(l)} — ${src.plays} '
              '(${s.totalPlays > 0 ? (src.plays / s.totalPlays * 100).round() : 0}%)',
      ],
      if (s.topTracks.isNotEmpty) ...[
        '',
        l.statsShareTopTracks,
        for (final (i, row) in s.topTracks.take(5).indexed)
          '  ${i + 1}. ${row.track.name}'
              '${row.track.artist.isEmpty ? '' : ' — ${row.track.artist}'} '
              '(${l.playsCount(row.plays)})',
      ],
      if (s.topArtists.isNotEmpty) ...[
        '',
        l.statsShareTopArtists,
        for (final (i, a) in s.topArtists.take(5).indexed)
          '  ${i + 1}. ${a.name} (${a.plays})',
      ],
      '',
      '— Bloom',
    ];
    Clipboard.setData(ClipboardData(text: lines.join('\n')));
    toaster.show(l.statsCopied, kind: ToastKind.success);
  }

  void _clear() {
    if (!_asking) {
      setState(() {
        _resetLevel = false;
        _asking = true;
      });
      return;
    }
    setState(() => _asking = false);
    ref.read(statsClearProvider.notifier).clear(keepLevel: !_resetLevel);
    toaster.show(context.l.statsCleared, kind: ToastKind.success);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final month = ref.watch(wrappedEntriesProvider).month;

    return Padding(
      padding: const EdgeInsets.fromLTRB(kSheetEdge, 12, kSheetEdge, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_asking) ...[
            Text(
              context.l.statsClearTitle,
              style: bloomText(size: 14, weight: 700, color: t.text),
            ),
            const SizedBox(height: 4),
            Text(
              context.l.statsClearSub,
              style: bloomText(size: 12, weight: 500, color: t.text2),
            ),
            SheetSwitchRow(
              label: context.l.statsClearLevel,
              value: _resetLevel,
              onChanged: (v) => setState(() => _resetLevel = v),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ] else if (month != null) ...[
            SheetButton(
              label: context.l.wrMonth,
              icon: Bi.medalRibbonsStar,
              tone: ButtonTone.accent,
              onTap: () {
                // The review is its own sheet: this one goes first.
                Navigator.of(context).pop();
                showWrappedSheet(context, month);
              },
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: SheetButton(
                  label: _asking ? context.l.commonCancel : context.l.statsCopy,
                  icon: _asking ? null : Bi.copy,
                  onTap: _asking
                      ? () => setState(() => _asking = false)
                      : () => _copy(ref.read(profileStatsProvider)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SheetButton(
                  label: context.l.statsClear,
                  icon: Bi.trashBinTrash,
                  tone: ButtonTone.danger,
                  onTap: _clear,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
