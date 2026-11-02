/// Customization, on one screen: context tiles on top (what stands where),
/// Library and Presets tabs under them with a plus on the right, and the
/// current tab's grid. The plus opens its tab's add sheet.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/cover_store.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/pressable.dart';
import '../custom_store.dart';
import '../media_store.dart';
import 'custom_widgets.dart';
import 'media_library_pane.dart';
import 'presets_pane.dart';
import '../../../shared/ui/subpage_header.dart';
import '../../../shared/ui/big_tabs.dart';
import '../../../shared/ui/atoms.dart';

enum _Pane { library, presets }

/// Tab change: a slide from the side switched to, with a fade.
const Duration _kPaneSwitch = Duration(milliseconds: 260);

class CustomizationScreen extends ConsumerStatefulWidget {
  const CustomizationScreen({super.key});

  @override
  ConsumerState<CustomizationScreen> createState() =>
      _CustomizationScreenState();
}

class _CustomizationScreenState extends ConsumerState<CustomizationScreen> {
  _Pane _pane = _Pane.library;

  /// Which way it switched: 1 right (to presets), -1 left.
  double _dir = 1;

  void _pick(_Pane pane) {
    if (pane == _pane) return;
    setState(() {
      _dir = pane.index > _pane.index ? 1 : -1;
      _pane = pane;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return SubPage(
      title: context.l.stCustom,
      onBack: () => context.go('/settings'),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: _CtxTiles(),
          ),
          // Line between tiles and tabs.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Divider(height: 1, thickness: 1, color: t.ovlBg),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                PillTabs(
                  labels: [context.l.custLibrary, context.l.custPresets],
                  index: _pane.index,
                  onPick: (i) => _pick(_Pane.values[i]),
                ),
                const Spacer(),
                CircleIconButton(
                  icon: Bi.add,
                  size: 40,
                  iconSize: 22,
                  background: Colors.transparent,
                  color: context.bloom.text2,
                  onTap: () => switch (_pane) {
                    _Pane.library => showAddMediaSheet(context, ref),
                    _Pane.presets => showAddPresetSheet(context, ref),
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: _kPaneSwitch,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeOutCubic,
              layoutBuilder: (current, previous) => Stack(
                fit: StackFit.expand,
                children: [...previous, ?current],
              ),
              // Only the new tab slides in, the old just fades: the leaving one
              // sliding the same way would read as a counter-move.
              transitionBuilder: (child, animation) {
                final incoming = child.key == ValueKey(_pane);
                return FadeTransition(
                  opacity: animation,
                  child: incoming
                      ? SlideTransition(
                          position: Tween(
                            begin: Offset(0.06 * _dir, 0),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        )
                      : child,
                );
              },
              child: KeyedSubtree(
                key: ValueKey(_pane),
                child: switch (_pane) {
                  _Pane.library => const MediaLibraryPane(),
                  _Pane.presets => const PresetsPane(),
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Context tiles: the context's picture at half opacity with an icon on top. A
/// tap clears the picture.
class _CtxTiles extends StatelessWidget {
  const _CtxTiles();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final ctx in CustomCtx.values) ...[
        if (ctx != CustomCtx.values.first) const SizedBox(width: 8),
        Expanded(child: _CtxTile(ctx: ctx)),
      ],
    ],
  );
}

class _CtxTile extends ConsumerWidget {
  const _CtxTile({required this.ctx});

  final CustomCtx ctx;

  /// Tile height.
  static const double height = 58;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final src = ref.watch(customSrcProvider(ctx));
    final image = coverImage(src);
    // A library picture can be dropped on a tile to stand here. While a finger
    // is over the tile, its edge is dashed.
    return DragTarget<MediaItem>(
      onAcceptWithDetails: (details) {
        ref.read(customProvider.notifier).set(ctx, details.data.id);
        toaster.show(switch (ctx) {
          CustomCtx.bg => context.l.custBgUpdated,
          CustomCtx.cover => context.l.custCoverUpdated,
          CustomCtx.slider => context.l.custSliderUpdated,
        }, kind: ToastKind.success);
      },
      builder: (context, candidates, _) => Stack(
        children: [
          _tile(context, ref, t, src, image),
          if (candidates.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _DashedRRect(
                    color: t.text.withValues(alpha: 0.62),
                    radius: t.radius * 1.3,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    WidgetRef ref,
    BloomTokens t,
    String? src,
    ImageProvider? image,
  ) {
    return Pressable(
      onTap: src == null
          ? null
          : () {
              ref.read(customProvider.notifier).set(ctx, null);
              toaster.show(switch (ctx) {
                CustomCtx.bg => context.l.custBgRemoved,
                CustomCtx.cover => context.l.custCoverRemoved,
                CustomCtx.slider => context.l.custSliderRemoved,
              });
            },
      scale: 0.97,
      child: ClipRRect(
        // Rounding as on settings group cards: at 0.75 of the radius these read
        // almost square.
        borderRadius: BorderRadius.circular(t.radius * 1.3),
        child: SizedBox(
          height: height,
          child: ColoredBox(
            color: t.pill,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (image != null)
                  Opacity(
                    opacity: 0.5,
                    child: Image(
                      image: image,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.expand(),
                    ),
                  ),
                Center(
                  child: BloomIcon(
                    customCtxIcon(ctx),
                    size: 22,
                    // Over a picture the icon is white with a shadow, readable
                    // on anything; on an empty tile it's muted.
                    color: image == null ? t.text2 : Colors.white,
                    shadows: image == null
                        ? null
                        : const [
                            Shadow(color: Color(0xA6000000), blurRadius: 3),
                          ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dashed edge of a tile a picture is held over: 2 px inside the tile rather
/// than outside, to stay off its neighbours.
class _DashedRRect extends CustomPainter {
  const _DashedRRect({required this.color, required this.radius});

  final Color color;
  final double radius;

  static const double stroke = 2;
  static const double dash = 6;
  static const double gap = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + gap) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRect old) =>
      old.color != color || old.radius != radius;
}
