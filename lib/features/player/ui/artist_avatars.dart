/// The track's artists' avatars, stacked before their names in the player.
///
/// Only the uploader's picture comes with the track; the rest are looked up by
/// name ([findArtistCached]), the same lookup the artist sheet uses.
///
/// While looking and loading nothing shows, and nothing when not found or
/// broken: a stand-in next to the name would read as someone's avatar, an
/// empty circle as still loading. The line shifts once, when they arrive.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/entities/entities.dart';
import '../../../core/providers/artist_lookup.dart';
import '../../../core/providers/music_provider.dart';
import '../../../core/store/cover_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/util/artists.dart';

/// Circle diameter. The player's caption is 16 px: the avatar stands a little
/// over lowercase letters, to read as a picture but not compete with the name.
const double _size = 22;

/// How far the next circle tucks under the previous.
const double _overlap = 9;

/// Gap between circles. A CUTOUT rather than an outline: there's a blurred
/// cover under the player, and any solid frame would be a blot.
const double _gap = 2;

/// Gap from the stack to the name.
const double _lead = 8;

class TrackArtistAvatars extends ConsumerStatefulWidget {
  const TrackArtistAvatars({super.key, required this.track});

  final Track track;

  @override
  ConsumerState<TrackArtistAvatars> createState() => _TrackArtistAvatarsState();
}

class _TrackArtistAvatarsState extends ConsumerState<TrackArtistAvatars> {
  /// The track's artists in line order. Also the mark of the request: a new
  /// list on every track change tells a late answer it is for a gone track.
  List<ArtistLink> _links = const [];

  /// Name → avatar URL. Missing: still looking or not found, shown the same.
  Map<String, String> _urls = {};

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(TrackArtistAvatars old) {
    super.didUpdateWidget(old);
    // Same track, same line: what was found still stands.
    if (old.track.id == widget.track.id &&
        old.track.artist == widget.track.artist) {
      return;
    }
    _sync();
  }

  void _sync() {
    // A circle for EVERY name, no cap: a stack cut at three would say three.
    // A fresh list: its identity marks this request.
    final links = List.of(artistLinks(widget.track));
    _links = links;
    _urls = {};

    // The uploader's own avatar comes with the track: only load it.
    if (ownArtistAvatar(widget.track) case final own?) {
      unawaited(_accept(links, links.first.name, own));
      return;
    }
    if (links.isEmpty) return;
    unawaited(_resolve(links));
  }

  /// Puts a picture in the stack only once it has LOADED. A broken link drops
  /// out of the stack entirely: a [Cover] placeholder would read as someone
  /// else's avatar, and likewise while loading.
  Future<void> _accept(
    List<ArtistLink> forLinks,
    String name,
    String url,
  ) async {
    if (!await _loads(url)) return;
    // The track may have changed while loading.
    if (!mounted || !identical(_links, forLinks)) return;
    setState(() => _urls[name] = url);
  }

  Future<void> _resolve(List<ArtistLink> links) async {
    final provider = ref.read(registryProvider).byId(widget.track.source.id);
    // No platform to ask: the names go without pictures.
    if (provider == null) return;
    // The same name twice in a line ("A & A") is looked up once.
    await Future.wait([
      for (final l in {for (final l in links) l.name: l}.values)
        _one(provider, links, l),
    ]);
  }

  Future<void> _one(
    MusicProvider provider,
    List<ArtistLink> forLinks,
    ArtistLink link,
  ) async {
    Artist? found;
    try {
      found = await findArtistCached(provider, link.name);
    } catch (_) {
      // No network: the name stays without a picture.
    }
    if (!mounted || !identical(_links, forLinks)) return;
    final url = found?.avatar;
    if (url == null || url.isEmpty) return;
    // Someone else's avatar is worse than none: the known page, else the name.
    final same = link.id != null
        ? found!.id == link.id
        : found!.name.trim().toLowerCase() == link.name.trim().toLowerCase();
    if (!same) return;
    await _accept(forLinks, link.name, url);
  }

  @override
  Widget build(BuildContext context) {
    final urls = [
      for (final l in _links)
        if (_urls[l.name] != null) _urls[l.name]!,
    ];
    if (urls.isEmpty) return const SizedBox.shrink();

    final step = _size - _overlap;
    return Padding(
      padding: const EdgeInsets.only(right: _lead),
      child: SizedBox(
        width: _size + step * (urls.length - 1),
        height: _size,
        child: Stack(
          children: [
            // Drawn from the tail: the first artist stays ON TOP, as first in
            // the name too.
            for (final i in List.generate(urls.length, (i) => i).reversed)
              Positioned(
                left: step * i,
                child: ClipPath(
                  // A circle under its left neighbour cuts out the neighbour's
                  // edge with a gap, so the stack reads on any background.
                  clipper: i == 0
                      ? null
                      : _NeighbourBite(step: step, gap: _gap),
                  child: Cover(url: urls[i], size: _size, circle: true),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// `true`: the picture decoded and is cached, so [Cover] shows it at once.
/// `false`: a broken link or no network.
Future<bool> _loads(String url) {
  final image = coverImage(url);
  if (image == null) return Future.value(false);
  final done = Completer<bool>();
  final stream = image.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  void finish(bool ok) {
    if (!done.isCompleted) done.complete(ok);
    stream.removeListener(listener);
  }

  listener = ImageStreamListener(
    (_, _) => finish(true),
    onError: (_, _) => finish(false),
  );
  stream.addListener(listener);
  return done.future;
}

/// A circle minus the left neighbour, swollen by [gap].
class _NeighbourBite extends CustomClipper<Path> {
  const _NeighbourBite({required this.step, required this.gap});

  /// How far to the left the neighbour's centre stands.
  final double step;
  final double gap;

  @override
  Path getClip(Size size) {
    final self = Path()..addOval(Offset.zero & size);
    final hole = Path()
      ..addOval(
        Rect.fromCircle(
          center: Offset(size.width / 2 - step, size.height / 2),
          radius: size.width / 2 + gap,
        ),
      );
    return Path.combine(PathOperation.difference, self, hole);
  }

  @override
  bool shouldReclip(_NeighbourBite old) => old.step != step || old.gap != gap;
}
