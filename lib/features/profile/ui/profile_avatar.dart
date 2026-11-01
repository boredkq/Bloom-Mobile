/// Profile avatar: an own picture or a stand-in figure. One widget for the home
/// header's button, the profile page's header and the editor's preview, so the
/// profile comes as a parameter: the editor draws a DRAFT with it.
///
/// Size comes from an outer [SizedBox]: in flight the header's button becomes
/// the page's large avatar, and a fixed side inside the flying copy would stop
/// it growing.
library;

import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/store/cover_store.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/cover_hero.dart';
import '../profile_store.dart';

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.profile,
    required this.size,
    this.flightTag,
  });

  final UserProfile profile;
  final double size;

  /// Flight tag to the profile page; `null` means no flight.
  final Object? flightTag;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final image = coverImage(profile.avatar);
    // No own picture: as with an empty cover, a solid dark fill and a muted
    // mark on top. The mark is a figure rather than Bloom's: a logo in a face's
    // place reads as a track with no cover.
    final Widget face = image == null
        ? ColoredBox(
            color: t.coverEmpty,
            child: Center(
              child: BloomIcon(
                Bi.userBold,
                size: size * 0.46,
                color: t.text.withValues(alpha: 0.22),
              ),
            ),
          )
        : Image(image: image, fit: BoxFit.cover);

    return SizedBox(
      width: size,
      height: size,
      child: CoverHero(
        tag: flightTag,
        shape: BorderRadius.circular(size / 2),
        // No ring around the avatar, accent or coloured.
        child: ClipOval(child: face),
      ),
    );
  }
}
