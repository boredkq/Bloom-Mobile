/// Витрина «Похожие на X» на главной: один сид из топа прослушиваний и то, что
/// на него похоже, — треки и артисты вперемешку; `Home::buildSimilar` ПК.
///
/// Сид живёт сутки, как «Для вас», и чередует тип: чётный день — артист,
/// нечётный — трек. Внутри типа сиды идут по кругу по верху топа, так что
/// витрина успевает показать несколько разных «якорей».
///
/// Откуда что берётся:
///   трек-сид   → похожие треки: похожие на него самого, не его артистов;
///                похожие артисты: первый артист трека → его страница.
///   артист-сид → похожие артисты: его страница;
///                похожие треки: похожие на его самые слушаемые треки, но без
///                его собственных (иначе витрина стала бы его дискографией).
library;

import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/entities/entities.dart';
import '../../core/providers/artist_lookup.dart';
import '../../core/providers/music_provider.dart';
import '../../shared/util/artists.dart';
import '../../shared/util/taste.dart';
import 'daily_showcase.dart';
import 'for_you.dart';

/// Из скольких верхних позиций топа крутится сид.
const int _seedPool = 5;

/// Сколько сидов пробуем подряд, если первый не дал похожих.
const int _seedTries = 2;
const int _tracksMax = 14;
const int _artistsMax = 6;

/// Меньше ТРЕКОВ — «похожие на» превращаются в список имён: другой сид или тип.
const int _minTracks = 4;

/// Столько артистов с картинкой хватает, чтобы безликих не брать.
const int _minFaced = 4;

/// Карточки «Для вас», видные без прокрутки: от них «Похожие на» держатся
/// всегда, от остальных — пока хватает своих.
const int _forYouNear = 6;

sealed class SimilarSeed {
  const SimilarSeed();

  String get name;
  String? get cover;

  Map<String, dynamic> toJson();

  static SimilarSeed? fromJson(Object? json) {
    if (json is! Map) return null;
    if (json['kind'] == 'artist') {
      final artist = Artist.fromJson(json['artist']);
      return artist == null ? null : SimilarArtistSeed(artist);
    }
    final id = json['id'];
    if (id is! String) return null;
    return SimilarTrackSeed(
      id: id,
      name: json['name'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      cover: json['cover'] as String?,
      track: Track.fromJson(json['track']),
    );
  }
}

final class SimilarTrackSeed extends SimilarSeed {
  const SimilarTrackSeed({
    required this.id,
    required this.name,
    required this.artist,
    this.cover,
    this.track,
  });

  final String id;
  @override
  final String name;
  final String artist;
  @override
  final String? cover;

  /// Сам трек — плитка сида играет его. `null` — поднять нечем (свой файл,
  /// которого нет в библиотеке), и плитка тогда не нажимается.
  final Track? track;

  @override
  Map<String, dynamic> toJson() => {
    'kind': 'track',
    'id': id,
    'name': name,
    'artist': artist,
    if (cover != null) 'cover': cover,
    if (track != null) 'track': track!.toJson(),
  };
}

final class SimilarArtistSeed extends SimilarSeed {
  const SimilarArtistSeed(this.artist);

  final Artist artist;

  @override
  String get name => artist.name;
  @override
  String? get cover => artist.avatar;

  @override
  Map<String, dynamic> toJson() => {
    'kind': 'artist',
    'artist': artist.toJson(),
  };
}

sealed class SimilarItem {
  const SimilarItem();

  Map<String, dynamic> toJson();

  static SimilarItem? fromJson(Object? json) {
    if (json is! Map) return null;
    if (json['kind'] == 'artist') {
      final artist = Artist.fromJson(json['artist']);
      return artist == null ? null : SimilarArtistItem(artist);
    }
    final track = Track.fromJson(json['track']);
    return track == null ? null : SimilarTrackItem(track);
  }
}

final class SimilarTrackItem extends SimilarItem {
  const SimilarTrackItem(this.track);
  final Track track;

  @override
  Map<String, dynamic> toJson() => {'kind': 'track', 'track': track.toJson()};
}

final class SimilarArtistItem extends SimilarItem {
  const SimilarArtistItem(this.artist);
  final Artist artist;

  @override
  Map<String, dynamic> toJson() => {
    'kind': 'artist',
    'artist': artist.toJson(),
  };
}

class SimilarTo {
  const SimilarTo(this.seed, this.items);

