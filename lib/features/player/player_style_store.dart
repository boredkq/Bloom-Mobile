/// Стиль плеера — порт `playerStyle` из десктопного
/// `settings/model/playerViewStore.ts`.
///
/// Вариантов у нас два из четырёх. Десктопные `large` и `cinema` — это
/// grid-раскладки на широкое окно (обложка крупно слева, очередь колонкой
/// справа), на телефоне им негде развернуться: очередь у нас и так шторка.
/// Остались «Обычный» и «Пластинка».
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/json_store.dart' show jsonStoreProvider;

enum PlayerStyle {
  /// Квадратная обложка со скруглением — как было.
  standard,

  /// Круглая обложка, которая крутится, пока играет (`.ps-cover.vinyl-mode`).
  vinyl,

  /// Аура (Apple Music): живой фон и мягко пружинящая обложка.
  aura,

  /// Слоновая кость (Ivory): строгий журнальный минимализм.
  ivory;

  bool get isVinyl => this == PlayerStyle.vinyl;
  bool get isAura => this == PlayerStyle.aura;
  bool get isIvory => this == PlayerStyle.ivory;
}

final playerStyleProvider =
    NotifierProvider<PlayerStyleController, PlayerStyle>(
      PlayerStyleController.new,
    );

class PlayerStyleController extends Notifier<PlayerStyle> {
  @override
  PlayerStyle build() {
    final raw = ref.read(jsonStoreProvider).read('playerStyle');
    // Незнакомая запись (правили файл руками, откат на старую сборку, приехал
    // десктопный `large`) молча становится обычным плеером — стиль не повод
    // ронять запуск.
    for (final style in PlayerStyle.values) {
      if (style.name == raw) return style;
    }
    return PlayerStyle.standard;
  }

  void setStyle(PlayerStyle style) {
    if (style == state) return;
    state = style;
    ref.read(jsonStoreProvider).write('playerStyle', style.name);
  }
}
