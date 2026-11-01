/// Настройки плеера — пока одна вкладка десктопного раздела: «Анимации».
///
/// Порт `AnimCards` из `settings/ui/sections/ViewSection.tsx`. Поверхностей у
/// нас две (на ПК их три — там ещё полноэкранный режим), у каждой своя
/// карточка: коробки разного размера, и одна настройка на обеих заставляла бы
/// выбирать между «красиво в плеере» и «не рябит над таб-баром».
///
/// Внутри карточки две независимые строки — обложка и подпись: слайд обложки
/// при спокойном затухании текста (и наоборот) — рабочее сочетание, а не
/// недонастройка.
///
/// Сами кнопки выбора на странице НЕ стоят: развёрнутыми тремя блоками они
/// занимали два экрана прокрутки. Остались три строки «название — что сейчас
/// выбрано», а варианты открываются нижней шторкой — ровно как «Тема» и «Вид
/// таб-бара» в «Интерфейсе». Шторка от выбора не закрывается: настроек в ней
/// две-три, и они настраиваются подряд.
///
/// Значки вариантов рисуем сами: на ПК это три крошечных SVG (перечёркнутый
/// круг, две плитки рядом, две плитки внахлёст), в шрифте Solar таких нет.
///
/// Вид самой карточки над таб-баром настраивается не тут, а на своей странице
/// («Мини плеер»): настроек у неё шесть, и в конце этой страницы их приходилось
/// искать прокруткой. Осталась только строка «Мини-плеер» в «Смене трека» —
/// переходы обеих поверхностей настраиваются сравнением одна с другой.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../features/customization/custom_store.dart';
import '../../../features/lyrics/lyrics_store.dart';
import '../../../features/player/play_button_store.dart';
import '../../../features/player/player_bg_store.dart';
import '../../../features/player/player_style_store.dart';
import '../../../features/player/player_view_store.dart';
import '../../../features/player/slider_style_store.dart';
import '../../../features/player/track_anim_store.dart';
import '../../../features/player/ui/play_button.dart';
import '../../../features/player/ui/slider_shapes.dart';
import '../../../features/player/ui/vinyl_disc.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/glass.dart';
import '../../../shared/ui/pressable.dart';
import '../../../shared/ui/subpage_header.dart';
import '../../../shared/util/format.dart';
import 'settings_rows.dart';
import 'settings_sheets.dart';

class PlayerSettingsScreen extends ConsumerWidget {
  const PlayerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final anim = ref.watch(trackAnimProvider);
    final lyricsMode = ref.watch(lyricsPrefsProvider.select((p) => p.mode));
    final style = ref.watch(playerStyleProvider);
    final playShape = ref.watch(playButtonShapeProvider);
    final align = ref.watch(titleAlignProvider);
    final slider = ref.watch(sliderStyleProvider);
    final bg = ref.watch(playerBgProvider);
    final coverFx = ref.watch(coverBgFxProvider);
    final l = context.l;

    return SubPage(
      title: l.setPlayer,
      onBack: () => context.go('/settings'),
      children: [
        SettingsCaption(l.pvGroupLook.toUpperCase()),
        const SizedBox(height: 10),
        SettingsGroupCard(
          rows: [
            SettingsValueRow(
              title: l.pvStyleRow,
              value: _styleLabel(l, style),
              glyph: _StyleGlyph(style: style),
              onTap: () => _openStyle(context),
            ),
            SettingsValueRow(
              title: l.pvPlayButtonRow,
              value: _playShapeLabel(l, playShape),
              glyph: _PlayShapeGlyph(shape: playShape),
              onTap: () => _openPlayShape(context),
            ),
          ],
        ),
        const SizedBox(height: 22),
        SettingsCaption(l.pvGroupQueue.toUpperCase()),
        const SizedBox(height: 10),
        const _QueueViewCards(),
        const SizedBox(height: 12),
        // Плашка «Далее» стоит в этой же группе, а не у слайдера: настраивает
        // она не полосу, а то, из чего плашка берётся, — очередь.
        SettingsGroupCard(
          rows: [
            SettingsToggleRow(
              title: l.pvNextUp,
              subtitle: l.pvNextUpSub,
              value: ref.watch(nextUpProvider),
              onChanged: ref.read(nextUpProvider.notifier).set,
            ),
          ],
        ),
        const SizedBox(height: 22),
        SettingsCaption(l.pvGroupBg.toUpperCase()),
        const SizedBox(height: 10),
        SettingsGroupCard(
          rows: [
            SettingsValueRow(
              title: l.pvBgRow,
              value: _playerBgLabel(l, bg),
              glyph: BloomIcon(_playerBgIcon(bg)),
              onTap: () => _openPlayerBg(context, ref),
            ),
            // Только под «Обложкой»: настраивать нечего, пока за плеером стоит
            // не она, — и строка, которая ничего не меняет, хуже отсутствующей.
            if (bg.isCover)
              SettingsValueRow(
                title: l.pvBgFxRow,
                value: _coverFxLabel(l, coverFx),
                glyph: BloomIcon(_coverFxIcon(coverFx)),
                onTap: () => _openCoverFx(context, ref),
              ),
          ],
        ),
        const SizedBox(height: 22),
        SettingsCaption(l.pvGroupTitle.toUpperCase()),
        const SizedBox(height: 10),
        SettingsGroupCard(
          rows: [
            SettingsValueRow(
              title: l.pvTitleAlign,
              value: _alignLabel(l, align),
              glyph: _AlignRowGlyph(align: align),
              onTap: () => _openTitleAlign(context),
            ),
          ],
        ),
        const SizedBox(height: 22),
        SettingsCaption(l.pvGroupSlider.toUpperCase()),
        const SizedBox(height: 10),
        SettingsGroupCard(
          rows: [
            SettingsValueRow(
              title: l.pvSliderRow,
              value: _sliderLabel(l, slider),
              glyph: _SliderRowGlyph(style: slider),
              onTap: () => _openSlider(context),
            ),
          ],
        ),
        const SizedBox(height: 22),
        SettingsCaption(l.pvGroupAnim.toUpperCase()),
        const SizedBox(height: 10),
        SettingsGroupCard(
          rows: [
            for (final surface in TrackAnimSurface.values)
              SettingsValueRow(
                title: _surfaceLabel(l, surface),
                value: _summary([
                  for (final target in TrackAnimTarget.values)
                    _kindLabel(l, anim.of(surface).of(target)),
                ]),
                // Значок — поверхность, а не вид перехода: их в строке два
                // (обложка и подпись), одним значком не показать.
                glyph: BloomIcon(
                  surface == TrackAnimSurface.player
                      ? Bi.maximizeSquare
                      : Bi.minimizeSquare,
                ),
                onTap: () => _openAnim(context, surface),
              ),
          ],
        ),
        const SizedBox(height: 22),
        SettingsCaption(l.pvGroupLyrics.toUpperCase()),
        const SizedBox(height: 10),
        SettingsGroupCard(
          rows: [
            SettingsValueRow(
              title: l.pvLyricsRow,
              value: _modeLabel(l, lyricsMode),
              glyph: const BloomIcon(Bi.magicStick),
              onTap: () => _openLyrics(context),
            ),
          ],
        ),
      ],
    );
  }
}

