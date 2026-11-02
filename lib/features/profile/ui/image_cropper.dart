/// Picture crop for the profile: a frame (a circle for the avatar, a rectangle
/// by aspect for the banner), dragging, a pinch and a scale slider, on
/// [CustomPaint]. Initial scale is cover (the picture fills the frame), and the
/// slider goes down to fit whole.
///
/// The crop renders to a separate layer and saves as an app file; only
/// `local:<name>` goes in the profile.
library;

import 'dart:io';
import 'dart:typed_data' show Uint8List;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/cover_store.dart';
import '../../../shared/ui/atoms.dart';

enum CropShape { circle, rect }

/// Picks a gallery picture, crops it and stores it. Returns the field value
/// (`local:...`), or `null` if abandoned at any step. [aspect] is the frame's
/// height over width (for [CropShape.rect]). [output] is the result's width in
/// pixels: the screen frame is smaller, and keeping it one to one means mush on
/// a large avatar.
Future<String?> pickAndCropImage(
  BuildContext context, {
  required CropShape shape,
  double aspect = 1,
  double output = 720,
  String prefix = 'img',
}) async {
  final path = await pickImageFile();
  if (path == null || !context.mounted) return null;

  final bytes = await Navigator.of(context, rootNavigator: true)
      .push<Uint8List>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => _CropPage(
            path: path,
            shape: shape,
            aspect: aspect,
            output: output,
          ),
        ),
      );
  if (bytes == null) return null;
  return saveLocalImage(bytes, prefix: prefix);
}

class _CropPage extends StatefulWidget {
  const _CropPage({
    required this.path,
    required this.shape,
    required this.aspect,
    required this.output,
  });

  final String path;
  final CropShape shape;
  final double aspect;
  final double output;

  @override
  State<_CropPage> createState() => _CropPageState();
}

class _CropPageState extends State<_CropPage> {
  ui.Image? _image;

  /// Scale relative to cover: 1 means the picture just fills the frame.
  double _zoom = 1;
  Offset _offset = Offset.zero;

  /// Counted from the picture area's size, known only in build.
  Size _canvas = Size.zero;
  Size _frame = Size.zero;
  double _cover = 1;
  double _minZoom = 0.2;

