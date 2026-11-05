import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../app/theme/bloom_theme.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/pressable.dart';

/// Animated radar pulse / concentric ripple circle for listening state.
class ListeningPulseWidget extends StatefulWidget {
  const ListeningPulseWidget({
    super.key,
    required this.isListening,
    required this.isIdentifying,
    required this.onTap,
  });

  final bool isListening;
  final bool isIdentifying;
  final VoidCallback onTap;

  @override
  State<ListeningPulseWidget> createState() => _ListeningPulseWidgetState();
}

class _ListeningPulseWidgetState extends State<ListeningPulseWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    if (widget.isListening || widget.isIdentifying) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(ListeningPulseWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.isListening || widget.isIdentifying) && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isListening && !widget.isIdentifying && _controller.isAnimating) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final accentColor = t.accent;

    return Center(
      child: SizedBox(
        width: 200,
        height: 200,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return CustomPaint(
              painter: _PulsePainter(
                progress: _controller.value,
                isListening: widget.isListening,
                isIdentifying: widget.isIdentifying,
                color: accentColor,
              ),
              child: child,
            );
          },
          child: Center(
            child: Pressable(
              onTap: widget.onTap,
              scaleFactor: 0.94,
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.isListening || widget.isIdentifying
                      ? accentColor
                      : t.surface,
                  boxShadow: [
                    BoxShadow(
                      color: (widget.isListening || widget.isIdentifying
                              ? accentColor
                              : Colors.black)
                          .withValues(alpha: 0.35),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ],
                  border: Border.all(
                    color: widget.isListening || widget.isIdentifying
                        ? accentColor.withValues(alpha: 0.8)
                        : t.ovlLine,
                    width: 2,
                  ),
                ),
                child: Center(
                  child: widget.isIdentifying
                      ? SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              t.bg,
                            ),
                          ),
                        )
                      : BloomIcon(
                          Bi.soundwaveBold,
                          size: 38,
                          color: widget.isListening ? t.bg : t.fg,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter({
    required this.progress,
    required this.isListening,
    required this.isIdentifying,
    required this.color,
  });

  final double progress;
  final bool isListening;
  final bool isIdentifying;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (!isListening && !isIdentifying) return;

    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;
    const waveCount = 3;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    for (var i = 0; i < waveCount; i++) {
      final waveProgress = (progress + (i / waveCount)) % 1.0;
      final radius = 48.0 + (maxRadius - 48.0) * waveProgress;
      final opacity = (1.0 - waveProgress).clamp(0.0, 1.0) * 0.6;

      paint.color = color.withValues(alpha: opacity);
      canvas.drawCircle(center, radius, paint);

      if (isListening) {
        final fillPaint = Paint()
          ..style = PaintingStyle.fill
          ..color = color.withValues(alpha: opacity * 0.15);
        canvas.drawCircle(center, radius, fillPaint);
      }
    }

    if (isIdentifying) {
      final sweepPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..shader = SweepGradient(
          colors: [
            color.withValues(alpha: 0.0),
            color.withValues(alpha: 0.8),
          ],
          transform: GradientRotation(progress * 2 * math.pi),
        ).createShader(Rect.fromCircle(center: center, radius: 56));
      canvas.drawCircle(center, 56, sweepPaint);
    }
  }

  @override
  bool shouldRepaint(_PulsePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.isListening != isListening ||
      oldDelegate.isIdentifying != isIdentifying;
}
