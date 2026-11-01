/// The artist's and the album's / playlist's header: the picture full width,
/// "back" and "⋯" over its top, the title, the line under it and the actions
/// at its bottom. A sliver: the round buttons stay pinned ([StickyHero]).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../core/l10n/l10n.dart';
import '../../core/store/cover_store.dart';
import '../../features/player/player_controller.dart';
import 'atoms.dart';
import 'bloom_icon.dart';

import 'cover_hero.dart';
import 'glass.dart';
import 'pressable.dart';
import 'sticky_hero.dart';

class DetailHero extends StatelessWidget {
  const DetailHero({
    super.key,
    required this.image,
    required this.title,
    required this.subtitle,
    required this.actions,
    this.owner,
    this.ownerAvatar,
    this.onOwner,
    this.onMenu,
    this.flight,
  });

  /// The artist's avatar or the set's cover; a profile's banner isn't used.
  final String? image;

  final String title;

  /// The set's owner, between the title and the numbers.
  final String? owner;

  /// The owner's face beside their name.
  final String? ownerAvatar;

  /// Set when the owner is an artist whose page a tap opens.
  final VoidCallback? onOwner;

  /// The numbers: the count, the length, an album's year.
  final String subtitle;

  /// The row under it: "Play" and the round ones.
  final Widget actions;

  /// "⋯" at the top right; none when null.
  final VoidCallback? onMenu;

  /// The card's cover, flying into [image]; null, the header just fades in.
  final CoverFlight? flight;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final size = MediaQuery.of(context).size;
    // Square, but capped by height: on a tall screen the buttons would need
    // a scroll.
    final height = size.width * 0.92 < size.height * 0.5
        ? size.width * 0.92
        : size.height * 0.5;

    return StickyHero(
      height: height + 72,
      flying: flight != null,
      // The picture goes under the actions and ends rounded: the edge shows.
      background: HeroCover(
        child: CoverHero(
          tag: flight?.tag,
          shape: BorderRadius.vertical(bottom: Radius.circular(t.radius * 1.5)),
          child: _Background(url: image, previous: flight?.image),
        ),
      ),
      barHeight: kHeaderControl,
      bar: Row(
        children: [
          GlassIconButton(
            icon: Bi.arrowLeft,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const Spacer(),
          if (onMenu != null) GlassIconButton(icon: Bi.kebab, onTap: onMenu),
        ],
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: theme.headlineSmall?.copyWith(fontSize: 28),
          ),
          if (owner case final name? when name.isNotEmpty) ...[
            const SizedBox(height: 6),
            _Owner(name: name, avatar: ownerAvatar, onTap: onOwner),
          ],
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 1,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: theme.bodyMedium,
            ),
          ],
          const SizedBox(height: 14),
          actions,
        ],
      ),
    );
  }
}

/// A collection's owner under its title, with their face; a link when they're
/// an artist.
class _Owner extends StatelessWidget {
  const _Owner({required this.name, this.avatar, this.onTap});

  final String name;
  final String? avatar;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (avatar case final url? when url.isNotEmpty) ...[
          Cover(url: url, size: 24, circle: true),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: onTap == null ? t.text2 : t.text,
            ),
          ),
        ),
      ],
    );
    return Center(
      child: onTap == null
          ? row
          : Pressable(onTap: onTap, scale: 0.97, child: row),
    );
  }
}

/// The picture, or the dim Bloom mark as an empty [Cover] has it.
class _Background extends StatelessWidget {
  const _Background({required this.url, this.previous});

  final String? url;

  /// The card's cover: the platform's bigger one comes mid-flight, and without
  /// it the header would blink empty as it lands.
  final String? previous;

  @override
  Widget build(BuildContext context) {
    Widget empty() => const BannerEmpty();
    final earlier = coverImage(previous);
    Widget waiting() => earlier == null
        ? empty()
        : Image(
            image: earlier,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => empty(),
          );

    final image = coverImage(url);
    if (image == null) return waiting();
    return Image(
      image: image,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => waiting(),
      frameBuilder: (context, child, frame, wasSync) =>
          wasSync || frame != null ? child : waiting(),
    );
  }
}

/// "Play" ↔ "Pause": short, so the swap keeps up with the tap.
const Duration _swap = Duration(milliseconds: 180);

/// A list's wide button: "Play", and "Pause" while the queue is this list's,
/// so a second tap pauses instead of starting over. The platform's pages and
/// the library's lists share it.
class HeroPlayButton extends ConsumerWidget {
  const HeroPlayButton({
    super.key,
    required this.sourceId,
    required this.onPlay,
    this.label,
  });

  /// The page's `PlaySource.id`: while it plays, the button pauses. Null,
  /// always "Play".
  final String? sourceId;

  /// Null: nothing to play (loading, or no tracks).
  final VoidCallback? onPlay;

  /// Null: the usual "Play" (a default must be a constant).
  final String? label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final id = sourceId;
    final mine =
        id != null &&
        ref.watch(playbackProvider.select((s) => s.sourceId == id));

    Widget pill({
      required BloomGlyph icon,
      required String text,
      bool on = true,
    }) {
      final tap = on
          ? (mine ? () => ref.read(playbackProvider.notifier).toggle() : onPlay)
          : null;
      return Pressable(
        onTap: tap,
        scale: 0.97,
        child: GlassBox(
          color: on ? t.accent : null,
          enabled: !on,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 13),
            // The icon and the word swap together, in place: the pill holds
            // the width.
            child: AnimatedSwitcher(
              duration: _swap,
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                // A 4% grow, so the tap shows without a jump.
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.96, end: 1).animate(anim),
                  child: child,
                ),
              ),
              child: Row(
                key: ValueKey(text),
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  BloomIcon(icon, size: 18, color: t.accentText),
                  const SizedBox(width: 8),
                  Text(
                    text,
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: t.accentText),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Another list plays: a plain button, no need to watch the player.
    if (!mine) {
      return pill(
        icon: Bi.playBold,
        text: label ?? context.l.commonPlay,
        on: onPlay != null,
      );
    }

    // From the player itself: a pause from the shade or a headset skips
    // `PlaybackState`.
    final playing = ref.watch(playingNowProvider);
    return pill(
      icon: playing ? Bi.pauseBold : Bi.playBold,
      text: playing ? context.l.commonPause : label ?? context.l.commonPlay,
    );
  }
}

/// The header's actions: the wide "Play" and the round ones beside it.
class HeroActions extends StatelessWidget {
  const HeroActions({
    super.key,
    required this.onPlay,
    required this.trailing,
    this.sourceId,
    this.label,
  });

  /// Null: nothing to play (loading, or no tracks).
  final VoidCallback? onPlay;

  /// The round buttons right of "Play".
  final List<Widget> trailing;

  /// See [HeroPlayButton.sourceId].
  final String? sourceId;

  /// Null: the usual "Play" (a default must be a constant).
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: HeroPlayButton(
            sourceId: sourceId,
            onPlay: onPlay,
            label: label,
          ),
        ),
        for (final w in trailing) ...[const SizedBox(width: 10), w],
      ],
    );
  }
}
