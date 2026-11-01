/// Детали шторок «Кастомизации» — картинки библиотеки и пресета. Вид с макета
/// пользователя, а не общий вид шторок: фон шторки ровный, без картинки,
/// блоки залиты плашкой темы без рамки, отступ от края у превью и у блоков
/// один, «Удалить» прибито к низу.
library;

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/cover_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/pressable.dart';

/// Отступ превью и блоков от края шторки — на макете они стоят по одной
/// линии с кнопкой «назад» страницы под шторкой.
const double kCustSheetEdge = 16;

/// Шапка шторки: картинка во всю ширину, по краям — как блоки ниже.
///
/// Картинок бывает несколько (у пресета — по одной на занятый контекст): тогда
/// их листают пальцем, точки снизу показывают, сколько всего.
class CustSheetPreview extends StatefulWidget {
  const CustSheetPreview({super.key, required this.srcs});

  /// Высота превью — с макета.
  static const double height = 180;

  final List<String> srcs;

  @override
  State<CustSheetPreview> createState() => _CustSheetPreviewState();
}

class _CustSheetPreviewState extends State<CustSheetPreview> {
  final _pages = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final srcs = widget.srcs;
    return Padding(
      padding: const EdgeInsets.fromLTRB(kCustSheetEdge, 4, kCustSheetEdge, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(t.radius),
        child: SizedBox(
          height: CustSheetPreview.height,
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(color: t.pill),
            child: switch (srcs.length) {
              // Пресет, у которого все картинки удалены, — значок коробки.
              0 => Center(
                child: BloomIcon(Bi.boxMinimalistic, size: 30, color: t.muted),
              ),
              1 => _FitImage(src: srcs.first),
              _ => Stack(
                fit: StackFit.expand,
                children: [
                  PageView.builder(
                    controller: _pages,
                    itemCount: srcs.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (_, i) => _FitImage(src: srcs[i]),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 10,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < srcs.length; i++) ...[
                          if (i > 0) const SizedBox(width: 6),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(
                                alpha: i == _index ? 0.9 : 0.35,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            },
          ),
        ),
      ),
    );
  }
}

/// Картинка превью: вписана целиком, а не обрезана — вертикальный скриншот и
/// широкие обои видны полностью. Пустые поля по бокам (или сверху и снизу)
/// закрывает та же картинка, растянутая и размытая, — так на макете.
class _FitImage extends StatelessWidget {
  const _FitImage({required this.src});

  /// Размытие подложки полей.
  static const double blur = 24;

  /// Притемнение подложки: размытая копия не должна спорить с самим фото.
  static const double dim = 0.35;

  final String src;

  @override
  Widget build(BuildContext context) {
    final image = coverImage(src);
    if (image == null) return const SizedBox.expand();
    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(
            sigmaX: blur,
            sigmaY: blur,
            tileMode: TileMode.decal,
          ),
          child: Image(
            image: image,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.expand(),
          ),
        ),
        ColoredBox(color: Colors.black.withValues(alpha: dim)),
        Image(
          image: image,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => Center(
            child: Text(
              context.l.custImageGone,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ],
    );
  }
}

/// Подпись секции над блоком.
class CustSheetLabel extends StatelessWidget {
  const CustSheetLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      kCustSheetEdge + 2,
      16,
      kCustSheetEdge,
      8,
    ),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: context.bloom.text2),
    ),
  );
}

/// Блок секции: плашка темы без рамки — цвет снят с макета (#1a1a1a на фоне
/// #0a0a0a).
class CustSheetBlock extends StatelessWidget {
  const CustSheetBlock({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kCustSheetEdge),
      child: Material(
        color: t.pill,
        borderRadius: BorderRadius.circular(t.radius),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

/// Where a row's text starts: its padding, icon box and gap.
const double kCustRowText = 68;

/// Строка блока: значок, название и справа [trailing] (галочка у контекстов).
class CustSheetRow extends StatelessWidget {
  const CustSheetRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final BloomGlyph icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Pressable(
      onTap: onTap,
      scale: 0.98,
      child: SizedBox(
        height: 64,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              SizedBox(
                width: 38,
                child: BloomIcon(icon, size: 20, color: t.iconFg),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// Кнопка, прибитая к низу шторки («Удалить»), как на макете: без заливки,
/// тонкая рамка и белая подпись по центру.
class CustSheetFooterButton extends StatelessWidget {
  const CustSheetFooterButton({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(kCustSheetEdge),
    child: BloomButton(
      label: label,
      tone: ButtonTone.line,
      pill: false,
      height: 49,
      onTap: onTap,
    ),
  );
}
