/// Library tab of customization: a grid of own pictures and an add sheet (a
/// link or a gallery photo) under the plus. Where a picture applies is chosen
/// in its own sheet ([showMediaItemSheet]): first a picture, then the
/// Background, Cover and Slider ticks. Fewer states and nothing to forget. A
/// context tile on top can also clear a picture.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/cover_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/pressable.dart';
import '../custom_store.dart';
import '../media_store.dart';
import 'custom_widgets.dart';
import 'media_item_sheet.dart';

class MediaLibraryPane extends ConsumerWidget {
  const MediaLibraryPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(mediaLibProvider);
    return CustomPane(
      empty: context.l.custLibraryEmpty,
      itemCount: items.length,
      itemBuilder: (_, i) => _MediaCard(item: items[i]),
    );
  }
}

/// The tab's plus: a sheet with a link field and an Attach photo item.
Future<void> showAddMediaSheet(BuildContext context, WidgetRef ref) async {
  final l10n = context.l;
  final picked = await showBloomSheetChild<Object>(
    context: context,
    child: SheetAddForm(
      hint: 'https://example.com/image.gif',
      icon: Bi.gallery,
      label: l10n.custAttachPhoto,
    ),
  );
  if (picked == null) return;
  if (picked is String) {
    final ok = ref.read(mediaLibProvider.notifier).addUrl(picked);
    toaster.show(
      ok ? l10n.custAdded : l10n.custBadUrl,
      kind: ok ? ToastKind.success : ToastKind.warn,
    );
    return;
  }
  final added = await ref.read(mediaLibProvider.notifier).addFromGallery();
  if (added == 0) return; // cancelled or denied, so quietly
  toaster.show(l10n.custFilesAdded(added), kind: ToastKind.success);
}

class _MediaCard extends ConsumerWidget {
  const _MediaCard({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final image = coverImage(item.src);
    final usage = ref.watch(mediaUsageProvider(item.id));
    final tile = Pressable(
      onTap: () => showMediaItemSheet(context, item),
      scale: 0.97,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(t.radius * 0.85),
        child: DecoratedBox(
          decoration: BoxDecoration(color: t.pill),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (image != null)
                Image(
                  image: image,
                  fit: BoxFit.cover,
                  // A broken link mustn't break the grid: an empty tile stays,
                  // visible and openable for deleting.
                  errorBuilder: (_, _, _) => Center(
                    child: BloomIcon(Bi.gallery, size: 22, color: t.muted),
                  ),
                ),
              // Where a picture applies, as icons over it. An empty list isn't
              // drawn: a free picture's tile is clean.
              if (usage.isNotEmpty) Center(child: _UsageBadge(usage: usage)),
            ],
          ),
        ),
      ),
    );
    // A second way to place a picture: drag it to a context tile on top. It
    // drags on a long press: a plain move over the grid stays a scroll.
    return LongPressDraggable<MediaItem>(
      data: item,
      hapticFeedbackOnStart: true,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _DragGhost(src: item.src),
      // Source card while being dragged.
      childWhenDragging: Opacity(opacity: 0.45, child: tile),
      child: tile,
    );
  }
}

/// Preview following the finger: 72×48 centred on the touch point.
class _DragGhost extends StatelessWidget {
  const _DragGhost({required this.src});

  static const Size size = Size(72, 48);

  final String src;

  @override
  Widget build(BuildContext context) {
    final image = coverImage(src);
    return Transform.translate(
      offset: Offset(-size.width / 2, -size.height / 2),
      child: Container(
        width: size.width,
        height: size.height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: context.bloom.pill,
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [
            BoxShadow(
              color: Color(0x80000000),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: image == null
            ? null
            : Image(
                image: image,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.expand(),
              ),
      ),
    );
  }
}

/// Plate saying where this picture stands, an icon per taken context. The same
/// glass as a platform badge in a track row: there's a picture below, and a
/// solid plate reads as a patch.
class _UsageBadge extends StatelessWidget {
  const _UsageBadge({required this.usage});

  final List<CustomCtx> usage;

  @override
  Widget build(BuildContext context) => GlassSurface(
    shape: BorderRadius.circular(10),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final ctx in usage) ...[
            if (ctx != usage.first) const SizedBox(width: 8),
            BloomIcon(customCtxIcon(ctx), size: 15, color: Colors.white),
          ],
        ],
      ),
    ),
  );
}
