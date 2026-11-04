/// Platform logos and source badges. A logo is drawn in its brand colours, not
/// tinted to the theme, just as brand names aren't translated. In badges the
/// mark has one colour: the platform's brand colour, or the accent with the
/// accent badges setting.
library;

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../app/theme/tokens.dart';
import '../../core/entities/entities.dart';
import '../../core/store/settings_store.dart';
import 'bloom_icon.dart';

const Map<MusicSource, String> _assets = {
  MusicSource.soundcloud: 'assets/platform/soundcloud.svg',
  MusicSource.ytmusic: 'assets/platform/YouTube.svg',
  MusicSource.yandex: 'assets/platform/yandex_music.svg',
};

/// Brand colour of each platform. Every asset is one fill, YouTube's triangle
/// is a hole in it, so a tint keeps the shape.
const Map<MusicSource, Color> platformColor = {
  MusicSource.soundcloud: Color(0xFFFF5500),
  MusicSource.ytmusic: Color(0xFFFF0033),
  MusicSource.yandex: Color(0xFFFED42B),
};

/// Optical size correction. `size` is the side of the square the mark fits in
/// with `contain`, not its perceived size. YouTube's asset is a wide, nearly
/// solid rectangle (viewBox 313×216), so it fills the square and looks bigger
/// next to the sparse SoundCloud and Yandex marks. I shrink it so the marks
/// weigh the same.
const Map<MusicSource, double> _opticalScale = {MusicSource.ytmusic: 0.82};

/// Platform logo; local files get a folder.
class PlatformLogo extends StatelessWidget {
  const PlatformLogo(this.source, {super.key, this.size = 16, this.color});

  final MusicSource source;

  /// Side of the square the mark fits in, before [_opticalScale].
  final double size;

  /// Tints the mark one colour (badges). `null` keeps the asset's brand
  /// colours.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (source == MusicSource.local) {
      return BloomIcon(
        Bi.folder,
        size: size,
        color: color ?? context.bloom.text,
      );
    }
    final asset = _assets[source];
    if (asset == null) return SizedBox(width: size, height: size);
    final box = size * (_opticalScale[source] ?? 1);
    final tint = color;
    return SvgPicture.asset(
      asset,
      width: box,
      height: box,
      fit: BoxFit.contain,
      colorFilter: tint == null
          ? null
          : ColorFilter.mode(tint, BlendMode.srcIn),
    );
  }
}

/// Share of the badge the mark takes; each logo has its own airiness. YouTube
/// gets less: the badge is small on a phone and a solid wide rectangle would
/// burst it. The resulting width is further scaled by [_opticalScale].
const Map<MusicSource, double> _logoScale = {
  MusicSource.soundcloud: 0.60,
  MusicSource.yandex: 0.58,
  MusicSource.ytmusic: 0.54,
};

/// Cover badge sizes. Two for the whole app, so rows and cards don't drift
/// apart: [kRowBadge] in a list row, [kCardBadge] on a big card.
const double kRowBadge = 18;
const double kCardBadge = 30;

/// Source badge over a cover: a round translucent glass plate (dim plus blur),
/// so the mark reads on any picture without covering it. Goes in a cover
/// corner: `Positioned` outside, inset 3 on rows and 6 on big cards.
///
/// The mark takes the brand colour, or the accent with
/// [SettingsState.accentBadges]. Local tracks have no platform, so no badge.
class SourceBadge extends ConsumerWidget {
  const SourceBadge(this.source, {super.key, this.size = 16});

  final MusicSource source;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = platformColor[source];
    if (brand == null) return const SizedBox.shrink();

    final t = context.bloom;
    final accentBadges = ref.watch(
      settingsProvider.select((s) => s.accentBadges),
    );
    // No outline and no growth past the nominal size: it would read too big on
    // a phone.

    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 1.5, sigmaY: 1.5),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withValues(alpha: 0.38),
          ),
          child: PlatformLogo(
            source,
            size: size * (_logoScale[source] ?? 0.6),
            color: accentBadges ? t.accent : brand,
          ),
        ),
      ),
    );
  }
}

/// An integration service in settings.
enum Service { lastfm, discord }

const Map<Service, String> _serviceAssets = {
  Service.lastfm: 'assets/platform/last-fm.svg',
  Service.discord: 'assets/platform/Discord.svg',
};

/// Both marks are one colour, filled BLACK in the files, which vanishes on the
/// dark theme. So unlike platform logos I tint them myself with the service's
/// brand colour.
const Map<Service, Color> serviceColor = {
  Service.lastfm: Color(0xFFD51007),
  Service.discord: Color(0xFF5865F2),
};

/// Mark of an integration, platform OR service, as one type. For places that
/// look the same whichever it is: settings pages match for SoundCloud and
/// Last.fm, while [MusicSource] and [Service] are separate enums with no common
/// parent.
class BrandMark {
  const BrandMark.platform(MusicSource this.source) : service = null;
  const BrandMark.service(Service this.service) : source = null;

  final MusicSource? source;
  final Service? service;

  /// Brand colour; `null` for local files, which have no platform.
  Color? get color =>
      source != null ? platformColor[source] : serviceColor[service];

  Widget logo({double size = 16, Color? color}) => source != null
      ? PlatformLogo(source!, size: size, color: color)
      : ServiceLogo(service!, size: size, color: color);
}

class ServiceLogo extends StatelessWidget {
  const ServiceLogo(this.service, {super.key, this.size = 16, this.color});

  final Service service;
  final double size;

  /// Colour override, for example to mute a service not yet connected.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      _serviceAssets[service]!,
      width: size,
      height: size,
      fit: BoxFit.contain,
      colorFilter: ColorFilter.mode(
        color ?? serviceColor[service]!,
        BlendMode.srcIn,
      ),
    );
  }
}
