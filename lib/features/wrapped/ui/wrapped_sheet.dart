/// The month's or the year's review: a story on a sheet. Bars on top (each one
/// jumps to its slide), a slide moves on by itself in 6 s, holding pauses it,
/// the left and right of the sheet go back and on, and the button under it. The
/// colour is one round blob under the slide: the top track's cover tone (a
/// platform's own on the platforms slide), moving from slide to slide. Each way
/// in knows its period, so there's no choosing one. The last slide is a poster
/// to share.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/bloom_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/l10n/source_label.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/platform_logo.dart';
import '../../../shared/ui/pressable.dart';
import '../../detail/artists_sheet.dart';
import '../../player/play_source.dart';
import '../../player/player_controller.dart';
import '../../profile/artist_avatars.dart';
import '../../profile/tally.dart';
import '../../settings/cover_accent.dart';
import '../periods.dart';
import '../wrapped_data.dart';
import '../wrapped_format.dart';
import '../wrapped_store.dart';
import 'wrapped_poster.dart';

const int _kSlideMs = 6000;

/// Past this a press is a hold; the press itself arrives some 100 ms late.
const Duration _kHold = Duration(milliseconds: 120);

/// The body is at least this much of the screen, so a short slide doesn't
/// fold the sheet and the next one throw it open.
const double _kBodyFill = 0.5;
const double _kBodyMin = 300;

/// Big things go by the sheet's width: this is the width their sizes are for.
const double _kDesignWidth = 444;

/// From this share of the plays at night the listener is a night one.
const double _kNightShare = 0.35;

enum _SlideId {
  intro,
  time,
  counts,
  tracks,
  artists,
  sources,
  discover,
  habits,
  share,
}

/// Where the blob stands per slide: left and top in shares of the sheet, the
/// size in shares of its width.
const Map<_SlideId, (double, double, double)> _kBlobAt = {
  _SlideId.intro: (-0.12, 0, 0.69),
  _SlideId.time: (-0.04, 0.10, 0.69),
  _SlideId.counts: (0.16, 0.04, 0.69),
  _SlideId.tracks: (-0.08, 0.18, 0.65),
  _SlideId.artists: (0.10, 0.04, 0.69),
  _SlideId.sources: (0.18, 0.12, 0.73),
  _SlideId.discover: (-0.16, 0.08, 0.69),
  _SlideId.habits: (0.12, 0, 0.69),
  _SlideId.share: (0.04, 0.06, 0.69),
};

/// How much a big thing grows or shrinks on this screen.
double _big(BuildContext context) =>
    (MediaQuery.sizeOf(context).width - 2 * kSheetEdge) / _kDesignWidth;

Future<void> showWrappedSheet(BuildContext context, WrappedData data) =>
    showBloomModal<void>(
      context: context,
      builder: (_) => _WrappedSheet(data: data),
    );

String periodTitle(AppLocalizations l, PeriodKind kind) => switch (kind) {
  PeriodKind.month => l.wrMonth,
  PeriodKind.year => l.wrYear,
};

class _WrappedSheet extends ConsumerStatefulWidget {
  const _WrappedSheet({required this.data});

  final WrappedData data;

  @override
  ConsumerState<_WrappedSheet> createState() => _WrappedSheetState();
}

