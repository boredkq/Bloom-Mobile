/// Small shared elements.
library;

import 'dart:math' show max, min;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart' show TextInputFormatter;

import '../../app/theme/bloom_theme.dart';
import '../../app/theme/tokens.dart';
import '../../core/store/cover_store.dart';
import 'bloom_icon.dart';
import 'bloom_mark.dart';
import 'cover_collage.dart';
import 'cover_hero.dart';
import 'glass.dart';
import 'pressable.dart';

/// Height of everything in a header: round buttons, pills, the search field.
/// Collapsed bars, search and the player's pill derive from it, so rows stay
/// aligned.
const double kHeaderControl = 51;

/// Title size inside a header pill. A separate number: track rows and card
/// labels share `titleMedium`, and I can't grow that for the header.
const double kHeaderTitleSize = 16;

/// Height of a filter chip and of the round buttons in its row.
const double kChipHeight = 50;

/// Cap for the iOS bottom inset. It is always 34 pt there against 24 on
/// Android, which would lift the layout visibly higher. The home indicator tops
/// out at 13 pt, so 24 still clears it.
const double _kIosBottomInsetCap = 24;

/// Bottom inset to lay out against, instead of `SafeArea`. Differs only on iOS:
/// on Android this may be a 48 dp three-button bar, and capping it would sit on
/// the buttons.
double bottomSafeInset(BuildContext context) {
  final inset = MediaQuery.paddingOf(context).bottom;
  return defaultTargetPlatform == TargetPlatform.iOS
      ? min(inset, _kIosBottomInsetCap)
      : inset;
}

/// Gap between a floating panel and the screen edges.
const double kFloatGap = 8;

/// Bottom margin of a panel that stops short of the edge. The system inset
/// replaces the gap rather than adding to it, or the panel would float higher
/// than it sits from the sides. The player and the tab bar share this so their
/// bottom edges line up across the transition.
double bottomEdgeInset(BuildContext context) =>
    max(bottomSafeInset(context), kFloatGap);

/// Room below a list for the shell's floating bars. The list runs under them
/// (`Scaffold.extendBody`), so the last rows need this to scroll clear. I read
/// the height from `MediaQuery` because `Scaffold` puts it there; a copy of the
/// number would drift. Outside the shell this is just the system inset.
double bottomBarsInset(BuildContext context) =>
    MediaQuery.paddingOf(context).bottom;

/// Bars inset as a sliver, for scroll views with no `SliverPadding` to add it
/// to.
class SliverBottomBarsInset extends StatelessWidget {
  const SliverBottomBarsInset({super.key, this.extra = 0});

  /// Extra gap above the bars.
  final double extra;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: SizedBox(height: bottomBarsInset(context) + extra),
  );
}

/// What a [BloomButton] is painted with.
enum ButtonTone {
  /// Just the label, in its color.
  text,

  /// Block plate, glass when it's on.
  plate,

  /// Main action: accent fill.
  accent,

  /// Irreversible action: red fill.
  danger,

  /// Secondary: a line, no fill.
  line,

  /// Main action on a coloured backdrop: the text colour's fill reads over any.
  ink,
}

