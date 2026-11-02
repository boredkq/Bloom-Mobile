/// Profile banner fill: an own picture, else a colour, an angled gradient or
/// (Auto) the tone of the most played track's cover. The profile comes from
/// outside, as the editor draws its draft too.
library;

import 'dart:math' show cos, sin, pi;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/store/cover_store.dart';
import '../../settings/cover_accent.dart';
import '../profile_store.dart';
import '../stats.dart';

/// Dark cover tone for Auto, the same band as the mini player's background.
/// Cached until restart: scanning means loading a picture.
final _autoToneProvider = FutureProvider.family<Color?, String?>((
  ref,
  cover,
) async {
  final hsl = await extractCoverHsl(cover);
  return hsl == null ? null : miniBgFromHsl(hsl);
});

class ProfileBannerFill extends ConsumerWidget {
  const ProfileBannerFill({super.key, required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = coverImage(profile.banner);
    if (image != null) return Image(image: image, fit: BoxFit.cover);

    final t = context.bloom;
    var from = profile.bannerColor;
    var to = from;
    var angle = profile.bannerAngle;
    switch (profile.bannerMode) {
      case BannerColorMode.solid:
        return ColoredBox(color: from);
      case BannerColorMode.gradient:
        to = profile.bannerColor2;
      case BannerColorMode.auto:
        final cover = ref.watch(profileStatsProvider.select((s) => s.topCover));
        // Until the tone is computed (or nothing's played yet) the profile's
        // own colour.
        from = ref.watch(_autoToneProvider(cover)).value ?? from;
        to = Color.lerp(from, t.blockColor, 0.65)!;
        angle = 135;
    }
    // The angle counts clockwise from up, while [Alignment]'s Y axis points
    // down: hence the flipped signs.
    final a = angle * pi / 180;
    final dx = sin(a);
    final dy = -cos(a);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(-dx, -dy),
          end: Alignment(dx, dy),
          colors: [from, to],
        ),
      ),
    );
  }
}