/// Подпись строки — выбранное через точку, в том же порядке, в каком настройки
/// идут в шторке.
String _summary(List<String> parts) => parts.join(' · ');

/// Шторка одной поверхности: обложка и подпись — двумя блоками.
///
/// Настройки читаются ВНУТРИ шторки (`Consumer`): выбор применяется на месте и
/// закрывать её незачем — вторая строка настраивается тут же.
Future<void> _openAnim(BuildContext context, TrackAnimSurface surface) {
  final l = context.l;
  return showBloomSheetChild<void>(
    context: context,
    header: settingsSheetHeader(
      context,
      _surfaceLabel(l, surface),
      _surfaceSub(l, surface),
    ),
    child: Consumer(
      builder: (context, ref, _) {
        final cfg = ref.watch(trackAnimProvider).of(surface);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final target in TrackAnimTarget.values)
              _Section(
                title: _targetLabel(l, target),
                child: _KindRow(
                  surface: surface,
                  target: target,
                  value: cfg.of(target),
                ),
              ),
          ],
        );
      },
    ),
  );
}

/// Шторка стиля плеера — порт карточки `settings.view.style` с ПК. Вариантов
/// два из четырёх: десктопные «Большой» и «Кино» — раскладки на широкое окно.
///
/// Устроена как шторка слайдера: сверху живое превью, под ним строки вариантов
/// с подписью — разница между стилями чисто картиночная, словами её не
/// объяснить. От выбора шторка НЕ закрывается: варианты для того и смотрят на
/// превью, что квадрат на глазах скругляется в диск и начинает крутиться.
/// Шапки нет по той же причине, что у слайдера, — она повторяла бы строку, с
/// которой в шторку пришли, и съедала высоту у превью.
Future<void> _openStyle(BuildContext context) {
  return showBloomSheetChild<void>(
    context: context,
    child: Consumer(
      builder: (context, ref, _) {
        final current = ref.watch(playerStyleProvider);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StylePreview(style: current),
            for (final style in PlayerStyle.values)
              SheetChoiceTile(
                glyph: _StyleGlyph(style: style),
                label: _styleLabel(context.l, style),
                sub: _styleSub(context.l, style),
                selected: style == current,
                onTap: () =>
                    ref.read(playerStyleProvider.notifier).setStyle(style),
              ),
          ],
        );
      },
    ),
  );
}

// ── Кнопка воспроизведения ──────────────────────────────────────────────────
// Наша настройка, десктопной пары нет: на ПК транспорт живёт в узкой полосе, и
// круг там единственно возможный. Настройка одна на обе поверхности — плеер и
// карточку над таб-баром (см. [PlayButtonShape]).

String _playShapeLabel(AppLocalizations l, PlayButtonShape shape) =>
    switch (shape) {
      PlayButtonShape.circle => l.pvPlayButtonCircle,
      PlayButtonShape.square => l.pvPlayButtonSquare,
      PlayButtonShape.plain => l.pvPlayButtonPlain,
    };

String _playShapeSub(AppLocalizations l, PlayButtonShape shape) =>
    switch (shape) {
      PlayButtonShape.circle => l.pvPlayButtonCircleSub,
      PlayButtonShape.square => l.pvPlayButtonSquareSub,
      PlayButtonShape.plain => l.pvPlayButtonPlainSub,
    };

/// Шторка формы кнопки. Устроена как шторка стиля плеера: сверху живая кнопка,
/// под ней варианты — разница между ними чисто картиночная, подписью её не
/// объяснить. От выбора шторка НЕ закрывается: варианты для того и перебирают,
/// глядя на превью.
Future<void> _openPlayShape(BuildContext context) {
  return showBloomSheetChild<void>(
    context: context,
    child: Consumer(
      builder: (context, ref, _) {
        final current = ref.watch(playButtonShapeProvider);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _PlayShapePreview(),
            for (final shape in PlayButtonShape.values)
              SheetChoiceTile(
                glyph: _PlayShapeGlyph(shape: shape),
                label: _playShapeLabel(context.l, shape),
                sub: _playShapeSub(context.l, shape),
                selected: shape == current,
                onTap: () =>
                    ref.read(playButtonShapeProvider.notifier).set(shape),
              ),
          ],
        );
      },
    ),
  );
}

