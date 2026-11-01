/// My Wave atop the home screen, the phone's turn of the PC's wave page: the
/// living circle on a stage in the wave's colour fills the first screen, the
/// rest of the home lies below it.
///
/// With nothing in the player, "My Wave" at the circle's heart starts it; else
/// the circle holds what plays, a wave or not: the artist, the cover, dislike ·
/// the title on the progress · like (the transport is the mini player's). At
/// the foot, along an arc, other waves to turn to. A long press on the stage
/// tunes the wave (the platform, the dislikes).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/library_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/pressable.dart';
import '../../../shared/ui/track_actions.dart';
import '../../../shared/util/artists.dart';
import '../../../shared/util/taste.dart';
import '../../customization/custom_store.dart';
import '../../detail/artists_sheet.dart';
import '../../player/play_source.dart';
import '../../player/player_controller.dart';
import '../../player/ui/player_sheet.dart';
import '../../profile/artist_avatars.dart';
import '../../settings/cover_accent.dart';
import '../wave_actions.dart';
import '../wave_controller.dart';
import '../wave_seeds.dart';
import '../wave_store.dart';
import '../wave_types.dart';
import 'vibe.dart';
import 'wave_tune_sheet.dart';

// Knobs: the circle's dense part across this share of the screen's width; the
// row of waves' height; a wave's share of the row; the film's opacity under
// text and buttons.
const double _coreShare = 1.05;
const double _picksH = 172;
const double _pickShare = 0.36;
const double _filmAlpha = 0.72;
const double _filmSide = 44;

/// Waves to turn to. Read again when the library or the dislikes change, not
/// on every play: the row shouldn't shift under the finger.
final _picksProvider = Provider.autoDispose<List<WaveOption>>((ref) {
  ref.watch(libraryProvider);
  ref.watch(waveStoreProvider);
  return wavePicks(recsInputOf(ref));
});

class WaveHero extends ConsumerStatefulWidget {
  const WaveHero({super.key, required this.header, required this.scroll});

  /// The home's header, over the stage.
  final Widget header;

  /// The home's scroll: scrolled away, the circle rests.
  final ScrollController scroll;

  @override
  ConsumerState<WaveHero> createState() => _WaveHeroState();
}

class _WaveHeroState extends ConsumerState<WaveHero> {
  bool _seen = true;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    widget.scroll.addListener(_onScroll);
    playerSheetOpen.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.scroll.removeListener(_onScroll);
    playerSheetOpen.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    final box = context.findRenderObject() as RenderBox?;
    final off = widget.scroll.hasClients ? widget.scroll.offset : 0.0;
    final seen =
        !playerSheetOpen.value && (box == null || off < box.size.height);
    if (seen != _seen) setState(() => _seen = seen);
  }

  /// A start from the heart: the spinner until the batch is in.
  Future<void> _start(Future<void> Function() go) async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      await go();
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final width = mq.size.width;
    final height = mq.size.height - bottomBarsInset(context);
    final head = mq.padding.top + 60;
    final picks = ref.watch(_picksProvider);
    final track = ref.watch(playbackProvider.select((s) => s.track));
    final playing = ref.watch(playingNowProvider);
    final cover = ref.watch(playerCoverProvider);
    final tone = track == null
        ? null
        : ref.watch(coverHslProvider(cover)).valueOrNull;
    final source = ref.watch(playbackProvider.select((s) => s.source));
    ref.watch(effectiveWaveSourceProvider);
    final canPersonal = ref.read(waveProvider.notifier).canPersonal();
    final busy = _starting || ref.watch(waveProvider).starting;

    // Back, when anything but My Wave plays; with no picks the actions stand
    // alone in the middle, and with nothing My Wave could start from there's
    // no row at all.
    final backOn =
        track != null &&
        !(source is WaveSource && source.mode == WaveMode.personal);
    final mid = (picks.length / 2).ceil();
    final ring = [
      ...picks.take(mid),
      if (backOn) const WaveOption.action(WaveOptionKind.back),
      const WaveOption.action(WaveOptionKind.shake),
      ...picks.skip(mid),
    ];
    final listOn = picks.isNotEmpty || canPersonal;
    final heartBottom = listOn ? _picksH : 0.0;
    final center = Offset(width / 2, (head + height - heartBottom) / 2);

    return SizedBox(
      height: height,
      child: Stack(
        // The stage runs on up into a pull past the top.
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: GestureDetector(
              onLongPress: () => showWaveTuneSheet(context),
              child: Vibe(
                tone: tone,
                playing: playing,
                center: center,
                core: _coreShare * width,
                running: _seen,
              ),
            ),
          ),
          Positioned(
            top: head,
            left: 24,
            right: 24,
            bottom: heartBottom,
            child: Center(
              child: track == null
                  ? _WaveTitle(
                      starting: busy,
                      onTap: () =>
                          _start(() => startPersonalWave(context, ref)),
                    )
                  // A low screen shrinks it whole instead of overflowing; its
                  // row of buttons still needs the real width.
                  : LayoutBuilder(
                      builder: (context, box) => FittedBox(
                        fit: BoxFit.scaleDown,
                        child: SizedBox(
                          width: box.maxWidth,
                          child: _NowPlaying(track: track),
                        ),
                      ),
                    ),
            ),
          ),
          if (listOn)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: _picksH,
              child: _Picks(
                options: ring,
                once: picks.isEmpty,
                // The middle wave's picture sits on the circle round the stage's centre.
                arcR: height - _picksH + _PickItem._side / 2 - center.dy,
              ),
            ),
          Positioned(
            top: mq.padding.top,
            left: 0,
            right: 0,
            child: widget.header,
          ),
        ],
      ),
    );
  }
}

