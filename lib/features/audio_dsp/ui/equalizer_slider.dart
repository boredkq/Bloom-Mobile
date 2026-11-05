import 'package:flutter/material.dart';

import '../../../app/theme/bloom_theme.dart';
import '../audio_dsp_models.dart';

/// Single vertical slider for an EQ frequency band.
class EqualizerBandSlider extends StatelessWidget {
  const EqualizerBandSlider({
    super.key,
    required this.label,
    required this.level,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final int level; // -100 to 100
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final db = AudioPresets.levelToDb(level);
    final dbText = db == 0
        ? '0'
        : db > 0
            ? '+${db.toStringAsFixed(1)}'
            : db.toStringAsFixed(1);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          dbText,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: enabled && level != 0 ? t.accent : t.muted,
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3.5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: enabled ? t.accent : t.muted.withValues(alpha: 0.4),
                inactiveTrackColor: t.ovlLine,
                thumbColor: enabled ? t.accent : t.muted,
                overlayColor: t.accent.withValues(alpha: 0.15),
              ),
              child: Slider(
                value: level.toDouble(),
                min: -100,
                max: 100,
                onChanged: enabled
                    ? (val) => onChanged(val.round().clamp(-100, 100))
                    : null,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: enabled ? t.fg : t.muted,
          ),
        ),
      ],
    );
  }
}