/// Живое превью: та самая [PlayButton] из плеера между соседями по транспорту —
/// иначе «крупнее соседних» не с чем сравнить. Кнопка неживая (`live: false`):
/// превью показывает вид, а не управляет звуком.
class _PlayShapePreview extends StatelessWidget {
  const _PlayShapePreview();

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Padding(
      padding: const EdgeInsets.fromLTRB(kSheetEdge, 8, kSheetEdge, 12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 26),
        decoration: BoxDecoration(
          // Та же заливка, что у блоков шторки.
          color: sheetPanelColor(context),
          borderRadius: BorderRadius.circular(t.radius),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            BloomIcon(Bi.skipPreviousBold, size: 30, color: t.iconFg),
            const SizedBox(width: 26),
            const PlayButton(
              size: 68,
              iconSize: 28,
              plainIconSize: 40,
              spinnerSize: 28,
              live: false,
            ),
            const SizedBox(width: 26),
            BloomIcon(Bi.skipNextBold, size: 30, color: t.iconFg),
          ],
        ),
      ),
    );
  }
}

/// Знак play в рамке своей формы — и в строке настройки, и в шторке. Рисуем
/// сами: в Solar есть готовые «play в круге» и «play в квадрате», но у них
/// разная толщина и посадка знака, и рядом друг с другом варианты читались бы
/// как разные иконки, а не как одна кнопка в трёх формах.
class _PlayShapeGlyph extends StatelessWidget {
  const _PlayShapeGlyph({required this.shape});

  final PlayButtonShape shape;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(23, 23),
    painter: _PlayShapePainter(
      shape: shape,
      color: IconTheme.of(context).color ?? context.bloom.iconFg,
    ),
  );
}

class _PlayShapePainter extends CustomPainter {
  const _PlayShapePainter({required this.shape, required this.color});

  final PlayButtonShape shape;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Рисуем в сетке 24×24, как значки Solar, и масштабируем разом.
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    switch (shape) {
      case PlayButtonShape.circle:
        canvas.drawCircle(const Offset(12, 12), 9.5, stroke);
      case PlayButtonShape.square:
        canvas.drawRRect(
          // Та же доля стороны, что у самой кнопки (0.3): рамка значка обязана
          // повторять её скругление, иначе выбор объясняет не то.
          RRect.fromLTRBR(2.5, 2.5, 21.5, 21.5, const Radius.circular(5.7)),
          stroke,
        );
      case PlayButtonShape.plain:
        break;
    }

    // Без рамки знак крупнее — ровно тем же приёмом, что и сама кнопка.
    final k = shape.isPlain ? 1.9 : 1.0;
    final path = Path()
      ..moveTo(12 - 2.6 * k, 12 - 4.2 * k)
      ..lineTo(12 + 4.4 * k, 12)
      ..lineTo(12 - 2.6 * k, 12 + 4.2 * k)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PlayShapePainter old) =>
      old.shape != shape || old.color != color;
}

/// Вид очереди — порт десктопной карточки `settings.view.queueView`.
///
/// Единственная настройка на странице, которая стоит КАРТОЧКАМИ, а не строкой
/// со шторкой: вариантов два, объяснять их подписью нечем — разницу показывает
/// сам значок, и ради двух строк открывать шторку незачем.
class _QueueViewCards extends ConsumerWidget {
  const _QueueViewCards();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(queueViewProvider);
    final l = context.l;
    return Row(
      children: [
        for (final view in QueueView.values) ...[
          if (view != QueueView.values.first) const SizedBox(width: 12),
          Expanded(
            child: _OptionCard(
              label: view.isExtended ? l.pvQueueExtended : l.pvQueueNormal,
              selected: view == current,
              glyph: _QueueViewGlyph(extended: view.isExtended),
              onTap: () => ref.read(queueViewProvider.notifier).set(view),
            ),
          ),
        ],
      ],
    );
  }
}