  double _startZoom = 1;
  Offset _startOffset = Offset.zero;
  Offset _startFocal = Offset.zero;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await File(widget.path).readAsBytes();
      final image = await decodeImageFromList(data);
      if (!mounted) return;
      setState(() => _image = image);
    } catch (_) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  /// Frame and scales for the area's current size.
  void _measure(Size canvas) {
    final image = _image;
    if (image == null || canvas == _canvas) return;
    _canvas = canvas;

    if (widget.shape == CropShape.circle) {
      final d = canvas.shortestSide * 0.62;
      _frame = Size(d, d);
    } else {
      var w = canvas.width * 0.88;
      var h = w * widget.aspect;
      if (h > canvas.height * 0.8) {
        h = canvas.height * 0.8;
        w = h / widget.aspect;
      }
      _frame = Size(w, h);
    }

    final iw = image.width.toDouble();
    final ih = image.height.toDouble();
    _cover = (_frame.width / iw) > (_frame.height / ih)
        ? _frame.width / iw
        : _frame.height / ih;
    final fit =
        (canvas.width / iw < canvas.height / ih
            ? canvas.width / iw
            : canvas.height / ih) *
        0.9;
    _minZoom = (fit / _cover).clamp(0.05, 1.0);
  }

  /// Rectangle the picture lies in now, in area coordinates.
  Rect _imageRect() {
    final image = _image!;
    final w = image.width * _cover * _zoom;
    final h = image.height * _cover * _zoom;
    return Rect.fromLTWH(
      (_canvas.width - w) / 2 + _offset.dx,
      (_canvas.height - h) / 2 + _offset.dy,
      w,
      h,
    );
  }

  Rect _frameRect() => Rect.fromCenter(
    center: Offset(_canvas.width / 2, _canvas.height / 2),
    width: _frame.width,
    height: _frame.height,
  );

  Future<void> _apply() async {
    final image = _image;
    if (image == null) return;
    final frame = _frameRect();
    final scale = widget.output / frame.width;
    final width = (frame.width * scale).round();
    final height = (frame.height * scale).round();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(scale);
    if (widget.shape == CropShape.circle) {
      canvas.clipPath(
        Path()..addOval(Rect.fromLTWH(0, 0, frame.width, frame.height)),
      );
    }
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      _imageRect().shift(-frame.topLeft),
      Paint()..filterQuality = FilterQuality.high,
    );
    final picture = recorder.endRecording();
    final out = await picture.toImage(width, height);
    picture.dispose();
    final data = await out.toByteData(format: ui.ImageByteFormat.png);
    out.dispose();
    if (!mounted || data == null) return;
    Navigator.of(context).pop(data.buffer.asUint8List());
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final image = _image;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  if (image == null) {
                    return const Center(
                      child: BloomSpinner(size: 36, stroke: 4),
                    );
                  }
                  _measure(Size(box.maxWidth, box.maxHeight));
                  return GestureDetector(
                    onScaleStart: (d) {
                      _startZoom = _zoom;
                      _startOffset = _offset;
                      _startFocal = d.localFocalPoint;
                    },
                    onScaleUpdate: (d) => setState(() {
                      _zoom = (_startZoom * d.scale).clamp(_minZoom, 3.0);
                      _offset =
                          _startOffset + (d.localFocalPoint - _startFocal);
                    }),
                    child: CustomPaint(
                      size: Size(box.maxWidth, box.maxHeight),
                      painter: _CropPainter(
                        image: image,
                        imageRect: _imageRect(),
                        frame: _frameRect(),
                        circle: widget.shape == CropShape.circle,
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(
                        context.l.profileZoom((_zoom * 100).round()),
                        style: theme.bodySmall,
                      ),
                      Expanded(
                        child: Slider(
                          value: _zoom.clamp(_minZoom, 3.0),
                          min: _minZoom,
                          max: 3,
                          onChanged: image == null
                              ? null
                              : (v) => setState(() => _zoom = v),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: BloomButton(
                          label: context.l.commonBack,
                          color: t.text2,
                          onTap: () => Navigator.of(context).pop(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: BloomButton(
                          label: context.l.commonApply,
                          tone: ButtonTone.accent,
                          onTap: image == null ? null : _apply,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The picture, dimming around the frame and the frame itself.
class _CropPainter extends CustomPainter {
  const _CropPainter({
    required this.image,
    required this.imageRect,
    required this.frame,
    required this.circle,
  });

  final ui.Image image;
  final Rect imageRect;
  final Rect frame;
  final bool circle;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      imageRect,
      Paint()..filterQuality = FilterQuality.medium,
    );

    // Dims all but the frame: an even-odd hole.
    final hole = Path()
      ..addRect(full)
      ..addPath(
        circle ? (Path()..addOval(frame)) : (Path()..addRect(frame)),
        Offset.zero,
      )
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      hole,
      Paint()..color = Colors.black.withValues(alpha: 0.62),
    );

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: 0.75);
    if (circle) {
      canvas.drawOval(frame, line);
      return;
    }
    canvas.drawRect(frame, line);

    // Corners, showing where to drag the picture.
    final corner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.white;
    const len = 12.0;
    for (final (point, sx, sy) in [
      (frame.topLeft, 1.0, 1.0),
      (frame.topRight, -1.0, 1.0),
      (frame.bottomLeft, 1.0, -1.0),
      (frame.bottomRight, -1.0, -1.0),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(point.dx, point.dy + sy * len)
          ..lineTo(point.dx, point.dy)
          ..lineTo(point.dx + sx * len, point.dy),
        corner,
      );
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.image != image ||
      old.imageRect != imageRect ||
      old.frame != frame ||
      old.circle != circle;
}
