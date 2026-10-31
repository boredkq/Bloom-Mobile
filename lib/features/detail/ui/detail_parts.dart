/// Pieces the artist's and the album's / playlist's pages share.
library;

import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/entity_tiles.dart';
import '../../../shared/ui/skeleton.dart';

/// A track of the page. It plays alone: its queue isn't the page's, so the
/// header's "Play" stays "Play".
class DetailRow extends StatelessWidget {
  const DetailRow({super.key, required this.track, this.number});

  final Track track;

  /// An album's: its place instead of the cover they all share.
  final int? number;

  @override
  Widget build(BuildContext context) =>
      TrackRow(track: track, queue: [track], index: 0, number: number);
}

/// "About": three lines, a tap opens the rest and closes it again.
class DetailAbout extends StatefulWidget {
  const DetailAbout(this.text, {super.key});

  final String text;

  @override
  State<DetailAbout> createState() => _DetailAboutState();
}

class _DetailAboutState extends State<DetailAbout> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _open = !_open),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Text(
            widget.text.trim(),
            maxLines: _open ? null : 3,
            overflow: _open ? TextOverflow.visible : TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontSize: 15,
              height: 1.4,
              color: context.bloom.text.withValues(alpha: 0.7),
            ),
          ),
        ),
      ),
    );
  }
}

/// Under the rows while pages are left: a spinner while one loads on its own,
/// "Load more" by hand after one failed, so a dead network doesn't loop.
class DetailLoadMore extends StatelessWidget {
  const DetailLoadMore({super.key, required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: busy
          ? SizedBox(
              height: 44,
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.bloom.accent,
                  ),
                ),
              ),
            )
          : BloomButton(
              label: context.l.commonLoadMore,
              tone: ButtonTone.plate,
              height: 44,
              onTap: onTap,
            ),
    );
  }
}

class DetailEmpty extends StatelessWidget {
  const DetailEmpty(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: context.bloom.muted),
      ),
    );
  }
}

class DetailError extends StatelessWidget {
  const DetailError(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: context.bloom.danger),
      ),
    );
  }
}

/// What the page will look like while it loads: an artist's a title over five
/// rows and one over a row of cards, an album's or a playlist's only rows.
class DetailSkeleton extends StatelessWidget {
  const DetailSkeleton({super.key, required this.artist});

  final bool artist;

  @override
  Widget build(BuildContext context) {
    Widget title(double width) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 14),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: SkeletonBox(width: width, height: 18, radius: 9),
      ),
    );
    return SkeletonPulse(
      child: Column(
        children: [
          if (artist) title(140),
          for (var i = 0; i < (artist ? 5 : 8); i++) TrackRowSkeleton(index: i),
          if (artist) ...[
            title(110),
            const CarouselSkeleton(height: 212, card: 132),
          ],
        ],
      ),
    );
  }
}