/// Карточка варианта: значок над подписью. Одна на вид очереди и на кнопки в
/// шторках (переходы, вид текста) — выбор «одно из нескольких» на странице
/// плеера должен читаться одинаково, где бы он ни стоял.
class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.label,
    required this.glyph,
    required this.selected,
    required this.onTap,
  });

  final String label;

  /// Значок красится через [IconTheme]: акцентом у выбранной карточки.
  final Widget glyph;
  final bool selected;
  final VoidCallback onTap;

  /// Ростом с две строки настроек: карточка держит значок и подпись, и на
  /// меньшей высоте они сходятся вплотную.
  static const double height = 88;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    return Pressable(
      onTap: onTap,
      scale: 0.97,
      child: GlassBox(
        // Радиус группы настроек: карточки стоят на её месте и обязаны читаться
        // с ней одинаково.
        borderRadius: BorderRadius.circular(t.radius * 1.3),
        child: Material(
          color: Colors.transparent,
          child: Ink(
            // Выбранное — тонкая плёнка акцента поверх стекла, как у строки
            // варианта в шторке (`SheetOptionTile`). Сплошной заливки тут быть
            // не должно: карточка остаётся поверхностью темы.
            color: selected ? t.accent.withValues(alpha: 0.12) : null,
            child: SizedBox(
              height: height,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconTheme(
                    data: IconThemeData(color: selected ? t.accent : t.iconFg),
                    child: glyph,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodyMedium?.copyWith(
                      color: selected ? t.text : t.text2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Значок вида очереди: плоский список против списка с заголовками секций.
///
/// Рисуем сами — в Solar есть только общий «список», и двумя одинаковыми
/// значками разницу между вариантами не показать.
class _QueueViewGlyph extends StatelessWidget {
  const _QueueViewGlyph({required this.extended});

  final bool extended;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(26, 20),
    painter: _QueueGlyphPainter(
      extended: extended,
      color: IconTheme.of(context).color ?? context.bloom.iconFg,
    ),
  );
}

class _QueueGlyphPainter extends CustomPainter {
  _QueueGlyphPainter({required this.extended, required this.color});

  final bool extended;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Полоса: доля ширины и своя прозрачность. Заголовок секции — короткий и
    // приглушённый, строка трека — во всю ширину.
    const rows = <({double width, double alpha, double height})>[
      (width: 1, alpha: 0.9, height: 2.5),
    ];
    final plan = extended
        ? const [
            (width: 0.42, alpha: 0.45, height: 2.0),
            (width: 1.0, alpha: 0.9, height: 2.5),
            (width: 1.0, alpha: 0.9, height: 2.5),
            (width: 0.42, alpha: 0.45, height: 2.0),
            (width: 1.0, alpha: 0.9, height: 2.5),
          ]
        : [for (var i = 0; i < 4; i++) rows.first];

    final total = plan.fold<double>(0, (sum, r) => sum + r.height);
    final gap = (size.height - total) / (plan.length - 1);
    final paint = Paint()..style = PaintingStyle.fill;
    var y = 0.0;
    for (final row in plan) {
      paint.color = color.withValues(alpha: color.a * row.alpha);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, y, size.width * row.width, row.height),
          Radius.circular(row.height / 2),
        ),
        paint,
      );
      y += row.height + gap;
    }
  }

  @override
  bool shouldRepaint(_QueueGlyphPainter old) =>
      old.extended != extended || old.color != color;
}

/// Живое превью стиля: мини-плеер с настоящей обложкой играющего трека.
///
/// Обложка та же, что в плеере (своя из «Кастомизации» важнее обложки трека), и
/// диск крутится тем же [VinylSpin] — картинка в настройках не должна
/// разойтись с настоящей. Ничего не играет — на её месте обычная заглушка.
class _StylePreview extends ConsumerWidget {
  const _StylePreview({required this.style});

  final PlayerStyle style;

  /// Сторона обложки в превью.
  static const double side = 132;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final vinyl = style.isVinyl;
    final url = ref.watch(playerCoverProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(kSheetEdge, 8, kSheetEdge, 12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 22),
        decoration: BoxDecoration(
          // Та же заливка, что у блоков шторки.
          color: sheetPanelColor(context),
          borderRadius: BorderRadius.circular(t.radius),
        ),
        child: Column(
          children: [
            SizedBox(
              width: side,
              height: side,
              child: Stack(
                children: [
                  // Квадрат скругляется в круг НА ГЛАЗАХ — по этой доле и видно,
                  // что настройка сделала. Радиус обложки в плеере (20) на
                  // превью взят долей стороны, иначе маленькая картинка
                  // выглядела бы заметно острее настоящей.
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: vinyl ? 1 : 0),
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    builder: (context, k, child) => ClipRRect(
                      borderRadius: BorderRadius.circular(
                        side * (0.11 + 0.39 * k),
                      ),
                      child: child,
                    ),
                    child: VinylSpin(
                      enabled: vinyl,
                      // В настройках диск крутится ВСЕГДА, пока стиль выбран:
                      // звука тут нет, а замерший круг от квадрата отличается
                      // только формой — половина смысла режима осталась бы за
                      // кадром.
                      spinning: true,
                      child: Cover(url: url, size: side, radius: 0),
                    ),
                  ),
                  if (vinyl)
                    Positioned.fill(
                      child: Center(
                        child: VinylLabel(size: side * VinylLabel.share),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            // Название и артист — плашками, а не текстом: превью показывает
            // раскладку, а не содержимое, и живой заголовок тянул бы на себя
            // всё внимание.
            _Bar(width: 104, height: 9, color: t.text.withValues(alpha: 0.55)),
            const SizedBox(height: 8),
            _Bar(width: 68, height: 7, color: t.text.withValues(alpha: 0.24)),
          ],
        ),
      ),
    );
  }
}

/// Плашка на месте строки текста в превью.
class _Bar extends StatelessWidget {
  const _Bar({required this.width, required this.height, required this.color});

  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(height / 2),
    ),
  );
}

/// Шторка выравнивания заголовка — порт карточки `settings.view.titleAlign` с
/// ПК.
///
/// Вариантов три и настройка одна: строки крупные, во всю ширину, с подписью и
/// галочкой — как в шторке «Свайпов», а не тремя кнопками в ряд. И закрывается
/// от выбора: настраивать в ней больше нечего.
///
/// Шапки нет: строка, из которой сюда пришли, осталась видна над шторкой, и
/// подписывать выбор второй раз незачем.
Future<void> _openTitleAlign(BuildContext context) {
  return showBloomSheetChild<void>(
    context: context,
    child: Consumer(
      builder: (context, ref, _) {
        final current = ref.watch(titleAlignProvider);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final align in TitleAlign.values)
              SheetChoiceTile(
                glyph: CustomPaint(
                  size: const Size(22, 22),
                  painter: _AlignGlyph(align: align, color: context.bloom.text),
                ),
                label: _alignLabel(context.l, align),
                sub: _alignSub(context.l, align),
                selected: align == current,
                closes: true,
                onTap: () => ref.read(titleAlignProvider.notifier).set(align),
              ),
          ],
        );
      },
    ),
  );
}

