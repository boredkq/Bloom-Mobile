/// Glass surface of the interface. Cards sit right on the app background, so
/// each surface has its own glass, made by [GlassBox].
///
/// **Every `GlassBox` must sit in a [GlassGroup].** `BackdropFilter.grouped`
/// shares one backdrop snapshot among neighbours and blurs it once per group,
/// or a settings screen would cost a dozen full-screen `saveLayer`s. The price:
/// surfaces in a group must not overlap. So there are several groups: one for
/// page content, one for the bottom bars on top of the list, one per sheet.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../features/settings/transparency_store.dart';

/// Shared backdrop snapshot for glass surfaces inside. Goes where a layer that
/// doesn't overlap itself begins: page content, bottom bars, a sheet.
class GlassGroup extends StatelessWidget {
  const GlassGroup({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => BackdropGroup(child: child);
}

/// UI surface: a solid plate, or with transparency on, glass (a translucent
/// fill plus blur and brightness of the backdrop).
///
/// The fill comes from [color], `pill` by default: a surface is lifted from the
/// background by a film, and the bare theme colour at 100% would be a block
/// indistinguishable from the background.
class GlassBox extends ConsumerWidget {
  const GlassBox({
    super.key,
    required this.child,
    this.color,
    this.borderRadius,
    this.borderSide,
    this.shape,
    this.overlay = false,
    this.enabled = true,
  });

  final Widget child;

  /// Fill colour when opaque. `pill` by default.
  final Color? color;

  /// Rounding; the theme's radius by default. Ignored with [shape].
  final BorderRadius? borderRadius;

  /// Border. Ignored with [shape].
  final BorderSide? borderSide;

  /// Custom shape, when rounding and a border aren't enough (a tab bar with a
  /// line only on top, a round button).
  final ShapeBorder? shape;

  /// Read the overlay setting rather than the blocks one: sheets, menus and
  /// dialogs.
  final bool overlay;

  /// Surface that gets no glass even with the setting on (a selected chip is
  /// painted with the accent).
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final glass = enabled
        ? ref.watch(overlay ? overlayGlassProvider : glassProvider)
        : null;
    final fill = color ?? t.pill;
    final form =
        shape ??
        RoundedRectangleBorder(
          borderRadius: borderRadius ?? BorderRadius.circular(t.radius),
          side: borderSide ?? BorderSide.none,
        );

    final surface = Material(
      // The fill lives on `Material`, not `DecoratedBox`: nearly every surface
      // holds an `InkWell` that needs a material ancestor.
      color: glass == null
          ? fill
          : fill.withValues(alpha: fill.a * glass.opacity),
      shape: form,
      clipBehavior: Clip.antiAlias,
      child: child,
    );
    if (glass?.filter == null) return surface;

    // The clip is a must: without it the filter covers the parent's whole area,
    // not just this plate.
    return ClipPath(
      clipper: ShapeBorderClipper(
        shape: form,
        textDirection: Directionality.maybeOf(context),
      ),
      child: BackdropFilter.grouped(filter: glass!.filter!, child: surface),
    );
  }
}
