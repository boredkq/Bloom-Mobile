/// Bottom sheets: one floating frame for all of them, and the look of the menus
/// about a track, list or artist — the cover as a banner, a capsule of icons,
/// flat rows.
///
/// A sheet goes through the root navigator, so it covers the tab bar and the
/// mini player too; otherwise they would stay above the dimming.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../core/store/cover_store.dart';
import '../../features/settings/transparency_store.dart';
import '../util/format.dart';
import 'bloom_icon.dart';
import 'glass.dart';
import 'pressable.dart';

/// An item of a sheet: a row, or an icon in the capsule.
class SheetAction {
  const SheetAction({
    required this.icon,
    required this.label,
    this.subtitle,
    this.onTap,
    this.danger = false,
    this.trailing,
  });

  final BloomGlyph icon;
  final String label;

  /// Grey line under the label. The capsule shows only the icon.
  final String? subtitle;

  /// The sheet closes BEFORE the call: nearly every item opens a dialog or
  /// another sheet, and those can't open over this one.
  final VoidCallback? onTap;

  /// Red: removes something.
  final bool danger;

  /// A mark on the right, like the tick of the active choice.
  final Widget? trailing;
}

/// A sheet of items: [bar] in the capsule, [groups] as rows below it. Empty
/// groups drop out.
Future<void> showBloomSheet({
  required BuildContext context,
  Widget? header,
  List<SheetAction> bar = const [],
  required List<List<SheetAction>> groups,
}) {
  return showBloomSheetChild<void>(
    context: context,
    header: header,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (bar.isNotEmpty) _ActionBar(actions: bar),
        for (final group in groups)
          if (group.isNotEmpty) _SheetGroup(actions: group),
      ],
    ),
  );
}

/// The same sheet with any content. Returns what it was closed with
/// (`Navigator.pop`).
Future<T?> showBloomSheetChild<T>({
  required BuildContext context,
  Widget? header,
  Widget? footer,
  double maxFraction = _kSheetMaxFraction,
  bool scrolls = true,
  required Widget child,
}) {
  return showBloomModal<T>(
    context: context,
    builder: (_) => _SheetShell(
      header: header,
      footer: footer,
      maxFraction: maxFraction,
      scrolls: scrolls,
      child: child,
    ),
  );
}

/// How tall a sheet may grow, as a share of the screen.
const double _kSheetMaxFraction = 0.85;

/// Corner of the floating sheet, all four.
const double kSheetRadius = 28;

/// Inset of a sheet's content from its edges; headers, plates and fields stand
/// on it.
const double kSheetEdge = 20;

/// Inset of flat rows from the sheet's edge. A row adds its own 16, so icons
/// stand at 24.
const double _kFlatEdge = 8;

/// Height of a sheet's row, with a grey line or without.
const double _kRowHeight = 56;

/// Opens a sheet: the one way in for all of them, those with a shell of their
/// own too (queue, speed, colour picker).
///
/// With "Overlay transparency" on, the page under the sheet is also blurred and
/// the dimming lighter (0.5 → 0.28): under a dark film the blur wouldn't show.
Future<T?> showBloomModal<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final glass = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(overlayGlassProvider);
  return navigator.push(
    _BloomSheetRoute<T>(
      builder: (context) => _FloatingFrame(child: builder(context)),
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      modalBarrierColor: Colors.black.withValues(
        alpha: glass == null ? 0.5 : 0.28,
      ),
    ),
  );
}

/// A sheet whose dimming can be glass. The sheet route doesn't pass a barrier
/// filter on, so I replace the barrier itself; a `Consumer`, because the blur
/// slider lives in a sheet and its own dimming must follow the finger.
class _BloomSheetRoute<T> extends ModalBottomSheetRoute<T> {
  _BloomSheetRoute({
    required super.builder,
    required super.isScrollControlled,
    super.capturedThemes,
    super.backgroundColor,
    super.modalBarrierColor,
  });

  @override
  Widget buildModalBarrier() {
    final barrier = super.buildModalBarrier();
    return Consumer(
      builder: (context, ref, _) {
        final filter = ref.watch(overlayGlassProvider)?.filter;
        if (filter == null) return barrier;
        return BackdropFilter(filter: filter, child: barrier);
      },
    );
  }
}

/// Holds a sheet off the screen's left, right and bottom edges, every corner
/// round. Below it the sheet sees its own width, and a screen without the
/// keyboard: both are dealt with here.
class _FloatingFrame extends StatelessWidget {
  const _FloatingFrame({required this.child});

  final Widget child;