/// Тот же значок для строки настройки: без кружка и цветом [IconTheme] — в
/// строке он стоит наравне с обычными значками Solar.
class _AlignRowGlyph extends StatelessWidget {
  const _AlignRowGlyph({required this.align});

  final TitleAlign align;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(21, 21),
    painter: _AlignGlyph(
      align: align,
      color: IconTheme.of(context).color ?? context.bloom.iconFg,
    ),
  );
}

/// Три строки разной длины, сдвинутые к своему краю, — те же SVG, что в
/// десктопной карточке выравнивания. В Solar такой тройки нет: `alignLeft`
/// оттуда — направляющая с планкой, а не текст.
class _AlignGlyph extends CustomPainter {
  const _AlignGlyph({required this.align, required this.color});

  final TitleAlign align;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Рисуем в сетке 24×24, как исходные SVG, и масштабируем разом.
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = color;

    // Первая строка всегда во всю ширину — двигаются только короткие, иначе
    // разница между вариантами не читается в 22 px.
    canvas.drawLine(const Offset(3, 6), const Offset(21, 6), stroke);
    final (mid, last) = switch (align) {
      TitleAlign.left => ((3.0, 15.0), (3.0, 18.0)),
      TitleAlign.center => ((6.0, 18.0), (4.0, 20.0)),
      TitleAlign.right => ((9.0, 21.0), (6.0, 21.0)),
    };
    canvas.drawLine(Offset(mid.$1, 12), Offset(mid.$2, 12), stroke);
    canvas.drawLine(Offset(last.$1, 18), Offset(last.$2, 18), stroke);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AlignGlyph old) =>
      old.align != align || old.color != color;
}

String _alignLabel(AppLocalizations l, TitleAlign align) => switch (align) {
  TitleAlign.left => l.pvTitleAlignLeft,
  TitleAlign.center => l.pvTitleAlignCenter,
  TitleAlign.right => l.pvTitleAlignRight,
};

String _alignSub(AppLocalizations l, TitleAlign align) => switch (align) {
  TitleAlign.left => l.pvTitleAlignLeftSub,
  TitleAlign.center => l.pvTitleAlignCenterSub,
  TitleAlign.right => l.pvTitleAlignRightSub,
};

/// Шторка типа слайдера — порт карточки `settings.view.slider` с ПК.
///
/// Сверху живая полоса прогресса, под ней строки вариантов: разница между
/// типами — только в том, как выглядит сама полоса, и подписью «Волновой» её не
/// объяснить. От выбора шторка НЕ закрывается — ради этого превью и стоит:
/// варианты перебираются подряд, глядя на него.
///
/// Шапки у этой шторки нет — в отличие от соседних. Название и пояснение
/// повторяли строку, с которой в неё пришли, и съедали высоту у того, ради чего
/// она открыта: превью и вариантов. Что настраивается — видно по самой полосе.
Future<void> _openSlider(BuildContext context) {
  return showBloomSheetChild<void>(
    context: context,
    child: Consumer(
      builder: (context, ref, _) {
        final current = ref.watch(sliderStyleProvider);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SliderPreview(style: current),
            for (final style in SliderStyle.values)
              SheetChoiceTile(
                // 44x10 like the PC grid: at 28 px it reads as a bar with a
                // thumb, not a dash.
                glyph: CustomPaint(
                  size: const Size(28, 6.4),
                  painter: _SliderGlyph(
                    style: style,
                    color: context.bloom.text,
                  ),
                ),
                label: _sliderLabel(context.l, style),
                selected: style == current,
                onTap: () => ref.read(sliderStyleProvider.notifier).set(style),
              ),
          ],
        );
      },
    ),
  );
}

/// Живая полоса прогресса в шторке: та же [bloomSliderTheme], что в плеере, —
/// иначе картинка в настройках со временем разошлась бы с настоящей.
///
/// Полосу можно тянуть: у половины типов вся разница в пуговке и в том, как она
/// разрезает дорожку, и на замершей картинке этого не видно. Время слева бежит
/// за пальцем, справа стоит длительность демо-трека.
class _SliderPreview extends StatefulWidget {
  const _SliderPreview({required this.style});

  final SliderStyle style;

  /// Демо-трек: 3:45 с позицией на 1:24 (мс).
  static const int total = 225000;
  static const int start = 84000;

  /// Зерно волны — постоянное: узор в настройках не должен меняться от
  /// открытия к открытию (в плеере он свой на каждый трек).
  static const int waveSeed = 42;

  @override
  State<_SliderPreview> createState() => _SliderPreviewState();
}