/// The one button with a label. Fills the width it is given (shrinks to the
/// label in a row); height and corners are set at the place.
class BloomButton extends StatelessWidget {
  const BloomButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.tone = ButtonTone.text,
    this.color,
    this.busy = false,
    this.height = 40,
    this.pill = true,
    this.overlay = false,
  });

  final String label;
  final VoidCallback? onTap;
  final BloomGlyph? icon;
  final ButtonTone tone;

  /// Label color of a [ButtonTone.text] button; accent when not set.
  final Color? color;

  /// The action runs: a spinner in place of the icon (or the label), no taps.
  final bool busy;
  final double height;

  /// Round ends; otherwise the theme radius, to sit flush with blocks.
  final bool pill;

  /// Plate on a sheet: takes the overlay glass setting.
  final bool overlay;

  static const _danger = Color(0xFFE0494A);

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final live = onTap != null && !busy;
    final idle = onTap == null;
    final (Color? fill, Color ink) = switch (tone) {
      ButtonTone.text => (null, idle ? t.muted : color ?? t.accent),
      ButtonTone.plate => (null, idle ? t.muted : t.text),
      ButtonTone.line => (null, t.text2),
      ButtonTone.accent => idle ? (t.pill, t.muted) : (t.accent, t.accentText),
      ButtonTone.danger => idle ? (t.ovlBg, t.muted) : (_danger, Colors.white),
      ButtonTone.ink => (t.text, t.bg),
    };
    final radius = BorderRadius.circular(pill ? 999 : t.radius);
    final spinner = BloomSpinner(size: 18, color: ink);
    final glyph = icon;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (glyph != null) ...[
          busy ? spinner : BloomIcon(glyph, size: 18, color: ink),
          const SizedBox(width: 8),
        ],
        if (busy && glyph == null)
          spinner
        else
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: bloomText(size: 14, weight: 600, color: ink),
            ),
          ),
      ],
    );
    final box = SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Center(child: content),
      ),
    );

    return Pressable(
      onTap: live ? onTap : null,
      child: switch (tone) {
        ButtonTone.plate => GlassBox(
          borderRadius: radius,
          overlay: overlay,
          child: box,
        ),
        ButtonTone.line => DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: t.ovlLine2),
          ),
          child: box,
        ),
        _ => DecoratedBox(
          decoration: BoxDecoration(color: fill, borderRadius: radius),
          child: box,
        ),
      },
    );
  }
}

/// Small pill with a value or a short action: tinted [color] when [active],
/// a quiet film otherwise.
class BloomTag extends StatelessWidget {
  const BloomTag({
    super.key,
    required this.text,
    this.active = true,
    this.color,
    this.onTap,
  });

  final String text;
  final bool active;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final c = color ?? t.accent;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? c.withValues(alpha: 0.14) : t.ovlBg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: bloomText(size: 13, weight: 700, color: active ? c : t.text2),
        ),
      ),
    );
  }
}

/// The spinner. With a [value] it's a progress ring over [trackColor].
class BloomSpinner extends StatelessWidget {
  const BloomSpinner({
    super.key,
    this.size = 22,
    this.stroke = 2,
    this.color,
    this.value,
    this.trackColor,
  });

  final double size;
  final double stroke;

  /// Accent when not set.
  final Color? color;
  final double? value;
  final Color? trackColor;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CircularProgressIndicator(
      value: value,
      strokeWidth: stroke,
      color: color ?? context.bloom.accent,
      backgroundColor: trackColor,
    ),
  );
}

/// A square that fills with accent and a tick: an item of a set, where several
/// can be on.
class BloomCheck extends StatelessWidget {
  const BloomCheck({super.key, required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: on ? t.accent : Colors.transparent,
        border: Border.all(color: on ? t.accent : t.muted, width: 1.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: on ? BloomIcon(Bi.check, size: 15, color: t.accentText) : null,
    );
  }
}

/// A line of text in the middle of an empty place: nothing here yet, or what
/// went wrong in [color].
class CenterNote extends StatelessWidget {
  const CenterNote(
    this.text, {
    super.key,
    this.color,
    this.padding = const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
  });

  final String text;

  /// Muted when not set.
  final Color? color;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: color ?? context.bloom.muted),
    ),
  );
}

