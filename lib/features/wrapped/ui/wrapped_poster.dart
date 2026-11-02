/// The review's poster and the button that shares it: 3:4, dark whatever the
/// theme, the theme's accent washing its top. Bloom's mark, the period, the
/// time and the plays, the top five tracks, the top artists as chips.
library;

import 'dart:typed_data' show Uint8List;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../app/theme/bloom_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/cover_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_mark.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../periods.dart';
import '../wrapped_data.dart';
import '../wrapped_format.dart';
import 'poster_image.dart';
import 'wrapped_sheet.dart' show periodTitle;

/// The poster's own box; the picture comes out at twice that, 840 × 1120.
const double _kPosterW = 420;
const double _kPosterH = 560;
const double _kPicture = 2;
const double _kRadius = 30;
const Color _kDark = Color(0xFF0D0D0D);

class WrappedPosterCard extends StatefulWidget {
  const WrappedPosterCard({super.key, required this.data, required this.width});

  final WrappedData data;
  final double width;

  @override
  State<WrappedPosterCard> createState() => _WrappedPosterCardState();
}

class _WrappedPosterCardState extends State<WrappedPosterCard> {
  final GlobalKey _shot = GlobalKey();
  bool _busy = false;

  Future<void> _share() async {
    setState(() => _busy = true);
    final l = context.l;
    final range = widget.data.range;
    final locale = Localizations.localeOf(context).languageCode;
    var ok = false;
    try {
      // The picture has what's drawn: a cover not in yet would be a hole.
      await _precacheCovers();
      final png = await _capture();
      if (png != null) {
        ok = await shareImageBytes(
          png,
          filename: 'bloom-wrapped-${periodKey(range)}.png',
          text:
              '${periodTitle(l, range.kind)} · ${periodDatesLabel(range, locale)}',
        );
      }
    } catch (_) {
      // Reported below.
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) toaster.show(l.wrShareFail);
  }

  Future<void> _precacheCovers() async {
    for (final row in widget.data.topTracks) {
      final image = coverImage(row.track.cover);
      if (image == null || !mounted) continue;
      await precacheImage(image, context, onError: (_, _) {});
    }
  }

  Future<Uint8List?> _capture() async {
    final boundary =
        _shot.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: _kPicture);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: _kPosterW / _kPosterH,
            child: FittedBox(
              child: RepaintBoundary(
                key: _shot,
                child: SizedBox(
                  width: _kPosterW,
                  height: _kPosterH,
                  child: _Poster(data: widget.data),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          BloomButton(
            label: context.l.wrShareSave,
            icon: Bi.downloadMinimalistic,
            tone: ButtonTone.plate,
            overlay: true,
            height: 44,
            busy: _busy,
            onTap: _share,
          ),
        ],
      ),
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.data});

  final WrappedData data;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final l = context.l;
    final locale = Localizations.localeOf(context).languageCode;
    final tracks = data.topTracks.take(5).toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(_kRadius),
      child: Container(
        color: _kDark,
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_kRadius),
          border: Border.all(color: const Color(0x1AFFFFFF)),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The accent, corner to corner, over the top half; it fades into
            // the dark.
            Align(
              alignment: Alignment.topCenter,
              child: Container(
                height: _kPosterH * 0.52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      t.accent.withValues(alpha: 0.5),
                      t.accent2.withValues(alpha: 0.5),
                    ],
                  ),
                ),
                foregroundDecoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [_kDark.withValues(alpha: 0), _kDark],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      BloomMark(size: 17, color: Colors.white, opacity: 0.85),
                      const SizedBox(width: 8),
                      Text(
                        'BLOOM',
                        style: bloomText(
                          size: 12,
                          weight: 700,
                          color: Colors.white.withValues(alpha: 0.6),
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 13),
                  _Line(periodTitle(l, data.range.kind), size: 28, bold: true),
                  const SizedBox(height: 3),
                  _Line(
                    periodDatesLabel(data.range, locale),
                    size: 13,
                    alpha: 0.55,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      _Number(
                        value: fmtListenTime(l, data.seconds),
                        label: l.wrCardTime,
                      ),
                      _Number(
                        value: fmtCount(locale, data.plays),
                        label: l.wrPlaysWord(data.plays),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _Line(
                    l.wrCardTopTracks.toUpperCase(),
                    size: 11,
                    bold: true,
                    alpha: 0.45,
                  ),
                  const SizedBox(height: 10),
                  for (final (i, row) in tracks.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Cover(url: row.track.cover, size: 36, radius: 8),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _Line(
                                  '${i + 1}. ${row.track.name}',
                                  size: 13,
                                  bold: true,
                                ),
                                const SizedBox(height: 3),
                                _Line(row.track.artist, size: 11, alpha: 0.45),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (data.topArtists.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _Line(
                      l.wrCardTopArtists.toUpperCase(),
                      size: 11,
                      bold: true,
                      alpha: 0.45,
                    ),
                    const SizedBox(height: 10),
                    // As many chips as fit on one line: the rest wrap below it
                    // and are cut off.
                    SizedBox(
                      height: 30,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        clipBehavior: Clip.hardEdge,
                        children: [
                          for (final a in data.topArtists.take(5))
                            BloomTag(text: a.name, color: Colors.white),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One of the two big numbers. A long time shrinks to fit its half rather than
/// lose its end.
class _Number extends StatelessWidget {
  const _Number({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 29,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: bloomText(size: 24, weight: 700, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 3),
            _Line(label, size: 11, alpha: 0.45),
          ],
        ),
      ),
    );
  }
}

/// A line of white text that ends in an ellipsis.
class _Line extends StatelessWidget {
  const _Line(
    this.text, {
    required this.size,
    this.bold = false,
    this.alpha = 1,
  });

  final String text;
  final double size;
  final bool bold;
  final double alpha;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: bloomText(
      size: size,
      weight: bold ? 700 : 400,
      color: Colors.white.withValues(alpha: alpha),
    ),
  );
}