  /// Above this the bottom inset is a row of system buttons, and the sheet
  /// stands over them. A gesture strip is lower: it lies over the sheet, whose
  /// content steps clear of it.
  static const double _gestureStrip = 40;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final gap = (media.size.width * 0.032).clamp(10.0, 20.0);
    final keyboard = media.viewInsets.bottom;
    final inset = media.padding.bottom;
    final overButtons = inset > _gestureStrip;
    final inner = overButtons ? 0.0 : math.max(0.0, inset - gap);

    return MediaQuery(
      data: media.copyWith(
        size: Size(media.size.width - gap * 2, media.size.height - keyboard),
        viewInsets: media.viewInsets.copyWith(bottom: 0),
        padding: media.padding.copyWith(bottom: inner),
        viewPadding: media.viewPadding.copyWith(bottom: inner),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          gap,
          0,
          gap,
          keyboard + (overButtons ? inset : gap),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(kSheetRadius),
          child: child,
        ),
      ),
    );
  }
}

/// A sheet's surface: the theme's plain background, or with overlay glass on a
/// translucent one over a blur of what's underneath.
class SheetSurface extends ConsumerWidget {
  const SheetSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final glass = ref.watch(overlayGlassProvider);
    // Declared here so sheets with a shell of their own get it for free.
    final skinned = _SheetSkinScope(glass: glass != null, child: child);
    if (glass == null) return ColoredBox(color: t.bg, child: skinned);

    final surface = ColoredBox(
      color: t.bg.withValues(alpha: t.bg.a * glass.opacity),
      child: skinned,
    );
    return glass.filter == null
        ? surface
        : BackdropFilter(filter: glass.filter!, child: surface);
  }
}

/// What a sheet's blocks stand on. Under a [SheetHero] they're [flat]: rows
/// without a plate or lines between them.
class _SheetSkinScope extends InheritedWidget {
  const _SheetSkinScope({
    required this.glass,
    this.flat = false,
    required super.child,
  });

  final bool glass;
  final bool flat;

  static _SheetSkinScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SheetSkinScope>();

  @override
  bool updateShouldNotify(_SheetSkinScope old) =>
      old.glass != glass || old.flat != flat;
}

/// Fill of a plate inside a sheet: a thin film on glass, or it would be the one
/// solid spot of a clear sheet; otherwise the same pill as plates of a page.
Color sheetPanelColor(BuildContext context) =>
    _SheetSkinScope.of(context)?.glass ?? false
    ? context.bloom.text.withValues(alpha: 0.06)
    : context.bloom.pill;

/// A line inside a sheet's plate.
Color sheetLineColor(BuildContext context) =>
    _SheetSkinScope.of(context)?.glass ?? false
    ? context.bloom.text.withValues(alpha: 0.08)
    : context.bloom.ovlLine;

class _SheetShell extends ConsumerWidget {
  const _SheetShell({
    required this.header,
    required this.footer,
    required this.maxFraction,
    required this.scrolls,
    required this.child,
  });

  final Widget? header;

  /// Pinned to the bottom, doesn't scroll with the items.
  final Widget? footer;

  /// The share of the screen the sheet doesn't grow past.
  final double maxFraction;

  /// False: the child is a list that scrolls itself and builds lazily, so the
  /// sheet takes its full height instead of wrapping it.
  final bool scrolls;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final media = MediaQuery.of(context);
    final hero = header is SheetHero;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: media.size.height * maxFraction),
      child: _SheetSkinScope(
        glass: ref.watch(overlayGlassProvider) != null,
        flat: hero,
        // A group of its own: the sheet lies over the page and its snapshot of
        // what's underneath must be its own too.
        child: GlassGroup(
          child: Stack(
            children: [
              const Positioned.fill(
                child: SheetSurface(child: SizedBox.expand()),
              ),
              SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // The handle and header stay put: only the items scroll.
                    if (!hero) const SheetHandle(),
                    ?header,
                    if (scrolls)
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [child, const SizedBox(height: 10)],
                          ),
                        ),
                      )
                    else
                      Expanded(child: child),
                    ?footer,
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The sheet's handle: on the banner in [color], else in the theme's text.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Container(
        width: 38,
        height: 4,
        decoration: BoxDecoration(
          color: color ?? context.bloom.text.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

/// A block of a sheet's rows: a plate, or flat under a [SheetHero].
class SheetPanel extends StatelessWidget {
  const SheetPanel({super.key, required this.children, this.gap = 6});

  final List<Widget> children;

  /// Air above and below; less in lists where each row is a block of its own.
  final double gap;

  @override
  Widget build(BuildContext context) {
    final column = Column(mainAxisSize: MainAxisSize.min, children: children);
    if (_SheetSkinScope.of(context)?.flat ?? false) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: _kFlatEdge, vertical: gap),
        child: column,
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(kSheetEdge, gap, kSheetEdge, gap),
      child: Material(
        color: sheetPanelColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(context.bloom.radius),
        ),
        clipBehavior: Clip.antiAlias,
        child: column,
      ),
    );
  }
}