/// The one text input: cursor, hint and frame live here, the plate around it
/// stays at the place. [fill] gives it a plate of its own.
class BloomField extends StatelessWidget {
  const BloomField({
    super.key,
    this.controller,
    this.focusNode,
    this.hint,
    this.style,
    this.hintStyle,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
    this.fill,
    this.radius,
    this.autofocus = false,
    this.enabled = true,
    this.obscure = false,
    this.autocorrect = true,
    this.maxLength,
    this.maxLines = 1,
    this.minLines,
    this.textAlign = TextAlign.start,
    this.keyboardType,
    this.action,
    this.formatters,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hint;

  /// `titleMedium` when not set.
  final TextStyle? style;

  /// [style] in muted when not set.
  final TextStyle? hintStyle;
  final EdgeInsets padding;
  final Color? fill;
  final double? radius;
  final bool autofocus;
  final bool enabled;
  final bool obscure;

  /// False for keys and links: no corrections or suggestions over them.
  final bool autocorrect;
  final int? maxLength;
  final int? maxLines;
  final int? minLines;
  final TextAlign textAlign;
  final TextInputType? keyboardType;
  final TextInputAction? action;
  final List<TextInputFormatter>? formatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final text = style ?? Theme.of(context).textTheme.titleMedium;
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      enabled: enabled,
      obscureText: obscure,
      autocorrect: autocorrect,
      enableSuggestions: autocorrect,
      maxLength: maxLength,
      maxLines: maxLines,
      minLines: minLines,
      textAlign: textAlign,
      keyboardType: keyboardType,
      textInputAction: action,
      inputFormatters: formatters,
      cursorColor: t.accent,
      style: text,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        isDense: true,
        counterText: '',
        contentPadding: padding,
        hintText: hint,
        hintStyle: hintStyle ?? text?.copyWith(color: t.muted),
        filled: fill != null,
        fillColor: fill,
        border: fill == null
            ? InputBorder.none
            : OutlineInputBorder(
                borderRadius: BorderRadius.circular(radius ?? t.radius),
                borderSide: BorderSide.none,
              ),
      ),
    );
  }
}

/// A title and a line under it, cut to one line each unless told otherwise.
class TwoLines extends StatelessWidget {
  const TwoLines(
    this.title,
    this.sub, {
    super.key,
    this.titleStyle,
    this.subStyle,
    this.gap = 2,
    this.subLines = 1,
    this.center = false,
  });

  final String title;

  /// `null` or empty: only the title.
  final String? sub;

  /// `titleMedium` when not set.
  final TextStyle? titleStyle;

  /// `bodySmall` when not set.
  final TextStyle? subStyle;
  final double gap;
  final int subLines;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final line = sub ?? '';
    final align = center ? TextAlign.center : TextAlign.start;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          textAlign: align,
          overflow: TextOverflow.ellipsis,
          style: titleStyle ?? theme.titleMedium,
        ),
        if (line.isNotEmpty) ...[
          SizedBox(height: gap),
          Text(
            line,
            maxLines: subLines,
            textAlign: align,
            overflow: TextOverflow.ellipsis,
            style: subStyle ?? theme.bodySmall,
          ),
        ],
      ],
    );
  }
}

/// A round plate with a mark in the middle.
class TintCircle extends StatelessWidget {
  const TintCircle({
    super.key,
    required this.size,
    required this.color,
    required this.child,
  });

  final double size;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    child: child,
  );
}

/// A number on an accent pill: how many, or which in order.
class CountBadge extends StatelessWidget {
  const CountBadge(
    this.value, {
    super.key,
    this.height = 18,
    this.size = 10,
    this.side = 5,
  });

  final int value;
  final double height;
  final double size;
  final double side;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Container(
      constraints: BoxConstraints(minWidth: height),
      height: height,
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(horizontal: side),
      decoration: BoxDecoration(
        color: t.accent,
        borderRadius: BorderRadius.circular(height / 2),
      ),
      child: Text(
        '$value',
        style: bloomText(
          size: size,
          weight: 700,
          color: t.accentText,
          height: 1,
        ),
      ),
    );
  }
}

/// A straight progress bar. With [animated] it glides to a new value.
class BloomBar extends StatelessWidget {
  const BloomBar({
    super.key,
    required this.value,
    required this.color,
    required this.track,
    this.height = 4,
    this.gradient,
    this.animated,
  });

  final double value;
  final Color color;
  final Color track;
  final double height;

  /// Instead of [color].
  final Gradient? gradient;
  final Duration? animated;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(height / 2);
    final fill = DecoratedBox(
      decoration: BoxDecoration(
        color: gradient == null ? color : null,
        gradient: gradient,
        borderRadius: radius,
      ),
    );
    final end = value.clamp(0.0, 1.0);
    Widget at(double v, Widget? child) => FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: v,
      child: child,
    );
    return SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(color: track, borderRadius: radius),
        child: animated == null
            ? at(end, fill)
            : TweenAnimationBuilder<double>(
                tween: Tween(end: end),
                duration: animated!,
                curve: Curves.easeOutCubic,
                builder: (_, v, child) => at(v, child),
                child: fill,
              ),
      ),
    );
  }
}

