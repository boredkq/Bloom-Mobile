/// Вкладка «Библиотека» страницы «Кастомизация» — сетка своих картинок и
/// шторка добавления (ссылка или фото из галереи) под плюсиком.
///
/// Куда картинка применена, выбирается не здесь, а в её собственной шторке
/// ([showMediaItemSheet]): на ПК сперва выбирают карточку контекста, потом
/// картинку, а тут наоборот — сперва картинку, потом галочки «Фон / Обложка /
/// Слайдер». Меньше состояний и нечего забыть выбрать. Снять картинку можно и
/// плиткой контекста наверху страницы — как на ПК.
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
    if (items.isEmpty) {
      return Center(
        child: CenterNote(
          context.l.custLibraryEmpty,
          padding: const EdgeInsets.symmetric(horizontal: 40),
        ),
      );
    }
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 8 + bottomBarsInset(context)),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        // Ландшафтная плитка: обои и есть ландшафт, а квадрат резал бы их
        // посередине ещё в списке.
        childAspectRatio: 4 / 3,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => _MediaCard(item: items[i]),
    );
  }
}

/// Плюсик вкладки: шторка с полем ссылки и пунктом «Приложить фото» — на ПК
/// это строка добавления под «+» и кнопка файлов рядом с ней.
Future<void> showAddMediaSheet(BuildContext context, WidgetRef ref) async {
  final l10n = context.l;
  final messenger = ScaffoldMessenger.of(context);
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
    messenger.toast(
      ok ? l10n.custAdded : l10n.custBadUrl,
      kind: ok ? ToastKind.success : ToastKind.warn,
    );
    return;
  }
  final added = await ref.read(mediaLibProvider.notifier).addFromGallery();
  if (added == 0) return; // отменили или не дали доступ — молчим
  messenger.toast(l10n.custFilesAdded(added), kind: ToastKind.success);
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
                  // Битая ссылка не должна ломать сетку — остаётся пустая
                  // плитка, которую видно и можно открыть, чтобы удалить.
                  errorBuilder: (_, _, _) => Center(
                    child: BloomIcon(Bi.gallery, size: 22, color: t.muted),
                  ),
                ),
              // Куда картинка применена — значками поверх неё. Пустой список
              // не рисуем вовсе: плитка ничем не занятой картинки чистая.
              if (usage.isNotEmpty) Center(child: _UsageBadge(usage: usage)),
            ],
          ),
        ),
      ),
    );
    // Второй способ поставить картинку — перетащить её на плитку контекста
    // наверху страницы, как на ПК. Тянется по долгому нажатию: простое
    // движение пальца по сетке остаётся прокруткой.
    return LongPressDraggable<MediaItem>(
      data: item,
      hapticFeedbackOnStart: true,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _DragGhost(src: item.src),
      // Карточка-источник, пока её тянут, — десктопная `.cz-card.dragging`.
      childWhenDragging: Opacity(opacity: 0.45, child: tile),
      child: tile,
    );
  }
}

/// Превью, летящее за пальцем, — десктопный `cz-drag-ghost`: 72×48 по центру
/// точки касания.
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

/// Плашка «эта картинка стоит вот здесь»: по значку на каждый занятый
/// контекст. Стекло то же, что у бейджа площадки в строке трека, — под ней
/// картинка, и сплошная плашка темы читалась бы заплаткой.
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