/// A divider inside a [SheetPanel], starting where the text does: a line under
/// the icons would cut their column in half. Flat rows go without one.
///
/// [indent] is where the block's text starts: 54 for an icon (16 + 22 + 16).
Widget sheetDivider({double indent = 54}) => Builder(
  builder: (context) => _SheetSkinScope.of(context)?.flat ?? false
      ? const SizedBox.shrink()
      : Divider(
          height: 1,
          thickness: 1,
          indent: indent,
          color: sheetLineColor(context),
        ),
);

/// The menu's items as flat rows.
class _SheetGroup extends StatelessWidget {
  const _SheetGroup({required this.actions});

  final List<SheetAction> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _kFlatEdge, vertical: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [for (final action in actions) _SheetTile(action: action)],
      ),
    );
  }
}

class _SheetTile extends StatelessWidget {
  const _SheetTile({required this.action});

  final SheetAction action;

  @override
  Widget build(BuildContext context) {
    return SheetRow(
      icon: action.icon,
      label: action.label,
      subtitle: action.subtitle,
      danger: action.danger,
      trailing: action.trailing,
      onTap: _closeThen(context, action.onTap),
    );
  }
}

/// Closes the sheet, then acts. Null stays null: the item is greyed out.
VoidCallback? _closeThen(BuildContext context, VoidCallback? onTap) =>
    onTap == null
    ? null
    : () {
        Navigator.of(context).pop();
        onTap();
      };

/// A sheet's row: icon, label, grey line under it, a mark on the right.
class SheetRow extends StatelessWidget {
  const SheetRow({
    super.key,
    this.icon,
    this.leading,
    required this.label,
    this.subtitle,
    this.color,
    this.danger = false,
    this.trailing,
    this.onTap,
  });

  final BloomGlyph? icon;

  /// Instead of [icon]: a platform's logo.
  final Widget? leading;
  final String label;
  final String? subtitle;

  /// The row's own colour instead of the text's.
  final Color? color;
  final bool danger;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final ink =
        color ??
        (danger
            ? t.danger
            : onTap != null
            ? t.text
            : t.muted);

    return Pressable(
      onTap: onTap,
      scale: 0.98,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _kRowHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              leading ?? BloomIcon(icon!, size: 22, color: ink),
              const SizedBox(width: 22),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.titleMedium?.copyWith(
                        color: ink,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (subtitle case final subtitle?)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.bodySmall,
                      ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// The capsule of main actions under the banner: icons only, evenly spaced.
class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.actions});

  final List<SheetAction> actions;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
        height: _kRowHeight,
        decoration: BoxDecoration(
          color: sheetPanelColor(context),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final action in actions)
              Expanded(
                child: Semantics(
                  button: true,
                  label: action.label,
                  child: Pressable(
                    onTap: _closeThen(context, action.onTap),
                    child: Center(
                      child: BloomIcon(
                        action.icon,
                        size: 24,
                        color: action.onTap == null ? t.muted : t.text,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A date for a sheet's header: "Created 2 Sept 2026". The label goes muted and
/// the date brighter, so the eye catches the date.
class SheetMeta {
  const SheetMeta({required this.label, required this.date});

  final String label;
  final String date;
}

/// No timestamp, no line: a dash in its place would say nothing.
SheetMeta? sheetDateMeta(BuildContext context, String label, int? ms) {
  if (ms == null || ms <= 0) return null;
  return SheetMeta(
    label: label,
    date: stampDate(ms, Localizations.localeOf(context).languageCode),
  );
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.meta});

  final SheetMeta meta;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final base = Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 13);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '${meta.label} ',
            style: TextStyle(color: t.muted),
          ),
          TextSpan(
            text: meta.date,
            style: TextStyle(color: t.text, fontWeight: FontWeight.w500),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: base,
    );
  }
}

/// The header of a sheet about a track, list or artist: the cover as a banner
/// across the sheet, melting into its surface, with the title over the melt.
/// Holds the handle too.
class SheetHero extends StatelessWidget {
  const SheetHero({
    super.key,
    required this.cover,
    required this.title,
    this.subtitle = '',
    this.subtitleWidget,
    this.meta,
  });

  /// Share of the sheet's width the banner takes, and the least it may be:
  /// under that the title climbs into the handle.
  static const double band = 0.24;
  static const double bandMin = 112;

  final String? cover;
  final String title;
  final String subtitle;