class _WrappedSheetState extends ConsumerState<_WrappedSheet>
    with SingleTickerProviderStateMixin {
  int _idx = 0;
  Color? _tone;
  bool _held = false;
  Timer? _holdTimer;

  /// Whom the platform is being asked for: a spinner on their circle, and a
  /// second tap meanwhile doesn't go.
  ArtistPlays? _opening;

  late final AnimationController _clock =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: _kSlideMs),
      )..addStatusListener((s) {
        if (s == AnimationStatus.completed) _go(1);
      });

  WrappedData get _d => widget.data;

  late final List<_SlideId> _slides = [
    _SlideId.intro,
    _SlideId.time,
    _SlideId.counts,
    if (_d.topTracks.isNotEmpty) _SlideId.tracks,
    if (_d.topArtists.isNotEmpty) _SlideId.artists,
    if (_d.sources.isNotEmpty) _SlideId.sources,
    if (_d.newArtists.isNotEmpty) _SlideId.discover,
    if (_d.activeDays > 0) _SlideId.habits,
    _SlideId.share,
  ];

  _SlideId get _cur => _slides[_idx];

  /// The poster waits for its button, it doesn't run out.
  bool get _timed => _cur != _SlideId.share;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(wrappedMarksProvider.notifier).markSeen(_d.range);
      ref.read(artistAvatarsProvider.notifier).ensure([
        for (final a in [..._d.topArtists, ..._d.newArtists])
          (name: a.name, source: a.source),
      ]);
    });
    _clock.forward();
    _loadTone();
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _clock.dispose();
    super.dispose();
  }

  Future<void> _loadTone() async {
    final hsl = await extractCoverHsl(_d.topTracks.firstOrNull?.track.cover);
    if (!mounted || hsl == null) return;
    // Its own hue, but quieter: the edge is sharp, so a bright one would shout
    // louder than the numbers.
    setState(() {
      _tone = HSLColor.fromAHSL(
        1,
        hsl.h,
        hsl.s.clamp(0.4, 0.78),
        0.4,
      ).toColor();
    });
  }

  void _go(int delta) {
    final next = _idx + delta;
    if (next < 0) return;
    if (next >= _slides.length) {
      Navigator.of(context).maybePop();
      return;
    }
    _jump(next);
  }

  void _jump(int index) {
    setState(() => _idx = index);
    _clock
      ..stop()
      ..value = 0;
    if (_timed) _clock.forward();
  }

  void _pressed(TapDownDetails _) {
    _holdTimer?.cancel();
    _holdTimer = Timer(_kHold, () {
      _held = true;
      _clock.stop();
    });
  }

  /// True when it was a hold.
  bool _letGo() {
    _holdTimer?.cancel();
    if (!_held) return false;
    _held = false;
    if (_timed) _clock.forward();
    return true;
  }

  void _released(TapUpDetails e) {
    if (_letGo()) return;
    final width = MediaQuery.sizeOf(context).width;
    final x = e.localPosition.dx;
    // The poster's button and the picture itself stay out of the way.
    final poster = _cur == _SlideId.share;
    if (x < width * (poster ? 0.1 : 0.32)) {
      _go(-1);
    } else if (x > width * (poster ? 0.9 : 0.6)) {
      _go(1);
    }
  }

  /// The top of the period from this track on, as a tap on a row in a list.
  void _play(int index) {
    ref
        .read(playbackProvider.notifier)
        .playQueue(
          [for (final row in _d.topTracks) row.track],
          index,
          source: PlainSource(
            id: 'wrapped:${_d.range.kind.id}',
            label: periodTitle(context.l, _d.range.kind),
          ),
        );
    Navigator.of(context).maybePop();
  }

  /// The slide waits while the artist is being picked or looked for; going to
  /// a page folds this sheet by itself.
  Future<void> _whileOpening(Future<void> Function() open) async {
    _clock.stop();
    await open();
    if (mounted && _timed) _clock.forward();
  }

  void _openTrackArtist(Track track) =>
      _whileOpening(() => openTrackArtist(context, ref, track));

  Future<void> _openArtist(ArtistPlays a) async {
    // Only own files: nowhere to go.
    if (a.source == MusicSource.local || _opening != null) return;
    setState(() => _opening = a);
    await _whileOpening(() => openPlayedArtist(context, ref, a));
    if (mounted) setState(() => _opening = null);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final l = context.l;
    final media = MediaQuery.of(context);
    final cur = _cur;
    final last = _idx == _slides.length - 1;
    final color =
        (cur == _SlideId.sources
            ? platformColor[_d.sources.first.source]
            : null) ??
        _tone ??
        t.accent;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(t.radius * 1.7),
        ),
        child: Stack(
          children: [
            const Positioned.fill(
              child: SheetSurface(child: SizedBox.expand()),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: _Blob(
                  at: _kBlobAt[cur]!,
                  color: color.withValues(
                    alpha: cur == _SlideId.share ? 0.22 : 0.3,
                  ),
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SheetHandle(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      kSheetEdge,
                      6,
                      kSheetEdge,
                      16,
                    ),
                    child: _Bars(
                      count: _slides.length,
                      index: _idx,
                      timed: _timed,
                      clock: _clock,
                      onJump: _jump,
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: _pressed,
                        onTapUp: _released,
                        onTapCancel: _letGo,
                        child: AnimatedSize(
                          duration: const Duration(milliseconds: 340),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: math.max(
                                _kBodyMin,
                                media.size.height * _kBodyFill,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: kSheetEdge,
                              ),
                              child: KeyedSubtree(
                                key: ValueKey(_idx),
                                child: _slide(cur),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      kSheetEdge,
                      16,
                      kSheetEdge,
                      14,
                    ),
                    child: BloomButton(
                      label: last ? l.wrClose : l.wrNext,
                      tone: ButtonTone.ink,
                      height: 46,
                      onTap: last
                          ? () => Navigator.of(context).maybePop()
                          : () => _go(1),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slide(_SlideId id) => switch (id) {
    _SlideId.intro => _IntroSlide(data: _d),
    _SlideId.time => _TimeSlide(data: _d),
    _SlideId.counts => _CountsSlide(data: _d),
    _SlideId.tracks => _TracksSlide(
      data: _d,
      onPlay: _play,
      onArtist: _openTrackArtist,
    ),
    _SlideId.artists => _ArtistsSlide(
      data: _d,
      opening: _opening,
      onArtist: _openArtist,
    ),
    _SlideId.sources => _SourcesSlide(data: _d),
    _SlideId.discover => _DiscoverSlide(
      data: _d,
      opening: _opening,
      onArtist: _openArtist,
    ),
    _SlideId.habits => _HabitsSlide(data: _d),
    _SlideId.share => _ShareSlide(data: _d),
  };
}

/// The colour under the slide, cut by the sheet's corners.
class _Blob extends StatelessWidget {
  const _Blob({required this.at, required this.color});

  final (double, double, double) at;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, box) {
        final size = box.maxWidth * at.$3;
        return Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 550),
              curve: Curves.easeOutCubic,
              left: box.maxWidth * at.$1,
              top: box.maxHeight * at.$2,
              width: size,
              height: size,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                decoration: BoxDecoration(shape: BoxShape.circle, color: color),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// How far along; each bar is a way to its slide.
class _Bars extends StatelessWidget {
  const _Bars({
    required this.count,
    required this.index,
    required this.timed,
    required this.clock,
    required this.onJump,
  });

  final int count;
  final int index;
  final bool timed;
  final Animation<double> clock;
  final void Function(int) onJump;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Row(
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onJump(i),
              // The bar is thin: the place to tap is taller.
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: SizedBox(
                    height: 4,
                    child: ColoredBox(
                      color: t.text.withValues(alpha: 0.18),
                      child: i == index && timed
                          ? AnimatedBuilder(
                              animation: clock,
                              builder: (_, _) => _fill(t, clock.value),
                            )
                          : _fill(t, i <= index ? 1 : 0),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _fill(BloomTokens t, double value) => FractionallySizedBox(
    alignment: Alignment.centerLeft,
    widthFactor: value,
    child: ColoredBox(color: t.text),
  );
}

// ── Slides ──

class _IntroSlide extends StatelessWidget {
  const _IntroSlide({required this.data});

  final WrappedData data;

  /// A line for small reviews.
  String? _joke(AppLocalizations l) {
    if (data.uniqueTracks == 1) return l.wrJokeOneTrack;
    if (data.plays < 5) return l.wrJokeTiny;
    if (data.plays < 25) return l.wrJokeSmall;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final l = context.l;
    final locale = Localizations.localeOf(context).languageCode;
    final joke = _joke(l);
    return _Middle(
      children: [
        _Rise(child: _Kicker(periodDatesLabel(data.range, locale))),
        const SizedBox(height: 9),
        _Rise(
          delay: 60,
          child: _H1(switch (data.range.kind) {
            PeriodKind.month => l.wrIntroMonth,
            PeriodKind.year => l.wrIntroYear,
          }),
        ),
        const SizedBox(height: 9),
        _Rise(delay: 120, child: _Sub(l.wrIntroSub)),
        if (joke != null) ...[
          const SizedBox(height: 9),
          _Rise(
            delay: 200,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: BoxDecoration(
                color: t.text.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                joke,
                style: bloomText(
                  size: 13,
                  weight: 400,
                  color: t.text.withValues(alpha: 0.7),
                  height: 1.3,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _TimeSlide extends StatelessWidget {
  const _TimeSlide({required this.data});

  final WrappedData data;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final locale = Localizations.localeOf(context).languageCode;
    final parts = splitListenTime(l, data.seconds);
    return _Middle(
      children: [
        _Rise(child: _H2(l.wrTimeKicker)),
        const SizedBox(height: 18),
        if (parts.isEmpty)
          _Rise(delay: 140, child: _H1(l.wrTimeLessThanMin))
        else
          for (final (i, part) in parts.indexed)
            _Rise(
              delay: 140 + i * 90,
              child: _Num(
                n: fmtCount(locale, part.n),
                word: part.word,
                size: 80 * _big(context),
              ),
            ),
        const SizedBox(height: 12),
        _Rise(delay: 320, child: _Sub(l.wrTimeSub(data.plays))),
      ],
    );
  }
}

class _CountsSlide extends StatelessWidget {
  const _CountsSlide({required this.data});

  final WrappedData data;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final locale = Localizations.localeOf(context).languageCode;
    final rows = <(int, String)>[
      (data.plays, l.wrPlaysWord(data.plays)),
      (data.uniqueTracks, l.wrTracksWord(data.uniqueTracks)),
      (data.uniqueArtists, l.wrArtistsWord(data.uniqueArtists)),
    ];
    return _Middle(
      children: [
        _Rise(child: _H2(l.wrCountsTitle)),
        const SizedBox(height: 18),
        for (final (i, row) in rows.indexed)
          _Rise(
            delay: 140 + i * 90,
            child: _Num(
              n: fmtCount(locale, row.$1),
              word: row.$2,
              size: 52 * _big(context),
            ),
          ),
        if (data.newTracksCount > 0) ...[
          const SizedBox(height: 12),
          _Rise(
            delay: 420,
            child: _Sub(l.wrCountsNewTracks(data.newTracksCount)),
          ),
        ],
      ],
    );
  }
}

class _TracksSlide extends StatelessWidget {
  const _TracksSlide({
    required this.data,
    required this.onPlay,
    required this.onArtist,
  });

  final WrappedData data;
  final void Function(int) onPlay;
  final void Function(Track) onArtist;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final l = context.l;
    final locale = Localizations.localeOf(context).languageCode;
    final big = _big(context);
    final first = data.topTracks.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // No. 1: a big cover tilted like a photo dropped on the sheet, the
        // plays beside it.
        _Rise(
          delay: 90,
          child: Pressable(
            onTap: () => onPlay(0),
            scale: 0.97,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 8),
                  child: Transform.rotate(
                    angle: -4 * math.pi / 180,
                    child: Cover(
                      url: first.track.cover,
                      size: 188 * big,
                      radius: 13,
                    ),
                  ),
                ),
                SizedBox(width: 18 * big),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 14),
                      _Num(
                        n: fmtCount(locale, first.plays),
                        word: l.wrTimesWord(first.plays),
                        size: 66 * big,
                        gap: 9,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        first.track.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: bloomText(
                          size: 20,
                          weight: 700,
                          color: t.text,
                          height: 1.16,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 3),
                      _ArtistName(
                        track: first.track,
                        size: 13,
                        onTap: onArtist,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // The rest: no place number, no plate, the plays as a bare number.
        for (final (i, row) in data.topTracks.skip(1).indexed)
          _Rise(
            delay: 200 + i * 70,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onPlay(i + 1),
              child: SizedBox(
                height: 62,
                child: Row(
                  children: [
                    Cover(url: row.track.cover, size: 46, radius: 10),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.track.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: bloomText(
                              size: 14,
                              weight: 700,
                              color: t.text,
                            ),
                          ),
                          const SizedBox(height: 1),
                          _ArtistName(
                            track: row.track,
                            size: 12,
                            onTap: onArtist,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        fmtCount(locale, row.plays),
                        style:
                            bloomText(
                              size: 13,
                              weight: 700,
                              color: t.text.withValues(alpha: 0.5),
                            ).copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The track's artist line: a tap goes to them, where there's anywhere to go.
class _ArtistName extends StatelessWidget {
  const _ArtistName({
    required this.track,
    required this.size,
    required this.onTap,
  });

  final Track track;
  final double size;
  final void Function(Track) onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: canOpenTrackArtist(track) ? () => onTap(track) : null,
    child: Text(
      track.artist,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: bloomText(
        size: size,
        weight: 400,
        color: context.bloom.text.withValues(alpha: 0.5),
      ),
    ),
  );
}

class _ArtistsSlide extends StatelessWidget {
  const _ArtistsSlide({
    required this.data,
    required this.opening,
    required this.onArtist,
  });

  final WrappedData data;
  final ArtistPlays? opening;
  final void Function(ArtistPlays) onArtist;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final l = context.l;
    final big = _big(context);
    final first = data.topArtists.first;
    return _Middle(
      children: [
        // No. 1 in the middle: the biggest hero of them all.
        _Rise(
          delay: 80,
          child: Center(
            child: Pressable(
              onTap: () => onArtist(first),
              scale: 0.97,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ArtistPic(
                    artist: first,
                    size: 134 * big,
                    busy: identical(opening, first),
                  ),
                  const SizedBox(height: 13),
                  Text(
                    first.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: bloomText(
                      size: math.max(27, 34 * big),
                      weight: 700,
                      color: t.text,
                      height: 1.08,
                      letterSpacing: -1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l.wrTimesN(first.plays),
                    style: bloomText(
                      size: 13,
                      weight: 400,
                      color: t.text.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (data.topArtists.length > 1) ...[
          const SizedBox(height: 12),
          // The places after it on one plate, with their numbers.
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: t.text.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                for (final (i, a) in data.topArtists.skip(1).indexed)
                  _Rise(
                    delay: 200 + i * 70,
                    child: _ArtistRow(
                      artist: a,
                      place: i + 2,
                      busy: identical(opening, a),
                      onTap: () => onArtist(a),
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        _Rise(
          delay: 460,
          child: Center(
            child: Text(
              l.wrArtistsTotalN(data.uniqueArtists),
              style: bloomText(
                size: 12.5,
                weight: 400,
                color: t.text.withValues(alpha: 0.4),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ArtistRow extends StatelessWidget {
  const _ArtistRow({
    required this.artist,
    required this.place,
    required this.busy,
    required this.onTap,
  });

  final ArtistPlays artist;
  final int place;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Pressable(
      onTap: onTap,
      scale: 0.98,
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: Text(
                  place.toString().padLeft(2, '0'),
                  style:
                      bloomText(
                        size: 11.5,
                        weight: 700,
                        color: t.text.withValues(alpha: 0.32),
                      ).copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                ),
              ),
              const SizedBox(width: 11),
              _ArtistPic(artist: artist, size: 38, busy: busy),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  artist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: bloomText(size: 14, weight: 700, color: t.text),
                ),
              ),
              const SizedBox(width: 11),
              Text(
                context.l.wrTimesN(artist.plays),
                style: bloomText(
                  size: 12,
                  weight: 400,
                  color: t.text.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An artist's round avatar (the best track's cover until it comes), or the
/// person icon.
class _ArtistPic extends ConsumerWidget {
  const _ArtistPic({
    required this.artist,
    required this.size,
    this.busy = false,
  });

  final ArtistPlays artist;
  final double size;
  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final url = playedArtistAvatar(artist, ref.watch(artistAvatarsProvider));
    if (url != null || busy) {
      return Cover(
        url: url,
        size: size,
        circle: true,
        overlay: busy ? const CoverSpinner() : null,
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: t.text.withValues(alpha: 0.08),
      ),
      alignment: Alignment.center,
      child: BloomIcon(
        Bi.user,
        size: size * 0.42,
        color: t.text.withValues(alpha: 0.35),
      ),
    );
  }
}

class _SourcesSlide extends StatelessWidget {
  const _SourcesSlide({required this.data});

  final WrappedData data;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final l = context.l;
    final locale = Localizations.localeOf(context).languageCode;
    final big = _big(context);
    final lead = data.sources.first;
    return _Middle(
      children: [
        _Rise(child: Center(child: _Kicker(l.wrSourcesKicker))),
        const SizedBox(height: 9),
        // The main one: its logo big, the plays that went there.
        _Rise(
          delay: 90,
          child: Column(
            children: [
              _SourceLogo(source: lead.source, size: 52 * big),
              const SizedBox(height: 14),
              _Num(
                n: fmtCount(locale, lead.plays),
                word: l.wrPlaysWord(lead.plays),
                size: 60 * big,
              ),
              const SizedBox(height: 4),
              Text(
                lead.source.label10n(l),
                style: bloomText(
                  size: 13,
                  weight: 400,
                  color: t.text.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
        // The others: a line each, with its share and a bar against the main one.
        for (final (i, row) in data.sources.skip(1).indexed) ...[
          SizedBox(height: i == 0 ? 16 : 11),
          _Rise(
            delay: 240 + i * 80,
            child: _SourceRow(
              row: row,
              share: (row.plays / data.plays * 100).round(),
              fill: row.plays / lead.plays,
            ),
          ),
        ],
      ],
    );
  }
}

class _SourceLogo extends StatelessWidget {
  const _SourceLogo({required this.source, required this.size});

  final MusicSource source;
  final double size;

  @override
  Widget build(BuildContext context) => source == MusicSource.local
      ? BloomIcon(Bi.folder, size: size, color: context.bloom.text)
      : PlatformLogo(source, size: size);
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.row,
    required this.share,
    required this.fill,
  });

  final SourcePlays row;
  final int share;
  final double fill;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _SourceLogo(source: row.source, size: 14),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                row.source.label10n(context.l),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: bloomText(
                  size: 13,
                  weight: 700,
                  color: t.text.withValues(alpha: 0.85),
                ),
              ),
            ),
            Text(
              '$share%',
              style: bloomText(size: 12.5, weight: 700, color: t.text),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 5,
            child: ColoredBox(
              color: t.text.withValues(alpha: 0.12),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: fill),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (_, value, _) => FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: value,
                  child: ColoredBox(
                    color: platformColor[row.source] ?? t.accent,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DiscoverSlide extends StatelessWidget {
  const _DiscoverSlide({
    required this.data,
    required this.opening,
    required this.onArtist,
  });

  final WrappedData data;
  final ArtistPlays? opening;
  final void Function(ArtistPlays) onArtist;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final l = context.l;
    return _Middle(
      children: [
        _Rise(child: _Kicker(l.wrDiscoverKicker)),
        const SizedBox(height: 9),
        _Rise(delay: 70, child: _H1(l.wrDiscoverTitle(data.newArtistsCount))),
        const SizedBox(height: 18),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final (i, a) in data.newArtists.indexed)
              _Rise(
                delay: 160 + i * 80,
                child: Pressable(
                  onTap: () => onArtist(a),
                  scale: 0.96,
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.only(left: 6, right: 13),
                    decoration: BoxDecoration(
                      color: t.text.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ArtistPic(
                          artist: a,
                          size: 24,
                          busy: identical(opening, a),
                        ),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            a.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: bloomText(
                              size: 13,
                              weight: 700,
                              color: t.text,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _HabitsSlide extends StatelessWidget {
  const _HabitsSlide({required this.data});

  final WrappedData data;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final l = context.l;
    final locale = Localizations.localeOf(context).languageCode;
    final most = data.hours.fold(1, math.max);
    final record = data.recordDay;
    final facts = [
      _Fact(
        label: l.wrHabitsPeak,
        value: fmtHourRange(l, data.peakHour),
        delay: 250,
      ),
      if (record != null)
        _Fact(
          label: l.wrHabitsRecord,
          value: l.wrHabitsRecordValue(
            l.wrTracksN(record.plays),
            DateFormat('d MMMM', locale).format(record.date),
          ),
          delay: 300,
        ),
      _Fact(label: l.wrHabitsStreak, value: l.wrDaysN(data.streak), delay: 350),
      _Fact(
        label: l.wrHabitsActive,
        value: l.wrDaysN(data.activeDays),
        delay: 400,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Rise(child: _Kicker(l.wrHabitsKicker)),
        const SizedBox(height: 9),
        _Rise(
          delay: 70,
          child: _H2(
            data.nightShare >= _kNightShare ? l.wrHabitsNight : l.wrHabitsDay,
          ),
        ),
        const SizedBox(height: 16),
        // Plays by the hour of the day; the busiest one in full colour.
        _Rise(
          delay: 150,
          child: Column(
            children: [
              SizedBox(
                height: 70,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var h = 0; h < 24; h++) ...[
                      if (h > 0) const SizedBox(width: 2),
                      Expanded(
                        child: FractionallySizedBox(
                          heightFactor: (data.hours[h] / most).clamp(0.03, 1.0),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: h == data.peakHour
                                  ? t.text
                                  : t.text.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 5),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final hour in const ['00', '06', '12', '18', '23'])
                    Text(
                      hour,
                      style: bloomText(
                        size: 10.5,
                        weight: 400,
                        color: t.text.withValues(alpha: 0.35),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < facts.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 8),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: facts[i]),
                const SizedBox(width: 8),
                Expanded(
                  child: i + 1 < facts.length
                      ? facts[i + 1]
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// A fact of the habits: what it is small and in capitals, the value under it.
class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, required this.delay});

  final String label;
  final String value;
  final int delay;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return _Rise(
      delay: delay,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: t.text.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: bloomText(
                size: 10.5,
                weight: 400,
                color: t.text.withValues(alpha: 0.5),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: bloomText(size: 14, weight: 700, color: t.text),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareSlide extends StatelessWidget {
  const _ShareSlide({required this.data});

  final WrappedData data;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width - 2 * kSheetEdge;
    return _Middle(
      children: [
        _Rise(child: Center(child: _Kicker(context.l.wrShareKicker))),
        const SizedBox(height: 16),
        _Rise(
          delay: 100,
          child: Center(
            child: WrappedPosterCard(
              data: data,
              width: math.min(width * 0.76, 320),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Pieces ──

/// A slide that stands in the middle of the body's height.
class _Middle extends StatelessWidget {
  const _Middle({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: children,
  );
}

class _Kicker extends StatelessWidget {
  const _Kicker(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: bloomText(
      size: 11.5,
      weight: 700,
      color: context.bloom.text.withValues(alpha: 0.5),
      letterSpacing: 0.9,
    ),
  );
}

class _H1 extends StatelessWidget {
  const _H1(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: bloomText(
      size: 36,
      weight: 700,
      color: context.bloom.text,
      height: 1.06,
      letterSpacing: -1.1,
    ),
  );
}

class _H2 extends StatelessWidget {
  const _H2(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: bloomText(
      size: 24,
      weight: 700,
      color: context.bloom.text,
      height: 1.15,
      letterSpacing: -0.6,
    ),
  );
}

class _Sub extends StatelessWidget {
  const _Sub(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: bloomText(
      size: 13.5,
      weight: 400,
      color: context.bloom.text.withValues(alpha: 0.55),
      height: 1.4,
    ),
  );
}

/// A huge number with its word small beside it: the slides' main move.
class _Num extends StatelessWidget {
  const _Num({
    required this.n,
    required this.word,
    required this.size,
    this.gap = 12,
  });

  final String n;
  final String word;
  final double size;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(
          child: Text(
            n,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: bloomText(
              size: size,
              weight: 700,
              color: t.text,
              height: 0.98,
              letterSpacing: -0.05 * size,
            ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ),
        SizedBox(width: gap),
        Flexible(
          child: Text(
            word,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: bloomText(
              size: 13.5,
              weight: 700,
              color: t.text.withValues(alpha: 0.55),
            ),
          ),
        ),
      ],
    );
  }
}

/// Brings a piece in from a touch below, after [delay] ms: a slide comes in
/// one piece after another. The delay is inside the controller, so a slide
/// gone early leaves no timer behind.
class _Rise extends StatefulWidget {
  const _Rise({required this.child, this.delay = 0});

  final Widget child;
  final int delay;

  @override
  State<_Rise> createState() => _RiseState();
}

class _RiseState extends State<_Rise> with SingleTickerProviderStateMixin {
  static const int _ms = 450;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.delay + _ms),
  )..forward();

  late final Animation<double> _curve = CurvedAnimation(
    parent: _c,
    curve: Interval(
      widget.delay / (widget.delay + _ms),
      1,
      curve: Curves.easeOutCubic,
    ),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _curve,
    builder: (_, child) => Opacity(
      opacity: _curve.value,
      child: Transform.translate(
        offset: Offset(0, 12 * (1 - _curve.value)),
        child: child,
      ),
    ),
    child: widget.child,
  );
}