class _SliderPreviewState extends State<_SliderPreview> {
  double _value = _SliderPreview.start.toDouble();

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(kSheetEdge, 8, kSheetEdge, 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
        decoration: BoxDecoration(
          // Та же заливка, что у блоков шторки.
          color: sheetPanelColor(context),
          borderRadius: BorderRadius.circular(t.radius),
        ),
        child: Column(
          children: [
            SizedBox(
              // Выше плеерной ловушки (там 29: дорожка 5 плюс по 12 воздуха) —
              // это главное, ради чего шторка открыта, и полоса в ней должна
              // читаться крупно, а не как строка настройки.
              height: 44,
              child: SliderTheme(
                data: bloomSliderTheme(
                  SliderTheme.of(context),
                  style: widget.style,
                  tokens: t,
                  waveSeed: _SliderPreview.waveSeed,
                ),
                child: Slider(
                  value: _value,
                  max: _SliderPreview.total.toDouble(),
                  onChanged: (v) => setState(() => _value = v),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    mmss(Duration(milliseconds: _value.round())),
                    style: theme.bodyMedium,
                  ),
                  Text(
                    mmss(const Duration(milliseconds: _SliderPreview.total)),
                    style: theme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Тот же значок для строки настройки. Уже, чем в шторке (26 против 28): в
/// строке он стоит в одной колонке со значками-иконками, и полоса во всю их
/// коробку выглядела бы рядом с ними линейкой.
class _SliderRowGlyph extends StatelessWidget {
  const _SliderRowGlyph({required this.style});

  final SliderStyle style;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(26, 6),
    painter: _SliderGlyph(
      style: style,
      color: IconTheme.of(context).color ?? context.bloom.iconFg,
    ),
  );
}

/// Четыре крошечных SVG из десктопной карточки `settings.view.slider`: полоса с
/// заливкой, волосяная полоса с кружком, два сегмента с каплей и столбики.
class _SliderGlyph extends CustomPainter {
  const _SliderGlyph({required this.style, required this.color});

  final SliderStyle style;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Рисуем в сетке 44×10, как исходные SVG, и масштабируем разом.
    canvas.save();
    canvas.scale(size.width / 44, size.height / 10);
    final fill = Paint()..color = color;
    // Незалитая часть — та же треть яркости, что у десктопного `opacity={0.3}`.
    final rest = Paint()..color = color.withValues(alpha: 0.3);

    void bar(double x, double y, double w, double h, Paint paint) =>
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, w, h),
            Radius.circular(math.min(1, h / 2)),
          ),
          paint,
        );

    switch (style) {
      case SliderStyle.standard:
        bar(0, 4, 44, 2, rest);
        bar(0, 4, 22, 2, fill);
      case SliderStyle.thin:
        bar(0, 4.5, 44, 1, rest);
        bar(0, 4.5, 22, 1, fill);
        canvas.drawCircle(const Offset(22, 5), 2.5, fill);
      case SliderStyle.ios:
        bar(0, 4, 20, 2, fill);
        bar(24, 4, 20, 2, rest);
        bar(21, 1, 2, 8, fill);
      case SliderStyle.wave:
        // Пятнадцать столбиков с шагом 3: семь залитых, остальные тихие.
        const List<double> heights = [
          4, 6, 3, 8, 5, 7, 4, 6, 3, 7, 5, 4, 8, 3, 5, //
        ];
        for (var i = 0; i < heights.length; i++) {
          final h = heights[i];
          bar(i * 3, (10 - h) / 2, 2, h, i < 7 ? fill : rest);
        }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SliderGlyph old) =>
      old.style != style || old.color != color;
}

String _sliderLabel(AppLocalizations l, SliderStyle style) => switch (style) {
  SliderStyle.standard => l.pvSliderStandard,
  SliderStyle.thin => l.pvSliderThin,
  // Название платформы не переводится — на ПК оно тоже вписано прямо в кнопку.
  SliderStyle.ios => 'iOS',
  SliderStyle.wave => l.pvSliderWave,
};

/// Шторка оформления текста песни: только вид. Заливку и эффект с ПК
/// (`settings.view.lyricsStyle`) убрали — активная строка горит целиком.
Future<void> _openLyrics(BuildContext context) {
  final l = context.l;
  return showBloomSheetChild<void>(
    context: context,
    child: Consumer(
      builder: (context, ref, _) {
        final current = ref.watch(lyricsPrefsProvider.select((p) => p.mode));
        final ctrl = ref.read(lyricsPrefsProvider.notifier);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Section(
              title: l.pvLyricsMode,
              subtitle: l.pvLyricsModeSub,
              // Вид — две крупные кнопки со своими значками: разница между ними
              // чисто картиночная, одними подписями её не объяснить.
              child: Row(
                children: [
                  for (final mode in LyricsMode.values) ...[
                    if (mode != LyricsMode.values.first)
                      const SizedBox(width: 8),
                    Expanded(
                      child: _OptionCard(
                        label: _modeLabel(l, mode),
                        selected: current == mode,
                        glyph: _ModeGlyph(mode: mode),
                        onTap: () => ctrl.setMode(mode),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}

/// Одна настройка в шторке: название, пояснение и кнопки. Без подложки и без
/// значка у названия — кнопки сами стоят карточками, и коробка вокруг них
/// давала рамку в рамке.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(kSheetEdge, 8, kSheetEdge, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.titleMedium),
          if (subtitle case final text?) ...[
            const SizedBox(height: 3),
            Text(text, style: theme.bodySmall),
          ],
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

String _styleLabel(AppLocalizations l, PlayerStyle style) => switch (style) {
  PlayerStyle.standard => l.pvStyleStandard,
  PlayerStyle.vinyl => l.pvStyleVinyl,
  PlayerStyle.aura => l.pvStyleAura,
  PlayerStyle.ivory => l.pvStyleIvory,
};

String _styleSub(AppLocalizations l, PlayerStyle style) => switch (style) {
  PlayerStyle.standard => l.pvStyleStandardSub,
  PlayerStyle.vinyl => l.pvStyleVinylSub,
  PlayerStyle.aura => l.pvStyleAuraSub,
  PlayerStyle.ivory => l.pvStyleIvorySub,
};

String _modeLabel(AppLocalizations l, LyricsMode mode) => switch (mode) {
  LyricsMode.overlay => l.pvLyricsModeOverlay,
  LyricsMode.replace => l.pvLyricsModeReplace,
};

/// Значок стиля плеера — те же два SVG, что в десктопном `ViewSection`: две
/// плитки рядом у обычного, круг в круге у пластинки.
class _StyleGlyph extends StatelessWidget {
  const _StyleGlyph({required this.style});

  final PlayerStyle style;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(24, 24),
    painter: _StylePainter(
      style: style,
      color: IconTheme.of(context).color ?? context.bloom.iconFg,
    ),
  );
}

class _StylePainter extends CustomPainter {
  const _StylePainter({required this.style, required this.color});

  final PlayerStyle style;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    switch (style) {
      // Две плитки рядом: широкая слева, узкая справа.
      case PlayerStyle.standard:
        canvas.drawRRect(
          RRect.fromLTRBR(3, 3, 11, 21, const Radius.circular(1)),
          stroke,
        );
        canvas.drawRRect(
          RRect.fromLTRBR(14, 3, 21, 21, const Radius.circular(1)),
          stroke,
        );
      // Диск с этикеткой.
      case PlayerStyle.vinyl:
        canvas.drawCircle(const Offset(12, 12), 9, stroke);
        canvas.drawCircle(const Offset(12, 12), 3, stroke);
      // Живая аура Apple Music: рамка со свечением и пружинящей точкой.
      case PlayerStyle.aura:
        canvas.drawRRect(
          RRect.fromLTRBR(4, 4, 20, 20, const Radius.circular(5)),
          stroke,
        );
        canvas.drawCircle(const Offset(12, 12), 3.5, stroke);
      // Слоновая кость (Ivory): строгий журнальный прямоугольник с линией.
      case PlayerStyle.ivory:
        canvas.drawRect(const Rect.fromLTWH(4, 4, 16, 16), stroke);
        canvas.drawLine(const Offset(7, 12), const Offset(17, 12), stroke);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StylePainter old) =>
      old.style != style || old.color != color;
}

/// Значок вида: слева квадрат обложки со строками поверх, справа — одни
/// строки. В Solar таких картинок нет, рисуем сами, как и значки анимации.
class _ModeGlyph extends StatelessWidget {
  const _ModeGlyph({required this.mode});

  final LyricsMode mode;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(28, 24),
    painter: _ModePainter(
      mode: mode,
      color: IconTheme.of(context).color ?? context.bloom.iconFg,
    ),
  );
}

class _ModePainter extends CustomPainter {
  const _ModePainter({required this.mode, required this.color});

  final LyricsMode mode;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 28, size.height / 24);
    final frame = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.round
      ..color = color.withValues(
        alpha: mode == LyricsMode.overlay ? 0.38 : 0.9,
      );
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..color = color;

    if (mode == LyricsMode.overlay) {
      // Рамка обложки, а по ней — строки текста.
      canvas.drawRRect(
        RRect.fromLTRBR(4, 3, 24, 21, const Radius.circular(3)),
        frame,
      );
      canvas.drawLine(const Offset(8, 9), const Offset(20, 9), line);
      canvas.drawLine(const Offset(8, 13), const Offset(17, 13), line);
      canvas.drawLine(const Offset(8, 17), const Offset(19, 17), line);
    } else {
      // Обложки нет — одни строки во всю ширину.
      canvas.drawLine(const Offset(4, 6), const Offset(24, 6), line);
      canvas.drawLine(const Offset(4, 11), const Offset(20, 11), line);
      canvas.drawLine(const Offset(4, 16), const Offset(23, 16), line);
      canvas.drawLine(const Offset(4, 21), const Offset(15, 21), line);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ModePainter old) =>
      old.mode != mode || old.color != color;
}

String _surfaceLabel(AppLocalizations l, TrackAnimSurface surface) =>
    switch (surface) {
      TrackAnimSurface.player => l.pvAnimPlayer,
      TrackAnimSurface.mini => l.pvAnimMini,
    };

String _surfaceSub(AppLocalizations l, TrackAnimSurface surface) =>
    switch (surface) {
      TrackAnimSurface.player => l.pvAnimPlayerSub,
      TrackAnimSurface.mini => l.pvAnimMiniSub,
    };

String _targetLabel(AppLocalizations l, TrackAnimTarget target) =>
    switch (target) {
      TrackAnimTarget.cover => l.pvAnimCover,
      TrackAnimTarget.text => l.pvAnimText,
    };

String _kindLabel(AppLocalizations l, TrackAnimKind kind) => switch (kind) {
  TrackAnimKind.none => l.pvAnimNone,
  TrackAnimKind.slide => l.pvAnimSlide,
  TrackAnimKind.fade => l.pvAnimFade,
};

/// Три варианта в ряд — порт десктопного `s-opt-row`.
class _KindRow extends ConsumerWidget {
  const _KindRow({
    required this.surface,
    required this.target,
    required this.value,
  });

  final TrackAnimSurface surface;
  final TrackAnimTarget target;
  final TrackAnimKind value;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        for (final kind in TrackAnimKind.values) ...[
          if (kind != TrackAnimKind.values.first) const SizedBox(width: 8),
          Expanded(
            child: _OptionCard(
              label: _kindLabel(context.l, kind),
              selected: kind == value,
              glyph: _KindGlyphBox(kind: kind),
              onTap: () => ref
                  .read(trackAnimProvider.notifier)
                  .setKind(surface, target, kind),
            ),
          ),
        ],
      ],
    );
  }
}

/// [_KindGlyph] цветом [IconTheme] — его задаёт [_OptionCard].
class _KindGlyphBox extends StatelessWidget {
  const _KindGlyphBox({required this.kind});

  final TrackAnimKind kind;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(24, 24),
    painter: _KindGlyph(
      kind: kind,
      color: IconTheme.of(context).color ?? context.bloom.iconFg,
    ),
  );
}

/// Значок варианта — те же три картинки, что в десктопной строке выбора.
class _KindGlyph extends CustomPainter {
  const _KindGlyph({required this.kind, required this.color});

  final TrackAnimKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Рисуем в сетке 24×24, как исходные SVG, и масштабируем разом.
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final faded = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color.withValues(alpha: 0.38);

    switch (kind) {
      // Перечёркнутый круг.
      case TrackAnimKind.none:
        canvas.drawCircle(const Offset(12, 12), 9, stroke);
        canvas.drawLine(const Offset(6, 18), const Offset(18, 6), stroke);
      // Две плитки рядом: приезжающая сплошная, уезжающая тихая.
      case TrackAnimKind.slide:
        canvas.drawRRect(
          RRect.fromLTRBR(2, 6, 11, 18, const Radius.circular(1.5)),
          faded,
        );
        canvas.drawRRect(
          RRect.fromLTRBR(13, 6, 22, 18, const Radius.circular(1.5)),
          stroke,
        );
        canvas.drawLine(const Offset(9, 12), const Offset(15, 12), faded);
      // Две плитки внахлёст.
      case TrackAnimKind.fade:
        canvas.drawRRect(
          RRect.fromLTRBR(3, 6, 15, 18, const Radius.circular(1.5)),
          faded,
        );
        canvas.drawRRect(
          RRect.fromLTRBR(9, 6, 21, 18, const Radius.circular(1.5)),
          stroke,
        );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_KindGlyph old) => old.kind != kind || old.color != color;
}

// ── Фон плеера ──────────────────────────────────────────────────────────────
// Наша настройка, десктопной пары у неё нет: на широком окне за плеером стоит
// само приложение, а на телефоне он занимает экран целиком, и за обложкой —
// пустота. Варианты крупными строками с пояснением: словом «Цвет» не объяснить,
// что цвет берётся от обложки.

String _playerBgLabel(AppLocalizations l, PlayerBg bg) => switch (bg) {
  PlayerBg.cover => l.pvBgCover,
  PlayerBg.app => l.pvBgApp,
  PlayerBg.color => l.pvBgColor,
  PlayerBg.none => l.pvBgNone,
};

String _playerBgSub(AppLocalizations l, PlayerBg bg) => switch (bg) {
  PlayerBg.cover => l.pvBgCoverSub,
  PlayerBg.app => l.pvBgAppSub,
  PlayerBg.color => l.pvBgColorSub,
  PlayerBg.none => l.pvBgNoneSub,
};

BloomGlyph _playerBgIcon(PlayerBg bg) => switch (bg) {
  PlayerBg.cover => Bi.gallery,
  // Тот же значок, каким «Фон» помечен на плитке картинки в библиотеке
  // («Кастомизация»): строка и там и тут про одно и то же место.
  PlayerBg.app => Bi.galleryWide,
  PlayerBg.color => Bi.palette,
  PlayerBg.none => Bi.forbiddenCircle,
};

/// Шторка «Фон плеера». Шапки нет: строка, из которой сюда пришли, осталась
/// видна над шторкой, а что делает каждый вариант, говорит его же подпись.
/// Закрывается от выбора — как и остальные шторки «одно из».
///
/// «Фон приложения» гаснет, пока фона нет: брать в плеер нечего, и вместо
/// подписи варианта строка говорит, где его поставить.
Future<void> _openPlayerBg(BuildContext context, WidgetRef ref) {
  final hasAppBg = ref.read(playerAppBgProvider) != null;
  return pickOneSheet(
    context: context,
    values: PlayerBg.values,
    current: ref.read(playerBgProvider),
    icon: _playerBgIcon,
    label: (bg) => _playerBgLabel(context.l, bg),
    sub: (bg) => bg == PlayerBg.app && !hasAppBg
        ? context.l.pvBgAppOff
        : _playerBgSub(context.l, bg),
    enabled: (bg) => bg != PlayerBg.app || hasAppBg,
    apply: ref.read(playerBgProvider.notifier).set,
  );
}

// ── Эффект фона обложки ─────────────────────────────────────────────────────
// Вторая строка той же группы, и стоит она в ней только под «Обложкой»: у
// остальных фонов обложки за плеером нет.

String _coverFxLabel(AppLocalizations l, CoverBgFx fx) => switch (fx) {
  CoverBgFx.dim => l.pvBgFxDim,
  CoverBgFx.blur => l.pvBgFxBlur,
  CoverBgFx.original => l.pvBgFxOriginal,
};

String _coverFxSub(AppLocalizations l, CoverBgFx fx) => switch (fx) {
  CoverBgFx.dim => l.pvBgFxDimSub,
  CoverBgFx.blur => l.pvBgFxBlurSub,
  CoverBgFx.original => l.pvBgFxOriginalSub,
};

BloomGlyph _coverFxIcon(CoverBgFx fx) => switch (fx) {
  // Луна — то же затемнение, каким «Ночной режим» помечен где угодно; капля —
  // размытие; палочка со звёздами — «как есть, без обработки».
  CoverBgFx.dim => Bi.moon,
  CoverBgFx.blur => Bi.waterdrop,
  CoverBgFx.original => Bi.magicStick,
};

/// Шторка «Эффект фона обложки» — устроена как шторка самого фона: варианты
/// объясняют себя подписью, и от выбора шторка закрывается.
///
/// Шапки нет по той же причине: строка, из которой сюда пришли, осталась видна
/// над шторкой.
Future<void> _openCoverFx(BuildContext context, WidgetRef ref) {
  return pickOneSheet(
    context: context,
    values: CoverBgFx.values,
    current: ref.read(coverBgFxProvider),
    icon: _coverFxIcon,
    label: (fx) => _coverFxLabel(context.l, fx),
    sub: (fx) => _coverFxSub(context.l, fx),
    apply: ref.read(coverBgFxProvider.notifier).set,
  );
}
