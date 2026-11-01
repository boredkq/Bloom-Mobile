/// Going to a track's artist: one opens at once, several are picked in a sheet.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/tokens.dart';
import '../../core/l10n/l10n.dart';
import '../../core/entities/entities.dart';
import '../../core/providers/artist_lookup.dart';
import '../../core/providers/music_provider.dart';
import '../../shared/ui/atoms.dart';
import '../../shared/ui/bloom_icon.dart';
import '../../shared/ui/bloom_sheet.dart';
import '../../shared/ui/bloom_toast.dart';
import '../../shared/ui/pressable.dart';
import '../../shared/util/artists.dart';
import '../profile/tally.dart';
import 'detail_nav.dart';

/// Whether the track has an artist to go to: one with a known page, or
/// several to pick from.
bool canOpenTrackArtist(Track track) {
  final links = artistLinks(track);
  return links.length > 1 || links.length == 1 && links.first.id != null;
}

/// Opens the track's artist; with several, a sheet asks which.
///
/// A lone artist with no known page opens nothing: searching by name with
/// nothing to choose from would lead anywhere.
Future<void> openTrackArtist(
  BuildContext context,
  WidgetRef ref,
  Track track,
) async {
  final links = artistLinks(track);
  if (links.length < 2) {
    final id = links.firstOrNull?.id;
    if (id == null) return;
    return openArtist(
      context,
      id,
      // The header draws at once: the track already carries the name and avatar.
      initial: Artist(
        id: id,
        name: links.first.name,
        source: track.source,
        avatar: ownArtistAvatar(track),
        verified: track.artistVerified,
      ),
    );
  }

  final picked = await showBloomSheetChild<Artist>(
    context: context,
    header: SheetHero(
      cover: track.cover,
      title: track.name,
      subtitle: track.artist,
    ),
    child: _ArtistPicker(track: track, links: links),
  );
  // I open the page from the screen's context: the sheet's is gone by now.
  if (picked == null || !context.mounted) return;
  await openArtist(context, picked.id, initial: picked);
}

/// Opens an artist from the stats or a review: the page their best track
/// knows, else the one with that name where they were played most.
Future<void> openPlayedArtist(
  BuildContext context,
  WidgetRef ref,
  ArtistPlays a,
) async {
  final known = artistLinks(a.track).where((l) => l.name == a.name).firstOrNull;
  if (known?.id case final id?) {
    return openArtist(
      context,
      id,
      initial: Artist(
        id: id,
        name: a.name,
        source: a.source,
        avatar: ownArtistAvatar(a.track),
        verified: a.track.artistVerified,
      ),
    );
  }
  Artist? found;
  try {
    final provider = ref.read(registryProvider).byId(a.source.id);
    found = provider == null ? null : await findArtistCached(provider, a.name);
  } catch (_) {
    // No network or the platform said no: nowhere to go all the same.
  }
  if (!context.mounted) return;
  if (found == null) {
    showToast(context, context.l.artistNotFound);
    return;
  }
  await openArtist(context, found.id, initial: found);
}

/// The track's artists: avatar and name. Each is looked up on its own, so a
/// row shows at once and its picture comes in when found.
class _ArtistPicker extends ConsumerStatefulWidget {
  const _ArtistPicker({required this.track, required this.links});

  final Track track;
  final List<ArtistLink> links;

  @override
  ConsumerState<_ArtistPicker> createState() => _ArtistPickerState();
}

class _ArtistPickerState extends ConsumerState<_ArtistPicker> {
  /// A name missing here is still being looked for; null — not found.
  final Map<String, Artist?> _found = {};

  @override
  void initState() {
    super.initState();
    final source = widget.track.source;
    // Known pages go without a search; only their avatars are looked up.
    for (final l in widget.links) {
      if (l.id case final id?) {
        _found[l.name] = Artist(id: id, name: l.name, source: source);
      }
    }
    unawaited(_resolve());
  }

  Future<void> _resolve() async {
    final provider = ref.read(registryProvider).byId(widget.track.source.id);
    // No platform to ask: the unknown names stay without a page.
    if (provider == null) {
      if (mounted) {
        setState(() {
          for (final l in widget.links) {
            _found.putIfAbsent(l.name, () => null);
          }
        });
      }
      return;
    }
    // The same name twice in a line ("A & A") is looked up once.
    await Future.wait([
      for (final l in {for (final l in widget.links) l.name: l}.values)
        _one(provider, l),
    ]);
  }

  Future<void> _one(MusicProvider provider, ArtistLink link) async {
    Artist? artist;
    try {
      artist = await findArtistCached(provider, link.name);
    } catch (_) {
      // No network: the row stays as it is, and the miss isn't remembered.
      if (link.id != null) return;
    }
    if (!mounted) return;
    setState(() {
      final known = _found[link.name];
      if (known == null) {
        _found[link.name] = artist;
      } else if (artist?.id == known.id) {
        // Someone else's avatar is worse than none.
        _found[link.name] = known.copyWith(avatar: artist!.avatar);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SheetPanel(
      children: [for (final link in widget.links) _row(link.name)],
    );
  }

  Widget _row(String name) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final pending = !_found.containsKey(name);
    final artist = _found[name];

    final String? note = pending || artist != null
        ? null
        : context.l.artistNotFoundOnSource;

    return Pressable(
      // Nowhere to go while looking and when not found.
      onTap: artist == null ? null : () => Navigator.of(context).pop(artist),
      scale: 0.98,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Cover(url: artist?.avatar, size: 44, circle: true),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    // Found: the name of the account it leads to, which may
                    // differ from the piece of the line.
                    artist?.name ?? name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.titleMedium?.copyWith(
                      color: artist == null && !pending ? t.muted : t.text,
                    ),
                  ),
                  if (note != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            if (pending)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: t.muted,
                ),
              )
            else if (artist != null)
              BloomIcon(Bi.altArrowRight, size: 20, color: t.muted),
          ],
        ),
      ),
    );
  }
}
