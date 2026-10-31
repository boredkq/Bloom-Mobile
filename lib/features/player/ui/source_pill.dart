/// Пилюля источника в шапке плеера: что именно сейчас играет — «Любимые»,
/// плейлист, альбом, страница артиста, выдача поиска.
///
/// Порт десктопного `#qpSourcePill` из `QueueBlock.tsx`: слева картинка
/// источника 24×24, дальше его имя, за именем — значок перемешки, когда она
/// включена (список идёт не в своём порядке, и это должно быть видно), а на
/// правом краю через волосяной разделитель — счётчик треков очереди, ровно как
/// на ПК.
///
/// Жестов два, и это главное отличие от десктопа. ТАП открывает шторку очереди:
/// пилюля — единственная кнопка очереди на экране (в ряду инструментов её
/// больше нет), а очередь открывают в разы чаще, чем уходят на её источник.
/// ДОЛГОЕ нажатие уводит на сам источник и закрывает плеер — это осталось от
/// прежнего тапа. У источников без своей страницы (поиск, витрина главной,
/// одиночный трек) долгого нажатия нет, тап работает всегда.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/library_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/marquee_text.dart';
import '../../../shared/ui/pressable.dart';
import '../../detail/detail_nav.dart';
import '../../library/ui/list_hero.dart';
import '../../profile/ui/history_sheet.dart';
import '../play_source.dart';
import 'player_sheet.dart';
import 'queue_sheet.dart';

/// Размеры пилюли. Вынесены сюда, а не размазаны по разметке: шапка плеера
/// собирается из них и из [kHeaderControl] — высота у пилюли та же, что у
/// круглых кнопок по краям, иначе шапка читается ступенькой.
const double _iconSize = 28;
const double _gap = 10;

/// Открыть источник очереди: закрыть плеер (и шторки над ним) и уйти на его
/// страницу.
///
/// Страницу кладём в навигатор ТЕКУЩЕЙ вкладки, а не в корневой: из поиска и
/// библиотеки те же страницы открываются под таб-баром и миниплеером, и
/// открытая отсюда обязана выглядеть так же (см. [currentBranchNavigator]).
void openPlaySource(BuildContext context, PlaySource source) {
  // Шторки над плеером снимает навигатор, а сам плеер — не маршрут: он слой
  // каркаса и складывается своим вызовом (см. `PlayerSheet`).
  Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst);
  collapsePlayerSheet();
  switch (source) {
    case LibSource(listId: 'history'):
      // History is a sheet over the profile: the profile first, then the sheet
      // once it's laid out.
      bloomRouter.go(kProfileLocation);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final root = bloomRouter.routerDelegate.navigatorKey.currentContext;
        if (root != null) showHistorySheet(root);
      });
    case LibSource(:final listId):
      // Раздел библиотеки живёт маршрутом — заодно переключит вкладку.
      bloomRouter.go('/library/list/$listId');
    case SetSource(:final set):
      final nav = currentBranchNavigator();
      if (nav != null) openSetIn(nav, set);
    case ArtistSource(:final artist):
      final nav = currentBranchNavigator();
      if (nav != null) openArtistIn(nav, artist.id, initial: artist);
    case PlainSource():
    case WaveSource():
      // Поиск, витрина, одиночный трек, волна — открывать нечего.
      break;
  }
}

/// Есть ли у источника своя страница. У [PlainSource] и [WaveSource] её нет —
/// такая пилюля рисуется без ряби и не ловит тап.
bool playSourceOpens(PlaySource source) =>
    source is! PlainSource && source is! WaveSource;

class SourcePill extends ConsumerWidget {
  const SourcePill({
    super.key,
    required this.source,
    required this.shuffle,
    required this.count,
    this.background,
    this.borderColor,
  });

  /// Заливка. `null` — обычная плашка темы (`pill`). Шапка плеера на своём
  /// фоне передаёт сюда плёнку блоков: сплошная плашка на нём читается
  /// чёрной нашлёпкой, а рядом стоят полупрозрачные транспорт и инструменты.
  final Color? background;

