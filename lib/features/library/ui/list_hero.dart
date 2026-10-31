/// The pictures of the library's lists: a playlist's cover, the collage of its
/// tracks or the empty cover; the built-in lists' icon on an outline.
library;

import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/store/cover_store.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_mark.dart';
import '../../../shared/ui/cover_collage.dart';

/// The icon of a built-in list ("all", "fav", "history"); null for a playlist.
BloomGlyph? systemListGlyph(String id) => switch (id) {
  'all' => Bi.musicNote,
  'fav' => Bi.heartBold,
  'history' => Bi.clockCircle,
  _ => null,
};

/// A built-in list's picture: its icon in the accent on an outline.
class OutlineArt extends StatelessWidget {
  const OutlineArt({
    super.key,
    required this.icon,
    required this.iconSize,
    required this.borderRadius,
    this.fill,
  });

  final BloomGlyph icon;
  final double iconSize;
  final BorderRadius borderRadius;

  /// Under a header that content scrolls beneath, the page's color.
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: borderRadius,
        border: Border.all(color: t.ovlLine),
      ),
      child: Center(
        child: BloomIcon(icon, size: iconSize, color: t.accent),
      ),
    );
  }
}

/// A list page's header picture, also in the editor.
class ListHeroBackground extends StatelessWidget {
  const ListHeroBackground({
    super.key,
    required this.listId,
    required this.cover,
    required this.tracks,
  });

  /// `all` / `fav` or a playlist's id.
  final String listId;

  /// A playlist's own cover; the built-in lists have none.
  final String? cover;

  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final glyph = systemListGlyph(listId);
    if (glyph != null) {
      return OutlineArt(
        icon: glyph,
        iconSize: 64,
        fill: t.bg,
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(t.radius * 1.5),
        ),
      );
    }

    final image = coverImage(cover);
    if (image != null) {
      return Image(
        image: image,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _empty(t),
      );
    }
    return CoverCollage(
      covers: tracks.map((track) => track.cover),
      fallback: _empty(t),
    );
  }

  Widget _empty(BloomTokens t) => ColoredBox(
    color: t.coverEmpty,
    child: Center(child: BloomMark(size: 96, color: t.text, opacity: 0.16)),
  );
}