/// The artist's size: big, as on Yandex's page, yet a long name keeps to two lines.
double _bigSize(BuildContext context) =>
    (MediaQuery.sizeOf(context).width * 0.15).clamp(40.0, 64.0);

TextStyle? _bigStyle(BuildContext context) {
  final size = _bigSize(context);
  return Theme.of(context).textTheme.headlineLarge?.copyWith(
    fontSize: size,
    height: 1.0,
    letterSpacing: -0.03 * size,
    fontWeight: FontWeight.w700,
    // Cut in the page's colour: it reads on any cover's tone and on the accent.
    color: context.bloom.bg,
  );
}

/// "My Wave", while nothing is in the player: a tap starts it.
class _WaveTitle extends StatelessWidget {
  const _WaveTitle({required this.starting, required this.onTap});

  final bool starting;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final size = _bigSize(context);
    final bg = context.bloom.bg;
    return Semantics(
      button: true,
      label: context.l.waveStart,
      child: Pressable(
        onTap: starting ? null : onTap,
        onLongPress: () => showWaveTuneSheet(context),
        scale: 0.97,
        child: starting
            ? BloomSpinner(
                size: size * 0.6,
                stroke: 3,
                color: bg,
                trackColor: bg.withValues(alpha: 0.25),
              )
            : Text(
                context.l.waveTitle,
                textAlign: TextAlign.center,
                style: _bigStyle(context),
              ),
      ),
    );
  }
}

