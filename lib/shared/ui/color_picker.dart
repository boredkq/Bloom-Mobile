/// Colour picker: a saturation and brightness square, a hue bar and a hex
/// field, in a sheet.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;

import '../../app/theme/tokens.dart';
import '../../core/l10n/l10n.dart';
import 'atoms.dart';
import 'bloom_sheet.dart';
import 'pressable.dart';

/// Opens the picker; returns the colour, or `null` if dismissed.
Future<Color?> showBloomColorPicker(BuildContext context, Color initial) {
  // The root navigator and dimming glass, as for all my sheets, or it stays
  // under the tab bar and mini player.
  return showBloomModal<Color>(
    context: context,
    builder: (_) => _ColorPickerSheet(initial: initial),
  );
}

/// `#rrggbb` with no alpha: the form colours are stored in.
String colorToHex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// Parses `#rgb` or `#rrggbb`; `null` if it isn't a colour.
Color? colorFromHex(String input) {
  var hex = input.trim().replaceAll(RegExp('[^0-9a-fA-F]'), '');
  if (hex.length == 3) {
    hex = hex.split('').map((c) => '$c$c').join();
  }
  if (hex.length != 6) return null;
  return Color(0xFF000000 | int.parse(hex, radix: 16));
}

class _ColorPickerSheet extends StatefulWidget {
  const _ColorPickerSheet({required this.initial});

  final Color initial;

  @override
  State<_ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends State<_ColorPickerSheet> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);
  late final TextEditingController _hex = TextEditingController(
    text: colorToHex(widget.initial),
  );

  Color get _color => _hsv.toColor();

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _set(HSVColor next, {bool syncHex = true}) {
    setState(() {
      _hsv = next;
      if (syncHex) _hex.text = colorToHex(next.toColor());
    });
  }

  void _onHex(String value) {
    final parsed = colorFromHex(value);
    if (parsed == null) return;
    // Black and white have no hue, so I keep the previous one or the slider
    // would jump to red on every 000000.
    final next = HSVColor.fromColor(parsed);
    _set(
      next.saturation == 0 || next.value == 0 ? next.withHue(_hsv.hue) : next,
      syncHex: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;

    return SheetSurface(
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 190,
                child: _SatBox(
                  hsv: _hsv,
                  onChanged: (s, v) =>
                      _set(_hsv.withSaturation(s).withValue(v)),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 26,
                child: _HueBar(
                  hue: _hsv.hue,
                  onChanged: (h) => _set(_hsv.withHue(h)),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  ColorChip(color: _color, width: 42, height: 42),
                  const SizedBox(width: 12),
                  Expanded(
                    child: BloomField(
                      controller: _hex,
                      onChanged: _onHex,
                      maxLength: 7,
                      formatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp('[#0-9a-fA-F]'),
                        ),
                      ],
                      fill: t.pill,
                      radius: t.radius * 0.6,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SheetButton(
                      label: context.l.commonCancel,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SheetButton(
                      label: context.l.commonDone,
                      tone: ButtonTone.accent,
                      onTap: () => Navigator.of(context).pop(_color),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Saturation and brightness square: s across, v down.
class _SatBox extends StatelessWidget {
  const _SatBox({required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final void Function(double s, double v) onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return LayoutBuilder(
      builder: (context, box) {
        void pick(Offset local) => onChanged(
          (local.dx / box.maxWidth).clamp(0.0, 1.0),
          1 - (local.dy / box.maxHeight).clamp(0.0, 1.0),
        );
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (d) => pick(d.localPosition),
          onPanUpdate: (d) => pick(d.localPosition),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(t.radius * 0.6),
            child: CustomPaint(
              size: Size(box.maxWidth, box.maxHeight),
              painter: _SatPainter(hsv),
            ),
          ),
        );
      },
    );
  }
}

class _SatPainter extends CustomPainter {
  const _SatPainter(this.hsv);

  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final hue = HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor();
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.white, hue],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(rect),
    );
    _drawKnob(
      canvas,
      Offset(hsv.saturation * size.width, (1 - hsv.value) * size.height),
    );
  }

  @override
  bool shouldRepaint(_SatPainter old) => old.hsv != hsv;
}

class _HueBar extends StatelessWidget {
  const _HueBar({required this.hue, required this.onChanged});

  final double hue;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        void pick(Offset local) =>
            onChanged((local.dx / box.maxWidth).clamp(0.0, 1.0) * 360);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (d) => pick(d.localPosition),
          onPanUpdate: (d) => pick(d.localPosition),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: CustomPaint(
              size: Size(box.maxWidth, box.maxHeight),
              painter: _HuePainter(hue),
            ),
          ),
        );
      },
    );
  }
}

class _HuePainter extends CustomPainter {
  const _HuePainter(this.hue);

  final double hue;

  static const List<Color> _spectrum = [
    Color(0xFFFF0000),
    Color(0xFFFFFF00),
    Color(0xFF00FF00),
    Color(0xFF00FFFF),
    Color(0xFF0000FF),
    Color(0xFFFF00FF),
    Color(0xFFFF0000),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(colors: _spectrum).createShader(rect),
    );
    _drawKnob(
      canvas,
      Offset((hue / 360) * size.width, size.height / 2),
      radius: size.height / 2 - 2,
    );
  }

  @override
  bool shouldRepaint(_HuePainter old) => old.hue != hue;
}

/// Knob: a white ring on a dark base, readable on any colour.
void _drawKnob(Canvas canvas, Offset at, {double radius = 8}) {
  canvas.drawCircle(
    at,
    radius,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.black.withValues(alpha: 0.35),
  );
  canvas.drawCircle(
    at,
    radius,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white,
  );
}

/// A rounded sample of a colour; with [onTap] it opens a choice.
class ColorChip extends StatelessWidget {
  const ColorChip({
    super.key,
    required this.color,
    this.width,
    this.height = 44,
    this.onTap,
  });

  final Color color;
  final double? width;
  final double height;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Pressable(
      onTap: onTap,
      scale: 0.97,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(t.radius * 0.6),
          border: Border.all(color: t.ovlLine2),
        ),
      ),
    );
  }
}
