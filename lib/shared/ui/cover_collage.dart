/// Collage from the first tracks' covers, the picture of a list with none of
/// its own. However many distinct covers it finds is the layout: 1 fills the
/// area, 2 split in half, 3 a big one on the left with two on the right, 4 a
/// 2×2 grid. With none, [fallback] stays.
///
/// Covers come as ready links in list order, so the collage knows nothing about
/// playlists or the library.
library;

import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../../core/store/cover_store.dart';

/// First four distinct non-empty covers, in list order. Duplicates go: every
/// track of an album has one picture, and four copies look broken.
List<String> pickCollageCovers(Iterable<String?> covers) {
  final out = <String>[];
  for (final cover in covers) {
    if (cover == null || cover.isEmpty || out.contains(cover)) continue;
    out.add(cover);
    if (out.length == 4) break;
  }
  return out;
}

class CoverCollage extends StatelessWidget {
  const CoverCollage({super.key, required this.covers, required this.fallback});

  /// Covers of the list's tracks in order, with gaps and repeats; sorted out
  /// inside.
  final Iterable<String?> covers;

  /// What fills the area if there are no covers at all. Only for the whole
  /// area: its icon would repeat in every cell, so a failed cell gets [_blank].
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final picked = pickCollageCovers(covers);
    if (picked.isEmpty) return fallback;
    // A single cover is the whole area: if it failed, there's nothing to show
    // and the placeholder fits.
    if (picked.length == 1) return _cell(picked.first, fallback);

    final blank = _blank(context.bloom);

    // Two covers are full-height columns; three and four are two rows, and with
    // three the first takes the whole left column.
    if (picked.length == 2) {
      return Row(children: [_half(picked[0], blank), _half(picked[1], blank)]);
    }
    if (picked.length == 3) {
      return Row(
        children: [
          _half(picked[0], blank),
          Expanded(
            child: Column(
              children: [_half(picked[1], blank), _half(picked[2], blank)],
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [_half(picked[0], blank), _half(picked[1], blank)],
          ),
        ),
        Expanded(
          child: Row(
            children: [_half(picked[2], blank), _half(picked[3], blank)],
          ),
        ),
      ],
    );
  }

  /// Cell with no picture: a plain plate with no icon, so failed cells read as
  /// one muted patch, not a grid of icons.
  Widget _blank(BloomTokens t) => ColoredBox(color: t.coverEmpty);

  /// A collage part: `Expanded` both ways splits the area evenly; the parent
  /// sets the size.
  Widget _half(String cover, Widget empty) =>
      Expanded(child: _cell(cover, empty));

  Widget _cell(String cover, Widget empty) {
    final image = coverImage(cover);
    if (image == null) return empty;
    return SizedBox.expand(
      child: Image(
        image: image,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => empty,
      ),
    );
  }
}
