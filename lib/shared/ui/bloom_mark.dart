/// Brand mark: the eight-ray star from the app icon. It is white in the file,
/// so I tint it with `srcIn`; white would vanish on the light theme.
library;

import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';

class BloomMark extends StatelessWidget {
  const BloomMark({super.key, this.size = 18, this.color, this.opacity = 1});

  final double size;

  /// Mark colour; the theme's `text` by default.
  final Color? color;

  final double opacity;

  @override
  Widget build(BuildContext context) {
    final tint = (color ?? context.bloom.text).withValues(alpha: opacity);
    return Image.asset(
      'assets/brand/bloom_mark.png',
      width: size,
      height: size,
      color: tint,
      colorBlendMode: BlendMode.srcIn,
      filterQuality: FilterQuality.medium,
    );
  }
}
