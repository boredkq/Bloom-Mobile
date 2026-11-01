/// Аватары исполнителей для топа статистики — порт десктопного
/// `useArtistAvatars`.
///
/// В истории от артиста остаётся одно имя, поэтому настоящий аватар приходится
/// искать по имени — но НЕ где придётся: у той площадки, где его и слушали
/// (десктоп ходит всегда в SoundCloud, и у слушателя Яндекса в топе оказывались
/// чужие аккаунты). Поэтому и ключ кеша — «площадка|имя».
///
/// Ответ (в том числе пустой — «не нашли») кешируется на 30 дней: без этого
/// каждое открытие профиля дёргало бы сеть на десять запросов, а промахи —
/// снова и снова.
///
/// Загрузка фоновая и необязательная: сети нет или площадка не настроена —
/// в топе просто остаётся обложка самого слушаемого трека артиста.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/entities/entities.dart';
import '../../core/providers/artist_lookup.dart';
import '../../core/store/json_store.dart' show jsonStoreProvider;
import '../../shared/util/artists.dart';
import 'tally.dart';

/// Столько живёт запись кеша — как `TTL` на десктопе.
const Duration _ttl = Duration(days: 30);

/// Кого спрашивать и у какой площадки.
typedef ArtistRef = ({String name, MusicSource source});

/// Ключ кеша и карты аватаров. Одна функция на запись и на чтение: разъедься
/// они, топ смотрел бы в пустоту.
String artistAvatarKey(MusicSource source, String name) =>
    '${source.id}|${name.trim().toLowerCase()}';

/// What to show for an artist from the stats or a review: the avatar their best
/// track brings, else the one found, else that track's cover.
String? playedArtistAvatar(ArtistPlays a, Map<String, String> found) =>
    ownArtistAvatar(a.track) ??
    found[artistAvatarKey(a.source, a.name)] ??
    a.cover;

class _Cached {
  const _Cached(this.url, this.at);

  /// Пустая строка — искали и не нашли. Тоже кешируется.
  final String url;
  final int at;
}

final artistAvatarsProvider =
    NotifierProvider<ArtistAvatarsController, Map<String, String>>(
      ArtistAvatarsController.new,
    );

class ArtistAvatarsController extends Notifier<Map<String, String>> {
  final Map<String, _Cached> _cache = {};

  /// Кого уже спросили в этом запуске — чтобы параллельные перестройки списка
  /// не отправили десять одинаковых запросов.
  final Set<String> _inFlight = {};

  /// Загрузка асинхронная, а стор могут выбросить раньше её конца.
  bool _disposed = false;

  @override
  Map<String, String> build() {
    ref.onDispose(() => _disposed = true);
    final raw = ref.read(jsonStoreProvider).readMap('artistAvatars');
    for (final e in raw.entries) {
      final v = e.value;
      if (v is! Map) continue;
      // Записи старого кеша лежали под голым именем — площадки в них нет, и
      // чьи это аватарки, уже не сказать. Роняем: перезапросятся у нужной.
      if (!e.key.contains('|')) continue;
      _cache[e.key] = _Cached(
        v['url'] as String? ?? '',
        (v['t'] as num?)?.toInt() ?? 0,
      );
    }
    return _visible();
  }

  Map<String, String> _visible() => {
    for (final e in _cache.entries)
      if (e.value.url.isNotEmpty) e.key: e.value.url,
  };

  void _save() {
    ref.read(jsonStoreProvider).write('artistAvatars', {
      for (final e in _cache.entries)
        e.key: {'url': e.value.url, 't': e.value.at},
    });
  }

  /// Догрузить недостающие аватары. Зовётся из UI при показе топа; лишние
  /// вызовы безвредны — свежий кеш ничего не запрашивает.
  ///
  /// Каждого артиста спрашиваем у ЕГО площадки; свои файлы пропускаем — искать
  /// их артиста негде.
  Future<void> ensure(Iterable<ArtistRef> artists) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final todo = <ArtistRef>[];
    for (final artist in artists) {
      if (artist.name.trim().isEmpty) continue;
      if (artist.source == MusicSource.local) continue;
      final key = artistAvatarKey(artist.source, artist.name);
      if (_inFlight.contains(key)) continue;
      final cached = _cache[key];
      if (cached != null && now - cached.at < _ttl.inMilliseconds) continue;
      todo.add(artist);
      _inFlight.add(key);
    }
    if (todo.isEmpty) return;

    final registry = ref.read(registryProvider);
    var changed = false;
    for (final artist in todo) {
      final key = artistAvatarKey(artist.source, artist.name);
      final provider = registry.byId(artist.source.id);
      // Площадка выключена — промах не запоминаем: включат, и спросим.
      if (provider == null) {
        _inFlight.remove(key);
        continue;
      }
      String url = '';
      try {
        url = (await findArtistByName(provider, artist.name))?.avatar ?? '';
      } catch (_) {
        // Сети нет или площадка отказала — запомним промах, чтобы не биться
        // об неё каждым открытием профиля.
      }
      _cache[key] = _Cached(url, DateTime.now().millisecondsSinceEpoch);
      _inFlight.remove(key);
      changed = true;
    }

    if (!changed || _disposed) return;
    _save();
    state = _visible();
  }
}