  /// Обводка — по той же причине, что у [CircleIconButton.borderColor].
  final Color? borderColor;

  /// Источник очереди. `null` — очередь ниоткуда (снимок старой сессии,
  /// восстановленный до того, как источник начали запоминать): пилюля тогда
  /// просто называет себя очередью.
  final PlaySource? source;

  /// Перемешка — значок за именем источника.
  final bool shuffle;

  /// Сколько треков в очереди — счётчик на правом краю пилюли (порт
  /// `#qpSourceCount` с ПК). Ноль не рисуем: пустой очереди на этом экране не
  /// бывает, но снимок старой сессии мог доехать и таким.
  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final source = this.source;
    final label = source == null
        ? context.l.playerQueue
        : _label(context, ref, source);
    // Уйти на источник можно не у всякой очереди — тогда остаётся один тап.
    final opens = source != null && playSourceOpens(source);

    final border = borderColor;
    return Center(
      child: Pressable(
        // Тап — очередь. Всегда: пилюля заменила собой кнопку очереди в ряду
        // инструментов, и «мёртвой» она быть не может.
        onTap: () => showQueueSheet(context),
        // Долгое нажатие — источник. Отклик обязателен: у долгого нажатия нет
        // своего вида, и без него непонятно, сработало оно или ты просто
        // задержал палец на тапе.
        onLongPress: opens
            ? () {
                HapticFeedback.selectionClick();
                openPlaySource(context, source);
              }
            : null,
        child: Material(
          color: background ?? t.pill,
          // Пилюля ровно в высоту круглых кнопок, поэтому `StadiumBorder` — тот
          // же радиус, что был; форма нужна ради обводки: у `Material` она
          // задаётся либо радиусом, либо формой, но не тем и другим сразу.
          shape: StadiumBorder(
            side: border == null ? BorderSide.none : BorderSide(color: border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            // Слева поля больше, чем просвет над картинкой: край пилюли
            // скруглён, и квадратная обложка, отодвинутая от него «поровну»,
            // упирается в закругление. Справа меньше, чем было: у края теперь
            // стоит счётчик, а он и сам обведён — двойной отступ отжимал бы его
            // от края сильнее, чем картинку слева.
            padding: const EdgeInsets.fromLTRB(14, 0, 12, 0),
            child: SizedBox(
              height: kHeaderControl,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SourceIcon(source: source),
                  const SizedBox(width: _gap),
                  Flexible(
                    child: MarqueeText(
                      label,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: t.text,
                      ),
                    ),
                  ),
                  if (shuffle) ...[
                    const SizedBox(width: 8),
                    // Цветом в имя источника, а не акцентом: значок стоит
                    // прямо за именем и читается его частью — акцент рядом
                    // выдёргивал на себя больше внимания, чем сам источник.
                    BloomIcon(Bi.shuffle, size: 14, color: t.text),
                  ],
                  if (count > 0) ...[
                    // Волосяной разделитель перед счётчиком — порт того же
                    // `span` с ПК: без него обведённая цифра липнет к имени и
                    // читается его частью.
                    const SizedBox(width: 8),
                    // `ovlLine2`, а не `ovlLine`: шесть процентов плёнки —
                    // это обводка целого блока, у волоска в 1 px на них не
                    // остаётся ничего видимого.
                    Container(width: 1, height: 12, color: t.ovlLine2),
                    const SizedBox(width: 8),
                    _Count(count),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Подпись источника. У разделов библиотеки берётся ЖИВОЙ — плейлист могли
  /// переименовать, пока он играет (см. `play_source.dart`).
  String _label(BuildContext context, WidgetRef ref, PlaySource source) {
    switch (source) {
      case LibSource(:final listId):
        return switch (listId) {
          'all' => context.l.commonAllTracks,
          'fav' => context.l.commonFavorites,
          'history' => context.l.commonHistory,
          _ =>
            _playlist(ref, listId)?.name ??
                // Плейлист удалили прямо во время воспроизведения — очередь
                // играет дальше, а называть её больше нечем.
                context.l.commonPlaylist,
        };
      case SetSource(:final set):
        return set.title;
      case ArtistSource(:final artist):
        return artist.name;
      case PlainSource(:final label):
        return label;
      case WaveSource(:final label):
        return label;
    }
  }
}

/// Счётчик треков очереди — порт `#qpSourceCount` с ПК: цифра в обводке, тем
/// же цветом, что имя источника. Ширина по содержимому: трёхзначная очередь
/// встречается чаще, чем кажется, а фиксировать её нечем — имя источника рядом
/// и так ужимается первым.
class _Count extends StatelessWidget {
  const _Count(this.value);

  final int value;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Container(
      height: 20,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        border: Border.all(color: t.ovlLine2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$value',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          height: 1,
          color: t.text,
        ),
      ),
    );
  }
}

UserPlaylist? _playlist(WidgetRef ref, String id) {
  for (final playlist in ref.watch(libraryProvider).playlists) {
    if (playlist.id == id) return playlist;
  }
  return null;
}

/// Картинка источника: обложка сета, аватар артиста, коллаж плейлиста либо
/// фирменный тинт раздела — ровно то же, что показывает его карточка.
class _SourceIcon extends ConsumerWidget {
  const _SourceIcon({required this.source});

  final PlaySource? source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final radius = t.radius * 0.4;

    switch (source) {
      case null:
        return _tint(t, radius, t.ovlBg, t.muted, Bi.musicNoteBold);
      case LibSource(:final listId):
        final glyph = systemListGlyph(listId);
        if (glyph != null) return _outline(t, radius, glyph);
        // Плейлист: своя обложка → коллаж из первых треков, как на его плитке.
        final lib = ref.watch(libraryProvider);
        final playlist = _playlist(ref, listId);
        return Cover(
          url: playlist?.cover,
          size: _iconSize,
          radius: radius,
          covers: playlist == null
              ? const <String?>[]
              : lib.tracksOf(playlist).map((track) => track.cover),
        );
      case WaveSource():
        // Волна — не список, обложки у неё нет: значок берёт акцент темы, как
        // и её карточка на главной.
        return _tint(t, radius, t.ovlBg, t.accent, Bi.soundwaveBold);
      case SetSource(:final set):
        return Cover(url: set.cover, size: _iconSize, radius: radius);
      case ArtistSource(:final artist):
        return Cover(url: artist.avatar, size: _iconSize, circle: true);
      case PlainSource(:final cover, :final icon):
        if (cover != null) {
          return Cover(url: cover, size: _iconSize, radius: radius);
        }
        return switch (icon) {
          PlainSourceIcon.search => _tint(
            t,
            radius,
            t.ovlBg,
            t.text2,
            Bi.magnifier,
          ),
          PlainSourceIcon.clock => _outline(t, radius, Bi.clockCircle),
          PlainSourceIcon.chart => _tint(
            t,
            radius,
            t.sysAllTint,
            t.sysAllIco,
            Bi.chart2,
          ),
          PlainSourceIcon.note => _tint(
            t,
            radius,
            t.ovlBg,
            t.muted,
            Bi.musicNoteBold,
          ),
        };
    }
  }

  /// The library's own lists and history: their icon on an outline.
  Widget _outline(BloomTokens t, double radius, BloomGlyph icon) =>
      SizedBox.square(
        dimension: _iconSize,
        child: OutlineArt(
          icon: icon,
          iconSize: (_iconSize * 0.5).roundToDouble(),
          borderRadius: BorderRadius.circular(radius),
        ),
      );

  Widget _tint(
    BloomTokens t,
    double radius,
    Color tint,
    Color color,
    BloomGlyph icon,
  ) => Container(
    width: _iconSize,
    height: _iconSize,
    decoration: BoxDecoration(
      color: tint,
      borderRadius: BorderRadius.circular(radius),
    ),
    child: BloomIcon(icon, size: _iconSize * 0.54, color: color),
  );
}