/// Where a big picture is missing.
class BannerEmpty extends StatelessWidget {
  const BannerEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return ColoredBox(
      color: t.coverEmpty,
      child: Center(child: BloomMark(size: 96, color: t.text, opacity: 0.16)),
    );
  }
}

/// A round field in a header: the magnifier, the text, what acts on it.
class HeaderSearchField extends StatelessWidget {
  const HeaderSearchField({
    super.key,
    required this.hint,
    this.controller,
    this.focusNode,
    this.action,
    this.trailing,
    this.onChanged,
    this.onSubmitted,
    this.overPicture = false,
  });

  final String hint;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final TextInputAction? action;
  final Widget? trailing;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Lies over a cover: clear glass and white ink instead of the theme's.
  final bool overPicture;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final ink = overPicture ? Colors.white : t.text;
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        height: kHeaderControl,
        child: Row(
          children: [
            BloomIcon(
              Bi.magnifier,
              size: 21,
              color: overPicture ? Colors.white : t.muted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: BloomField(
                controller: controller,
                focusNode: focusNode,
                hint: hint,
                autofocus: true,
                action: action,
                onChanged: onChanged,
                onSubmitted: onSubmitted,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: kHeaderTitleSize,
                  color: ink,
                ),
                hintStyle: TextStyle(
                  fontSize: kHeaderTitleSize,
                  color: overPicture ? Colors.white54 : t.muted,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
    final shape = BorderRadius.circular(999);
    return overPicture
        ? GlassSurface(shape: shape, child: body)
        : GlassBox(borderRadius: shape, child: body);
  }
}

/// Over a [Cover] while what it leads to is being looked for.
class CoverSpinner extends StatelessWidget {
  const CoverSpinner({super.key});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black.withValues(alpha: 0.55),
    child: const Center(
      child: FractionallySizedBox(
        widthFactor: 0.36,
        heightFactor: 0.36,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
      ),
    ),
  );
}

class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    this.icon,
    this.child,
    this.onTap,
    this.size = kHeaderControl,
    this.iconSize = 23,
    this.background,
    this.borderColor,
    this.glass,
    this.color,
    this.tooltip,
    this.label,
  });

  final BloomGlyph? icon;

  /// Instead of [icon]: a logo, a spinner.
  final Widget? child;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final Color? background;

  /// Circle outline, for fills too transparent to read on their own.
  final Color? borderColor;

  /// Whether to use glass. By default only buttons with no fill of their own:
  /// the accent under play is a state, not a theme surface. A surface film (the
  /// player header over a background) passes true.
  final bool? glass;

  /// Muted while there's nothing to tap, unless given.
  final Color? color;
  final String? tooltip;

  /// What a screen reader says when the icon alone wouldn't.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final border = borderColor;
    final button = Pressable(
      onTap: onTap,
      child: GlassBox(
        color: background,
        enabled: glass ?? background == null,
        shape: CircleBorder(
          side: border == null ? BorderSide.none : BorderSide(color: border),
        ),
        child: SizedBox(
          width: size,
          height: size,
          child:
              child ??
              BloomIcon(
                icon,
                size: iconSize,
                color: color ?? (onTap == null ? t.muted : t.iconFg),
              ),
        ),
      ),
    );
    final hinted = tooltip == null
        ? button
        : Tooltip(message: tooltip!, child: button);
    return label == null
        ? hinted
        : Semantics(button: true, label: label, child: hinted);
  }
}

/// Frosted glass under controls on top of a cover. The circle is light because
/// the blur gives the contrast: a nearly clear white film picks up the cover's
/// colour instead of a dark patch.
const double kGlassBlur = 14;
const Color kGlassFilm = Color(0x2BFFFFFF);

/// Wraps any shape in glass: [shape] clips the blur and draws the film's
/// border.
class GlassSurface extends StatelessWidget {
  const GlassSurface({super.key, required this.shape, required this.child});

  final BorderRadius shape;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: kGlassBlur, sigmaY: kGlassBlur),
        child: Material(
          color: kGlassFilm,
          borderRadius: shape,
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ),
    );
  }
}

