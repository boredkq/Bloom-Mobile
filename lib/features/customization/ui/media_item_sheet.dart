/// Sheet for one library picture: preview, where it's applied, cover mode,
/// background blur and dim, delete. Blur and dim are a property of the picture
/// itself, not a shared background setting (see [MediaItem.blur]).
///
/// Settings under the list show only when they have something to apply to: the
/// mode when it's a cover, effects when it's the background.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../custom_store.dart';
import '../media_store.dart';
import 'custom_sheet.dart';
import 'custom_widgets.dart';

Future<void> showMediaItemSheet(BuildContext context, MediaItem item) =>
    showBloomSheetChild<void>(
      context: context,
      header: CustSheetPreview(srcs: [item.src]),
      footer: _DeleteButton(id: item.id),
      child: _MediaItemBody(id: item.id),
    );

/// How long a section under the list takes to open.
const Duration _kReveal = Duration(milliseconds: 220);

class _MediaItemBody extends ConsumerWidget {
  const _MediaItemBody({required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    MediaItem? item;
    for (final it in ref.watch(mediaLibProvider)) {
      if (it.id == id) item = it;
    }
    // Only the button below deletes a picture and the sheet closes first, so an
    // empty body is just insurance for a frame.
    if (item == null) return const SizedBox.shrink();

    final targets = ref.watch(customProvider);
    final mode = ref.watch(coverModeProvider);
    final lib = ref.read(mediaLibProvider.notifier);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetCaption(context.l.custApplyTo),
        SheetPanel(
          children: [
            for (final ctx in CustomCtx.values) ...[
              if (ctx != CustomCtx.values.first) sheetDivider(indent: 60),
              // A tap places or clears the picture here; the tick means it's
              // there.
              SheetRow(
                icon: customCtxIcon(ctx),
                label: _ctxLabel(context, ctx),
                trailing: targets.of(ctx) == item.id ? const SheetTick() : null,
                onTap: () => ref
                    .read(customProvider.notifier)
                    .toggle(ctx, id, targets.of(ctx) != id),
              ),
            ],
          ],
        ),
        _Reveal(
          show: targets.cover == item.id,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetCaption(context.l.custCoverMode),
              for (final m in CoverMode.values)
                SheetOptionTile(
                  icon: switch (m) {
                    CoverMode.always => Bi.infinite,
                    CoverMode.fallback => Bi.shieldCheck,
                  },
                  label: switch (m) {
                    CoverMode.always => context.l.custCoverModeAlways,
                    CoverMode.fallback => context.l.custCoverModeFallback,
                  },
                  active: m == mode,
                  onTap: () => ref.read(coverModeProvider.notifier).set(m),
                ),
            ],
          ),
        ),
        _Reveal(
          show: targets.bg == item.id,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetCaption(context.l.custEffects),
              SheetPanel(
                children: [
                  _SliderRow(
                    label: context.l.custBlur,
                    value: item.blur,
                    max: kBgBlurMax,
                    suffix: 'px',
                    onChanged: (v) => lib.setBlur(id, v),
                  ),
                  _SliderRow(
                    label: context.l.custDim,
                    value: item.dim,
                    max: kBgDimMax,
                    suffix: '%',
                    onChanged: (v) => lib.setDim(id, v),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _ctxLabel(BuildContext context, CustomCtx ctx) => switch (ctx) {
    CustomCtx.bg => context.l.custCtxBg,
    CustomCtx.cover => context.l.custCtxCover,
    CustomCtx.slider => context.l.custCtxSlider,
  };
}

/// A section that slides out under the list and back. It collapses by height
/// rather than jumping, or the sheet would jerk by a whole block.
class _Reveal extends StatelessWidget {
  const _Reveal({required this.show, required this.child});

  final bool show;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSize(
    duration: _kReveal,
    curve: Curves.easeOutCubic,
    alignment: Alignment.topCenter,
    child: AnimatedSwitcher(
      duration: _kReveal,
      child: show ? child : const SizedBox(width: double.infinity),
    ),
  );
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.max,
    required this.suffix,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double max;
  final String suffix;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    return Padding(
      // Rows step by 56: the caption on top, the track below.
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: theme.bodyMedium)),
              Text('${value.round()}$suffix', style: theme.bodyMedium),
            ],
          ),
          const SizedBox(height: 2),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: SliderComponentShape.noOverlay,
              activeTrackColor: t.accent,
              inactiveTrackColor: t.track,
              thumbColor: t.accent,
            ),
            child: SizedBox(
              height: 24,
              child: Slider(
                value: value.clamp(0, max),
                max: max,
                // A step of one: this is a setting's slider, not the player's
                // bar, and whole percent and pixels read fine.
                divisions: max.round(),
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeleteButton extends ConsumerWidget {
  const _DeleteButton({required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) => CustSheetDelete(
    onTap: () {
      Navigator.of(context).pop();
      removeMedia(ref.read, id);
    },
  );
}
