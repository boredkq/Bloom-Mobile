/// Скелетоны загрузки: серые плашки в раскладке того, что сейчас грузится.
///
/// Полоски прогресса на экранах нет намеренно — заготовка держит будущую
/// высоту, поэтому выдача не «прыгает», когда ответ приходит.
///
/// Мигает не каждая плашка по отдельности, а всё поддерево целиком
/// ([SkeletonPulse]): один контроллер на экран и ни одного рассинхрона между
/// соседними плашками.
library;

import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';

/// Плашка-заготовка. [width] `null` — занять всю доступную ширину.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.radius,
    this.circle = false,
  });

  final double? width;
  final double height;
  final double? radius;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: t.iconBg,
        borderRadius: BorderRadius.circular(
          circle ? height / 2 : radius ?? t.radius * 0.72,
        ),
      ),
    );
  }
}

/// Плашка на месте строки текста: скругление по высоте, ширина — доля от
/// доступной, чтобы «строки» не выглядели одинаковой линейкой.
class SkeletonLine extends StatelessWidget {
  const SkeletonLine({super.key, required this.widthFactor, this.height = 12});

  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: SkeletonBox(height: height, radius: height / 2),
    );
  }
}

/// Общее мигание для поддерева заготовок.
class SkeletonPulse extends StatefulWidget {
  const SkeletonPulse({super.key, required this.child});

  final Widget child;

  @override
  State<SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<SkeletonPulse>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..repeat(reverse: true);

  late final _opacity = Tween(
    begin: 1.0,
    end: 0.45,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Не ловит тапы: под заготовкой ничего нажимаемого нет, но и «мёртвых»
    // касаний по ней быть не должно.
    return IgnorePointer(
      child: FadeTransition(opacity: _opacity, child: widget.child),
    );
  }
}

/// Ширины «строк» подписей — по кругу, чтобы плашки не выстраивались в
/// одинаковую линейку.
const List<double> _titleWidths = [0.62, 0.48, 0.71, 0.55];
const List<double> _subWidths = [0.34, 0.42, 0.28, 0.38];

/// Плашка на месте [TrackRow]: те же отступы и обложка 48, поэтому высота
/// строки совпадает с настоящей.
class TrackRowSkeleton extends StatelessWidget {
  const TrackRowSkeleton({super.key, required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          const SkeletonBox(width: 48, height: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLine(
                  widthFactor: _titleWidths[index % _titleWidths.length],
                  height: 13,
                ),
                const SizedBox(height: 7),
                SkeletonLine(
                  widthFactor: _subWidths[index % _subWidths.length],
                  height: 11,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const SkeletonBox(width: 30, height: 11, radius: 6),
        ],
      ),
    );
  }
}

/// Плашка на месте [SetCard]/[ArtistCard]: обложка на всю ширину ячейки и две
/// строки подписи (у артиста — одна, как и в карточке без счётчика).
class CardSkeleton extends StatelessWidget {
  const CardSkeleton({super.key, required this.circle, this.width});

  final bool circle;

  /// `null` — на всю ширину ячейки сетки; число — фиксированная ширина
  /// карточки в карусели.
  final double? width;

  @override
  Widget build(BuildContext context) {
    final content = LayoutBuilder(
      builder: (context, box) => Column(
        crossAxisAlignment: circle
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          SkeletonBox(
            width: box.maxWidth,
            height: box.maxWidth,
            circle: circle,
          ),
          const SizedBox(height: 10),
          SkeletonBox(width: box.maxWidth * (circle ? 0.7 : 0.8), height: 12),
          if (!circle) ...[
            const SizedBox(height: 6),
            SkeletonBox(width: box.maxWidth * 0.5, height: 10),
          ],
        ],
      ),
    );
    return width == null ? content : SizedBox(width: width, child: content);
  }
}

/// Лента заготовок вместо [EntityCarousel]: карточек ровно столько, чтобы
/// ряд был заполнен до правого края.
class CarouselSkeleton extends StatelessWidget {
  const CarouselSkeleton({
    super.key,
    required this.height,
    required this.card,
    this.circle = false,
  });

  final double height;
  final double card;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final count = (width / (card + 12)).ceil();

    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, _) => CardSkeleton(circle: circle, width: card),
      ),
    );
  }
}