/// Round button over a picture: light glass, white icon. `pill` and `iconFg`
/// read as a grey patch on a banner.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    this.icon,
    this.child,
    required this.onTap,
    this.size = kHeaderControl,
    this.iconSize = 23,
    this.background,
    this.color,
  });

  final BloomGlyph? icon;

  /// Instead of [icon]: a spinner.
  final Widget? child;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;

  /// My own fill for on states (followed, saved). The circle is then solid.
  final Color? background;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (background case final fill?) {
      return CircleIconButton(
        icon: icon,
        size: size,
        iconSize: iconSize,
        background: fill,
        color: color ?? Colors.white,
        onTap: onTap,
      );
    }
    return Pressable(
      onTap: onTap,
      child: GlassSurface(
        shape: BorderRadius.circular(size / 2),
        child: SizedBox(
          width: size,
          height: size,
          child:
              child ??
              BloomIcon(
                icon,
                size: iconSize,
                color: color ?? (onTap == null ? Colors.white38 : Colors.white),
              ),
        ),
      ),
    );
  }
}

/// Bottom edge of the cover in hero headers. The cover runs the full header
/// height and is clipped by rounded corners rather than fading out. The scrim
/// only keeps white text readable on a light photo, so it never reaches full
/// opacity or the edge would vanish.
class HeroCover extends StatelessWidget {
  const HeroCover({super.key, required this.child, this.start = 0.20});

  /// The picture: a cover, a collage or a placeholder.
  final Widget child;