  final SimilarSeed seed;
  final List<SimilarItem> items;
}

/// Номер локального дня: от него чётность типа сида и позиция в круге.
int recsDayNumber(DateTime now) =>
    DateTime.utc(now.year, now.month, now.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;

MusicProvider? _providerOf(RecsInput input, MusicSource source) {
  final p = input.registry.byId(source.id);
  return p != null && p.isEnabled ? p : null;
}

/// Артист [name] на площадке трека [via] — `Artists::find` ПК: известна его
/// страница по треку — она, иначе поиск по имени.
Future<Artist?> _resolveArtist(RecsInput input, String name, Track via) async {
  final link = firstArtistLink(via);
  if (link.name == name && link.id != null) {
    return Artist(
      id: link.id!,
      name: name,
      avatar: via.artistAvatar,
      source: via.source,
    );
  }
  final provider = _providerOf(input, via.source);
  if (provider == null) return null;
  try {
    return await findArtistCached(provider, name);
  } on Object {
    return null;
  }
}

Future<ArtistPageData?> _artistPage(RecsInput input, Artist artist) async {
  final provider = _providerOf(input, artist.source);
  if (provider == null) return null;
  try {
    final page = await provider.getArtist(artist.id);
    // A listener's page lists their likes, not their music.
    return page?.likes == null ? page : null;
  } on Object {
    return null;
  }
}

/// Отбор треков — `Home::pickTracks` ПК: только новое (не сохранённое, не
/// слышанное, не из соседней «Для вас»), без копий, не больше двух на артиста
/// (по каждому имени), без своих артистов сида ([own]).
///
/// «Для вас» собрана из того же топа и лучшее уже забрала, поэтому строгий
/// проход часто выходит коротким: тогда держимся только от её первых карточек —
/// повтор в дальнем её конце лучше ряда из одних имён.
List<Track> _pickTracks(
  RecsInput input,
  List<Track> batch,
  Set<String> skip,
  Set<String> own,
  List<Track> forYou,
) {
  List<Track> select(List<Track> avoid) {
    final known = {...input.known, for (final t in avoid) t.id, ...skip};
    final dup = input.knownDups();
    for (final t in avoid) {
      dup.add(t);
    }
    final cap = ArtistCap(kRecsPerArtistMax);
    final out = <Track>[];
    for (final t in batch) {
      if (out.length >= _tracksMax) break;
      if (known.contains(t.id) || input.disliked.contains(t.id)) continue;
      if (artistKeys(t).any(own.contains) || !cap.fits(t)) continue;
      if (!dup.accept(t)) continue;
      known.add(t.id);
      cap.take(t);
      out.add(t);
    }
    return out;
  }

  final strict = select(forYou);
  if (strict.length >= _minTracks || forYou.length <= _forYouNear) {
    return strict;
  }
  final soft = select(forYou.take(_forYouNear).toList());
  return soft.length > strict.length ? soft : strict;
}

/// Похожие артисты без своих сида ([own]) и повторов. Серый круг-заглушка в
/// ряду выглядит поломкой, поэтому безликих берём, только когда иначе
/// артистов почти нет.
List<Artist> _pickArtists(List<Artist> list, Set<String> own) {
  final seen = {...own};
  final uniq = [
    for (final a in list)
      if (a.name.isNotEmpty && seen.add(artistKey(a.name))) a,
  ];
  final withAvatar = [
    for (final a in uniq)
      if (a.avatar != null) a,
  ];
  return (withAvatar.length >= _minFaced ? withAvatar : uniq)
      .take(_artistsMax)
      .toList();
}

/// Смешать: артист на каждой третьей позиции (Т А Т Т А Т Т …), и артистов не
/// больше половины треков — ряд лиц с треком-другим читается как список имён.
List<SimilarItem> mixSimilar(List<Track> tracks, List<Artist> artists) {
  final few = artists.take((tracks.length + 1) ~/ 2).toList();
  final out = <SimilarItem>[];
  var ti = 0;
  var ai = 0;
  while (ti < tracks.length || ai < few.length) {
    final wantArtist = out.length % 3 == 1;
    if ((wantArtist && ai < few.length) || ti >= tracks.length) {
      out.add(SimilarArtistItem(few[ai++]));
    } else {
      out.add(SimilarTrackItem(tracks[ti++]));
    }
  }
  return out;
}

/// Похожие на [seedId], которых пропускает [_pickTracks]; жидкий ответ
/// добирается похожими на трек, который назовёт [more] (`null` — как есть).
Future<List<Track>> _likeTracks(
  RecsInput input,
  String seedId,
  Track? Function(List<Track> first) more,
  Set<String> skip,
  Set<String> own,
  List<Track> forYou,
) async {
  final b0 = await similarTracksFor(input.registry, seedId);
  final tracks = _pickTracks(input, b0, skip, own, forYou);
  final next = tracks.length < _tracksMax ? more(b0) : null;
  if (next == null) return tracks;
  final b1 = await similarTracksFor(input.registry, next.id);
  return _pickTracks(input, [...b0, ...b1], skip, own, forYou);
}

/// Трек-сид: самые слушаемые треки, по кругу. Похожее на него от других и
/// артисты, похожие на его первого. Свои артисты — ни там, ни там: у
/// SoundCloud аккаунт (первая ссылка) и имена в строке бывают разными, поэтому
/// считаются оба.
Future<SimilarTo?> _fromTrack(
  RecsInput input,
  int turn,
  List<Track> forYou,
) async {
  final pool = recsTopPlayed(input, limit: _seedPool, minPlays: 2);
  for (var k = 0; k < math.min(_seedTries, pool.length); k++) {
    final id = pool[(turn + k) % pool.length].id;
    final seed = input.trackOf(id);
    if (seed == null || seed.name.isEmpty) continue;

    final first = firstArtistLink(seed).name;
    final own = {...artistKeys(seed), if (first.isNotEmpty) artistKey(first)};
    // Добор — от лучшего в ответе трека чужого артиста.
    Track? more(List<Track> b0) =>
        b0.where((t) => !artistKeys(t).any(own.contains)).firstOrNull;
    final tracks = await _likeTracks(input, id, more, {id}, own, forYou);
    // Показывать всё равно нечего — за артистами не ходим.
    if (tracks.length < _minTracks) continue;

    final artist = isRealArtist(first)
        ? await _resolveArtist(input, first, seed)
        : null;
    final artists = artist == null
        ? const <Artist>[]
        : _pickArtists(
            (await _artistPage(input, artist))?.similarArtists ?? const [],
            own,
          );
    return SimilarTo(
      SimilarTrackSeed(
        id: id,
        name: seed.name,
        artist: seed.artist,
        cover: seed.cover,
        track: seed,
      ),
      mixSimilar(tracks, artists),
    );
  }
  return null;
}

/// Артист-сид: самые слушаемые артисты, по кругу. Похожие артисты — с его
/// страницы; треки — похожие на его самые слушаемые, но не его (иначе это
/// его дискография).
Future<SimilarTo?> _fromArtist(
  RecsInput input,
  int turn,
  List<Track> forYou,
) async {
  final pool = topArtists(input, _seedPool);
  for (var k = 0; k < math.min(_seedTries, pool.length); k++) {
    final cand = pool[(turn + k) % pool.length];
    final artist = await _resolveArtist(input, cand.name, cand.own);
    if (artist == null) continue;

    final page = await _artistPage(input, artist);
    final found = page?.artist ?? artist;
    final name = found.name.isEmpty ? cand.name : found.name;
    final own = {cand.key, artistKey(name)};
    final artists = _pickArtists(page?.similarArtists ?? const [], own);
    // Похожие на один трек без его же треков бывают жидкими — добираем от
    // второго по прослушиваниям.
    final tracks = await _likeTracks(
      input,
      cand.theirs.first.id,
      (_) => cand.theirs.elementAtOrNull(1),
      {for (final t in cand.theirs) t.id},
      own,
      forYou,
    );
    if (tracks.length < _minTracks) continue;

    return SimilarTo(
      SimilarArtistSeed(
        Artist(
          id: found.id,
          name: name,
          avatar: found.avatar ?? artist.avatar ?? cand.own.cover,
          source: found.source,
        ),
      ),
      mixSimilar(tracks, artists),
    );
  }
  return null;
}

/// Собрать витрину. Тип сида — по чётности дня; не вышло — пробуем другой тип,
/// чтобы витрина не пропадала через день. [forYou] — соседняя витрина: её
/// треки и их перезаливы сюда не повторяются.
Future<SimilarTo?> buildSimilarTo(
  RecsInput input, {
  List<Track> forYou = const [],
}) async {
  final day = recsDayNumber(input.now);
  final turn = day ~/ 2;
  final artistFirst = day.isEven;
  for (final artist in [artistFirst, !artistFirst]) {
    final res = artist
        ? await _fromArtist(input, turn, forYou)
        : await _fromTrack(input, turn, forYou);
    if (res != null) return res;
  }
  return null;
}

final similarToProvider = NotifierProvider<SimilarToController, SimilarTo?>(
  SimilarToController.new,
);

class SimilarToController extends DailyShowcase<SimilarTo> {
  @override
  String get storeKey => 'similarTo';

  /// 3 — правила ПК: от четырёх треков, артистов не больше половины треков,
  /// без своих артистов трек-сида, добор с другого трека.
  @override
  int get version => 3;

  @override
  Future<SimilarTo?> fetch() async {
    // Утром обе витрины собираются разом — ждём соседнюю, иначе сверяться
    // было бы не с чем.
    await ref.read(forYouProvider.notifier).settled();
    return buildSimilarTo(
      recsInputOf(ref),
      forYou: ref.read(forYouProvider) ?? const [],
    );
  }

  @override
  Object? encode(SimilarTo value) => {
    'seed': value.seed.toJson(),
    'items': [for (final it in value.items) it.toJson()],
  };

  @override
  SimilarTo? decode(Object? raw) {
    if (raw is! Map) return null;
    final seed = SimilarSeed.fromJson(raw['seed']);
    final items = [
      for (final it in (raw['items'] as List?) ?? const [])
        ?SimilarItem.fromJson(it),
    ];
    return seed == null || items.isEmpty ? null : SimilarTo(seed, items);
  }
}