  /// Instead of [subtitle]: a line that's alive, like a list's offline count.
  final Widget? subtitleWidget;
  final SheetMeta? meta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final image = coverImage(cover);
    final width = MediaQuery.sizeOf(context).width;

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: image == null ? 0 : math.max(bandMin, width * band),
      ),
      child: Stack(
        alignment: Alignment.bottomLeft,
        children: [
          if (image != null)
            Positioned.fill(
              // A mask, not a gradient to the sheet's colour: the surface may
              // be glass, and the picture must melt into whatever is there.
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (rect) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFFFFFFF),
                    Color(0xD9FFFFFF),
                    Color(0x33FFFFFF),
                    Color(0x00FFFFFF),
                  ],
                  stops: [0, 0.35, 0.7, 1],
                ).createShader(rect),
                child: Image(image: image, fit: BoxFit.cover),
              ),
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(
              child: SheetHandle(
                color: image == null
                    ? null
                    : Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 26, 16, 2),
            // Full width: the text is what sizes the stack, and the banner with it.
            child: SizedBox(
              width: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.titleLarge?.copyWith(fontSize: 20),
                  ),
                  if (subtitleWidget != null || subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    subtitleWidget ??
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.bodyMedium?.copyWith(fontSize: 14),
                        ),
                  ],
                  if (meta case final meta?) ...[
                    const SizedBox(height: 2),
                    _MetaLine(meta: meta),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A sheet's field with a tick on the right. The tick comes with the text:
/// until then the button has nothing to do.
class SheetField extends StatelessWidget {
  const SheetField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.onSubmit,
    this.autofocus = false,
    this.busy = false,
    this.maxLength,
    this.trailing,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;
  final bool autofocus;

  /// Long work under way (import by link): a spinner on the button, no taps.
  final bool busy;
  final int? maxLength;

  /// An icon inside the field on the right: the platform a link was recognised
  /// as.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final filled = controller.text.trim().isNotEmpty;
    final radius = BorderRadius.circular(t.radius);

    return Padding(
      padding: const EdgeInsets.fromLTRB(kSheetEdge, 4, kSheetEdge, 6),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: sheetPanelColor(context),
                borderRadius: radius,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      autofocus: autofocus,
                      maxLength: maxLength,
                      cursorColor: t.accent,
                      textInputAction: TextInputAction.done,
                      style: theme.titleMedium,
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        counterText: '',
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 16,
                        ),
                        hintText: hint,
                        hintStyle: theme.titleMedium?.copyWith(color: t.muted),
                      ),
                      onChanged: onChanged,
                      onSubmitted: (_) => onSubmit(),
                    ),
                  ),
                  if (trailing case final widget?) ...[
                    const SizedBox(width: 8),
                    widget,
                  ],
                ],
              ),
            ),
          ),
          // The row's width moves with the button, or the field would jerk on
          // the first character.
          AnimatedSize(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            child: filled
                ? Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: _ConfirmButton(
                      busy: busy,
                      radius: radius,
                      onTap: onSubmit,
                    ),
                  )
                : const SizedBox(height: 54),
          ),
        ],
      ),
    );
  }
}

class _ConfirmButton extends StatelessWidget {
  const _ConfirmButton({
    required this.busy,
    required this.radius,
    required this.onTap,
  });

  final bool busy;

  /// The field's corner, so the pair doesn't argue.
  final BorderRadius radius;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Pressable(
      onTap: busy ? null : onTap,
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(color: t.accent, borderRadius: radius),
        child: busy
            ? Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: t.accentText,
                  ),
                ),
              )
            : BloomIcon(Bi.check, size: 24, color: t.accentText),
      ),
    );
  }
}

/// Choice tile of a sheet grid: accent when picked, the sheet's plate
/// otherwise. [builder] lays out the content in the given ink.
class OptionTile extends StatelessWidget {
  const OptionTile({
    super.key,
    required this.active,
    required this.onTap,
    required this.builder,
    this.height,
    this.padding = EdgeInsets.zero,
    this.alignment = Alignment.center,
    this.scale = 0.94,
  });

  final bool active;
  final VoidCallback onTap;
  final Widget Function(Color ink) builder;
  final double? height;
  final EdgeInsets padding;
  final Alignment alignment;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Pressable(
      onTap: onTap,
      scale: scale,
      child: Container(
        height: height,
        padding: padding,
        alignment: alignment,
        decoration: BoxDecoration(
          color: active ? t.accent : sheetPanelColor(context),
          border: Border.all(
            color: active ? t.accent : sheetLineColor(context),
          ),
          borderRadius: BorderRadius.circular(t.radius * 0.8),
        ),
        child: builder(active ? t.accentText : t.text),
      ),
    );
  }
}