/// What plays: the artist (opens them), the cover (opens the player; held,
/// the track's menu), dislike · the title on the progress · like.
class _NowPlaying extends ConsumerWidget {
  const _NowPlaying({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final cover = ref.watch(playerCoverProvider);
    final liked = ref.watch(libraryProvider.select((l) => l.isFav(track.id)));
    final disliked = isWaveDisliked(ref, track.id);
    void menu() => showTrackActions(context, ref, track);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => openTrackArtist(context, ref, track),
          child: Text(
            track.artist,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: _bigStyle(context),
          ),
        ),
        const SizedBox(height: 24),
        Pressable(
          onTap: expandPlayerSheet,
          onLongPress: menu,
          scale: 0.97,
          child: Cover(url: cover, size: 96, radius: 10),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, box) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _FilmButton(
                icon: disliked ? Bi.dislikeBold : Bi.dislike,
                label: disliked
                    ? context.l.waveUndislike
                    : context.l.waveDislike,
                onTap: () => toggleWaveDislike(context, ref, track),
              ),
              const SizedBox(width: 8),
              _TitleBar(
                track: track,
                maxWidth: box.maxWidth - 2 * (_filmSide + 8),
                onLongPress: menu,
              ),
              const SizedBox(width: 8),
              _FilmButton(
                icon: liked ? Bi.heartBold : Bi.heart,
                color: liked ? t.sysFavIco : null,
                label: liked
                    ? context.l.taRemoveFromFavorites
                    : context.l.taAddToFavorites,
                onTap: () =>
                    ref.read(libraryProvider.notifier).toggleFav(track),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A plate of the page's colour, dense enough that the text on it reads over
/// the circle's brightest heart.
Color _film(BuildContext context) =>
    context.bloom.bg.withValues(alpha: _filmAlpha);

class _FilmButton extends StatelessWidget {
  const _FilmButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final BloomGlyph icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: CircleIconButton(
      icon: icon,
      size: _filmSide,
      iconSize: 20,
      background: _film(context),
      color: color ?? context.bloom.text,
      onTap: onTap,
    ),
  );
}

/// The title on the progress: the played part a shade lighter; a tap or a
/// drag seeks, a hold opens the track's menu.
class _TitleBar extends ConsumerStatefulWidget {
  const _TitleBar({
    required this.track,
    required this.maxWidth,
    required this.onLongPress,
  });

  final Track track;
  final double maxWidth;
  final VoidCallback onLongPress;

  @override
  ConsumerState<_TitleBar> createState() => _TitleBarState();
}

class _TitleBarState extends ConsumerState<_TitleBar> {
  double? _drag;

  double _frac(Offset local) {
    final box = context.findRenderObject() as RenderBox;
    return (local.dx / box.size.width).clamp(0.0, 1.0);
  }

  void _seek(double frac) {
    final total = ref.read(playheadProvider).value?.total ?? Duration.zero;
    if (total <= Duration.zero) return;
    ref
        .read(playbackProvider.notifier)
        .seek(Duration(milliseconds: (total.inMilliseconds * frac).round()));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final head = ref.watch(playheadProvider).value;
    final total = head?.total.inMilliseconds ?? 0;
    final frac =
        _drag ??
        (total <= 0
            ? 0.0
            : (head!.position.inMilliseconds / total).clamp(0.0, 1.0));
    final max = math.max(0.0, widget.maxWidth);

    return GestureDetector(
      onTapUp: (d) => _seek(_frac(d.localPosition)),
      onLongPress: widget.onLongPress,
      onHorizontalDragStart: (d) =>
          setState(() => _drag = _frac(d.localPosition)),
      onHorizontalDragUpdate: (d) =>
          setState(() => _drag = _frac(d.localPosition)),
      onHorizontalDragEnd: (_) {
        final at = _drag;
        setState(() => _drag = null);
        if (at != null) _seek(at);
      },
      onHorizontalDragCancel: () => setState(() => _drag = null),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: math.min(200, max),
          maxWidth: max,
          minHeight: _filmSide,
          maxHeight: _filmSide,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_filmSide / 2),
          child: ColoredBox(
            color: _film(context),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: frac,
                    child: ColoredBox(color: t.text.withValues(alpha: 0.12)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      widget.track.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: t.text,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Other waves along the circle round the stage's centre: the middle one at
/// its foot, the neighbours rising along it and fading out. A swipe turns it, round and round; back
/// and shake stand in the middle of the picks. With no picks the actions
/// stand alone and nothing turns.
class _Picks extends ConsumerStatefulWidget {
  const _Picks({required this.options, required this.once, required this.arcR});

  final List<WaveOption> options;
  final bool once;

  /// The circle's radius, from the stage's centre to the middle wave.
  final double arcR;

  @override
  ConsumerState<_Picks> createState() => _PicksState();
}

class _PicksState extends ConsumerState<_Picks> {
  /// Far from zero both ways, so the row turns round without an end.
  static const int _laps = 1000;

  late PageController _pages = _controller();

  /// The pick a wave is being built from, by its place in the row.
  int? _pending;

  int get _mid {
    final n = widget.options.length;
    final acts = widget.options.where((o) => o.track == null).length;
    return ((n - acts) / 2).ceil();
  }

  // keepPage off: a row built anew (the home scrolled far and back) restored
  // its old page, while the arc's first frame reads initialPage, so every
  // pick rose to the arc's top and stayed there till a swipe.
  PageController _controller() => PageController(
    viewportFraction: _pickShare,
    initialPage: widget.once ? 0 : widget.options.length * _laps + _mid,
    keepPage: false,
  );

  @override
  void initState() {
    super.initState();
    _ensureAvatars();
  }

  @override
  void didUpdateWidget(_Picks old) {
    super.didUpdateWidget(old);
    if (old.options.length != widget.options.length ||
        old.once != widget.once) {
      _pages.dispose();
      _pages = _controller();
    }
    _ensureAvatars();
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _ensureAvatars() {
    final artists = [
      for (final o in widget.options)
        if (o.kind == WaveOptionKind.artist)
          (name: o.name, source: o.track!.source),
    ];
    if (artists.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(artistAvatarsProvider.notifier).ensure(artists);
    });
  }

  Future<void> _go(int slot, WaveOption o) async {
    if (_pending != null) return;
    setState(() => _pending = slot);
    try {
      await switch (o.kind) {
        WaveOptionKind.artist => startWaveFromArtistName(
          context,
          ref,
          o.track!,
          o.name,
        ),
        WaveOptionKind.track => startWaveFromTrack(context, ref, o.track!),
        WaveOptionKind.back => startPersonalWave(context, ref),
        WaveOptionKind.shake => shakeWave(context, ref),
      };
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  Widget _pick(int slot, WaveOption o, double width) => SizedBox(
    width: width,
    child: _PickItem(
      option: o,
      pending: _pending == slot,
      onTap: () => _go(slot, o),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final options = widget.options;
    return LayoutBuilder(
      builder: (context, box) {
        final itemW = box.maxWidth * _pickShare;
        if (widget.once) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, o) in options.indexed) _pick(i, o, itemW),
            ],
          );
        }
        final arcR = math.max(widget.arcR, itemW);
        return PageView.builder(
          controller: _pages,
          padEnds: true,
          // The neighbours rise out of the row.
          clipBehavior: Clip.none,
          itemBuilder: (context, i) => AnimatedBuilder(
            animation: _pages,
            builder: (context, child) {
              final page = _pages.hasClients && _pages.position.haveDimensions
                  ? _pages.page!
                  : _pages.initialPage.toDouble();
              final d = (i - page).abs();
              final dx = math.min(d * itemW, arcR);
              final rise = arcR - math.sqrt(arcR * arcR - dx * dx);
              final fade = ((d - 0.6) / 1.0).clamp(0.0, 1.0);
              return Transform.translate(
                offset: Offset(0, -rise),
                child: Opacity(
                  opacity: 1 - 0.6 * fade * fade * (3 - 2 * fade),
                  child: child,
                ),
              );
            },
            child: Align(
              alignment: Alignment.topCenter,
              child: _pick(i, options[i % options.length], itemW),
            ),
          ),
        );
      },
    );
  }
}

/// A wave to turn to: a picture (round for an artist) or a glyph, a small
/// line over the name. The wave on now: the playing bars over its dimmed
/// picture, the line in the accent.
class _PickItem extends ConsumerWidget {
  const _PickItem({
    required this.option,
    required this.pending,
    required this.onTap,
  });

  final WaveOption option;
  final bool pending;
  final VoidCallback onTap;

  static const double _side = 64;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final l = context.l;
    final theme = Theme.of(context).textTheme;
    final o = option;
    final run = ref.watch(waveProvider);
    final current = run.active && o.about.isNotEmpty && run.about == o.about;
    final playing = ref.watch(playingNowProvider);

    final Widget picture;
    switch (o.kind) {
      case WaveOptionKind.back || WaveOptionKind.shake:
        picture = SizedBox.square(
          dimension: _side,
          child: BloomIcon(
            o.kind == WaveOptionKind.back ? Bi.restart : Bi.shuffle,
            size: 34,
            color: t.text,
          ),
        );
      case WaveOptionKind.artist || WaveOptionKind.track:
        final artist = o.kind == WaveOptionKind.artist;
        picture = Cover(
          url: _picture(ref, o),
          size: _side,
          circle: artist,
          radius: 10,
          overlay: current
              ? ColoredBox(
                  color: Colors.black.withValues(alpha: 0.45),
                  child: Center(
                    child: EqualizerBars(
                      playing: playing,
                      color: Colors.white,
                      scale: 1.2,
                    ),
                  ),
                )
              : null,
        );
    }

    final sub = switch (o.kind) {
      _ when current => l.wavePickNow,
      WaveOptionKind.artist => l.wavePickArtist,
      WaveOptionKind.track => l.wavePickTrack,
      _ => '',
    };
    final name = switch (o.kind) {
      WaveOptionKind.artist => o.name,
      WaveOptionKind.track => o.track!.name,
      WaveOptionKind.back => l.waveBack,
      WaveOptionKind.shake => l.waveShake,
    };

    return Pressable(
      onTap: pending ? null : onTap,
      scale: 0.97,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                picture,
                if (pending) BloomSpinner(size: 26, stroke: 2.4, color: t.text),
              ],
            ),
            const SizedBox(height: 10),
            if (sub.isNotEmpty)
              Text(
                sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.bodySmall?.copyWith(
                  fontSize: 12,
                  color: current ? t.accent : t.text2,
                ),
              ),
            Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.titleSmall?.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: t.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An artist's avatar (their own on the track, else found by name), else the
/// cover of their track; a track's own cover.
String? _picture(WidgetRef ref, WaveOption o) {
  final track = o.track!;
  if (o.kind == WaveOptionKind.track) return track.cover;
  if (ownArtistAvatar(track) case final own?) return own;
  return ref.watch(
        artistAvatarsProvider.select(
          (m) => m[artistAvatarKey(track.source, o.name)],
        ),
      ) ??
      track.cover;
}
