import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/pressable.dart';
import '../audio_dsp_models.dart';
import '../audio_dsp_store.dart';
import 'equalizer_slider.dart';

/// Opens the studio 10-band equalizer and sound effects sheet.
Future<void> showEqualizerSheet(BuildContext context) {
  return showBloomSheetChild<void>(
    context: context,
    header: SheetTitle(
      context.l.eqTitle,
      subtitle: context.l.eqSubtitle,
    ),
    child: const EqualizerSheetContent(),
  );
}

class EqualizerSheetContent extends ConsumerWidget {
  const EqualizerSheetContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final l = context.l;
    final state = ref.watch(audioDspProvider);
    final notifier = ref.read(audioDspProvider.notifier);

    final allPresets = [
      ...AudioPresets.builtIn,
      ...state.customPresets.values,
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Master switch row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  BloomIcon(
                    Bi.eq,
                    size: 24,
                    color: state.enabled ? t.accent : t.muted,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l.eqEnable,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: t.text,
                    ),
                  ),
                ],
              ),
              Switch.adaptive(
                value: state.enabled,
                activeTrackColor: t.accent,
                onChanged: notifier.setEnabled,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Presets chip carousel
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: allPresets.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final preset = allPresets[index];
                final isSelected = state.presetId == preset.id;
                return Pressable(
                  onTap: () => notifier.setPreset(preset.id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? t.accent
                          : t.card.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isSelected ? t.accent : t.ovlLine,
                      ),
                    ),
                    child: Text(
                      preset.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? t.bg : t.text,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // 10-band slider board
          Container(
            height: 190,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: t.card.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: t.ovlLine),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                const count = AudioPresets.bandCount;
                final bandWidth = (constraints.maxWidth / count).clamp(28.0, 48.0);
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < count; i++)
                        SizedBox(
                          width: bandWidth,
                          child: EqualizerBandSlider(
                            label: AudioPresets.bandFrequencyLabels[i],
                            level: state.bandLevels[i],
                            enabled: state.enabled,
                            onChanged: (lvl) => notifier.setBandLevel(i, lvl),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),

          // Bass Boost & Virtualizer cards
          Row(
            children: [
              Expanded(
                child: _EffectCard(
                  title: l.eqBassBoost,
                  value: state.bassBoost,
                  enabled: state.enabled,
                  icon: Bi.soundwaveBold,
                  onChanged: notifier.setBassBoost,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _EffectCard(
                  title: l.eqVirtualizer,
                  value: state.virtualizer,
                  enabled: state.enabled,
                  icon: Bi.musicNoteBold,
                  onChanged: notifier.setVirtualizer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // True-Peak Headroom Guard indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: t.card.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.ovlLine.withValues(alpha: 0.6)),
            ),
            child: Row(
              children: [
                BloomIcon(
                  Bi.checkCircleBold,
                  size: 18,
                  color: t.accent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.eqHeadroomGuard,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: t.text,
                        ),
                      ),
                      Text(
                        '${l.eqSafeGain}: ${state.safeGainDb.toStringAsFixed(1)} dB',
                        style: TextStyle(fontSize: 11, color: t.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Bottom buttons
          Row(
            children: [
              Expanded(
                child: SheetButton(
                  label: l.eqReset,
                  icon: Bi.close,
                  tone: ButtonTone.plate,
                  onTap: notifier.resetToFlat,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SheetButton(
                  label: l.eqSavePreset,
                  icon: Bi.diskette,
                  tone: ButtonTone.plate,
                  onTap: () => _promptSavePreset(context, ref),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _promptSavePreset(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: context.bloom.blockColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(context.l.eqSavePreset),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: context.l.eqPresetNameHint,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text(context.l.commonCancel),
          ),
          TextButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                ref.read(audioDspProvider.notifier).saveCustomPreset(text);
                toaster.show(context.l.eqPresetSaved, kind: ToastKind.success);
              }
              Navigator.of(dialogCtx).pop();
            },
            child: Text(context.l.commonSave),
          ),
        ],
      ),
    );
  }
}

class _EffectCard extends StatelessWidget {
  const _EffectCard({
    required this.title,
    required this.value,
    required this.enabled,
    required this.icon,
    required this.onChanged,
  });

  final String title;
  final int value;
  final bool enabled;
  final BloomGlyph icon;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: t.card.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.ovlLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  BloomIcon(icon, size: 16, color: enabled ? t.accent : t.muted),
                  const SizedBox(width: 6),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: t.text,
                    ),
                  ),
                ],
              ),
              Text(
                '$value%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: enabled && value > 0 ? t.accent : t.muted,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: enabled ? t.accent : t.muted.withValues(alpha: 0.4),
              inactiveTrackColor: t.ovlLine,
              thumbColor: enabled ? t.accent : t.muted,
              overlayColor: t.accent.withValues(alpha: 0.15),
            ),
            child: Slider(
              value: value.toDouble(),
              min: 0,
              max: 100,
              onChanged: enabled ? (val) => onChanged(val.round()) : null,
            ),
          ),
        ],
      ),
    );
  }
}