  /// Share of the height the scrim leaves untouched.
  final double start;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final rest = 1 - start;
    return ClipRRect(
      borderRadius: BorderRadius.vertical(
        bottom: Radius.circular(t.radius * 1.5),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          // Top: white buttons and the status bar vanish on a light photo, so
          // they get a dark scrim whatever the cover.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.55),
                  Colors.black.withValues(alpha: 0),
                ],
                stops: const [0, 0.28],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  t.bg.withValues(alpha: 0),
                  t.bg.withValues(alpha: 0.45),
                  t.bg.withValues(alpha: 0.70),
                  t.bg.withValues(alpha: 0.80),
                ],
                stops: [start, start + rest * 0.40, start + rest * 0.72, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Equalizer of the playing track: three pill bars, 3 wide with a gap of 2, 17
/// tall, growing from the bottom. Each has its own cycle and starts mid-cycle
/// so the group never syncs up. Frames start and end on one value, so the loop
/// is seamless. On pause the bars just freeze.
class EqualizerBars extends StatefulWidget {
  const EqualizerBars({
    super.key,
    required this.playing,
    this.color,
    this.scale = 1,
  });

  final bool playing;
  final Color? color;

  final double scale;

  @override
  State<EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<EqualizerBars>
    with SingleTickerProviderStateMixin {
  static const double _barW = 3;
  static const double _gap = 2;
  static const double _height = 17;

  /// Keyframes per bar: (cycle share, height share).
  static const List<List<(double, double)>> _frames = [
    [(0, .44), (.24, .80), (.48, .52), (.72, .90), (.88, .62), (1, .44)],
    [(0, .76), (.20, .46), (.42, .86), (.64, .54), (.82, .72), (1, .76)],
    [(0, .56), (.26, .92), (.52, .42), (.74, .78), (.90, .50), (1, .56)],
  ];

  /// Cycle length and negative delay of each bar, ms.
  static const List<int> _durations = [1700, 1350, 2000];
  static const List<int> _delays = [0, 500, 1100];

  /// Set up in [initState], not lazily: a bar that never played would first
  /// touch it in `dispose`, where looking up ancestors is no longer allowed.
  late final Ticker _ticker;

  /// Time played up to the last pause, and time of the current stretch.
  Duration _before = Duration.zero;
  Duration _elapsed = Duration.zero;

  void _tick(Duration d) => setState(() => _elapsed = _before + d);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    if (widget.playing) _ticker.start();
  }

  @override
  void didUpdateWidget(EqualizerBars old) {
    super.didUpdateWidget(old);
    if (widget.playing == old.playing) return;
    if (widget.playing) {
      _ticker.start();
    } else {
      _ticker.stop();
      _before = _elapsed;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// Height of bar [i] as a share of the box: ease-in-out between keyframes.
  double _level(int i) {
    final ms = _elapsed.inMicroseconds / 1000 + _delays[i];
    final p = (ms % _durations[i]) / _durations[i];
    final frames = _frames[i];
    for (var f = 1; f < frames.length; f++) {
      final (t1, v1) = frames[f];
      if (p > t1) continue;
      final (t0, v0) = frames[f - 1];
      final local = Curves.easeInOut.transform((p - t0) / (t1 - t0));
      return v0 + (v1 - v0) * local;
    }
    return frames.last.$2;
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? context.bloom.accent;
    final k = widget.scale;
    return SizedBox(
      height: _height * k,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < _frames.length; i++) ...[
            if (i > 0) SizedBox(width: _gap * k),
            Container(
              width: _barW * k,
              height: _height * k * _level(i),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Settings switch: a 44×24 track and an 18 knob, the accent when on. My own
/// because material `Switch` can't drop its touch highlight and brings its
/// palette.
class BloomSwitch extends StatelessWidget {
  const BloomSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.color,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  /// Track when on; accent by default.
  final Color? color;

  static const _duration = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Pressable(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: _duration,
        curve: Curves.easeOut,
        width: 44,
        height: 24,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: value ? color ?? t.accent : t.border,
          borderRadius: BorderRadius.circular(12),
        ),
        child: AnimatedAlign(
          duration: _duration,
          curve: Curves.easeOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: value ? t.accentText : Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

/// Cover: a rounded image with a placeholder when there is none.
class Cover extends StatelessWidget {
  const Cover({
    super.key,
    required this.url,
    required this.size,
    this.radius,
    this.circle = false,
    this.flight,
    this.overlay,
    this.covers,
  });

  final String? url;
  final double size;
  final double? radius;
  final bool circle;

  /// Covers of the list's tracks, for a collage when it has no picture of its
  /// own. The same as in that list's header, so card and page match. `null` for
  /// things that aren't lists.
  final Iterable<String?>? covers;

  /// Layer over the picture: the playing set's equalizer. It sits beside the
  /// flight, not inside: only the cover flies and the bars stay on the card.
  final Widget? overlay;

  /// Flight tag to the header of the page this card opens. `null` means the
  /// cover stays put. Only a real picture flies: on the other end a
  /// placeholder's place is taken by a collage or tint.
  final CoverFlight? flight;

  static double defaultRadius(BloomTokens t) => t.radius * 0.72;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final shape = circle
        ? BorderRadius.circular(size / 2)
        : BorderRadius.circular(radius ?? defaultRadius(t));

    // Empty cover: a muted Bloom mark. The fill is solid because a film over a
    // background picture showed the wallpaper and read as a hole in the list.
    Widget placeholder() => DecoratedBox(
      decoration: BoxDecoration(color: t.coverEmpty, borderRadius: shape),
      child: Center(
        child: BloomMark(size: size * 0.34, color: t.text, opacity: 0.16),
      ),
    );

    // I clip the overlay to the picture's shape, or the film spills past the
    // rounded corners.
    Widget withOverlay(Widget child) => overlay == null
        ? child
        : Stack(
            fit: StackFit.expand,
            children: [
              child,
              ClipRRect(borderRadius: shape, child: overlay),
            ],
          );

    final image = coverImage(url);
    if (image == null) {
      final collage = covers;
      return SizedBox(
        width: size,
        height: size,
        child: withOverlay(
          collage == null
              ? placeholder()
              : ClipRRect(
                  borderRadius: shape,
                  child: CoverCollage(covers: collage, fallback: placeholder()),
                ),
        ),
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: withOverlay(
        // The rounding goes inside the flight: a parent's clip doesn't reach
        // the flying copy, [CoverHero] shapes it itself.
        CoverHero(
          tag: flight?.tag,
          shape: shape,
          child: ClipRRect(
            borderRadius: shape,
            child: Image(
              image: image,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => placeholder(),
              frameBuilder: (context, child, frame, wasSync) {
                if (wasSync || frame != null) return child;
                return placeholder();
              },
            ),
          ),
        ),
      ),
    );
  }
}
