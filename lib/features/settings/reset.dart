/// Опасная зона: сброс настроек и полный сброс — порт десктопного
/// `features/settings/lib/reset.ts`.
///
/// - [resetSettings] возвращает к умолчаниям НАСТРОЙКИ: оформление, плеер,
///   поведение, пресеты кастомизации. Библиотека, история, профиль и
///   авторизации остаются (тот же список, что `SETTINGS_KEYS` на ПК).
/// - [hardReset] стирает ВСЁ: `bloom.json` целиком (кроме флага онбординга —
///   мастер и на десктопе показывается один раз), базу `bloom.db` (библиотека,
///   журнал, подписки) и файлы на диске: офлайн-копии, кеш текстов, свои обложки
///   и скопированные внутрь треки.
///
/// Отличие от десктопа в том, ЧЕМ заканчивается сброс. Там `location.reload()`
/// перезагружает окно, и сторы поднимаются заново; окна у нас нет, поэтому
/// каждое затронутое хранилище гасится через `ref.invalidate` — Riverpod
/// пересоберёт его `build()`, а тот прочитает уже пустой `bloom.json`. Из-за
/// этого список провайдеров приходится держать руками: пропустишь один —
/// стёртая настройка останется висеть в памяти до перезапуска.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/log/bloom_log.dart';
import '../../core/db/db.dart';
import '../../core/store/app_dirs.dart';
import '../../core/store/json_store.dart';
import '../../core/store/library_store.dart';
import '../../core/store/play_log.dart';
import '../../core/store/settings_store.dart';
import '../../core/store/days_store.dart';
import '../../features/customization/custom_store.dart';
import '../../features/customization/media_store.dart';
import '../../features/customization/presets_store.dart';
import '../../features/home/for_you.dart';
import '../../features/home/similar_to.dart';
import '../../features/lastfm/lastfm_store.dart';
import '../../features/library/lib_order_store.dart';
import '../../features/library/local_tracks.dart';
import '../../features/library/pl_auto_store.dart';
import '../../features/lyrics/lyrics_store.dart';
import '../../features/offline/offline_store.dart';
import '../../features/pc/pc_store.dart';
import '../../features/player/mini_style_store.dart';
import '../../features/player/play_button_store.dart';
import '../../features/player/player_bg_store.dart';
import '../../features/player/player_controller.dart';
import '../../features/player/player_style_store.dart';
import '../../features/player/player_view_store.dart';
import '../../features/player/session_store.dart';
import '../../features/player/slider_style_store.dart';
import '../../features/player/sleep_timer_store.dart';
import '../../features/player/speed_store.dart';
import '../../features/player/track_anim_store.dart';
import '../../features/profile/achievements.dart';
import '../../features/profile/artist_avatars.dart';
import '../../features/profile/level.dart';
import '../../features/profile/profile_store.dart';
import '../../features/search/recent_store.dart';
import '../../features/wave/wave_controller.dart';
import '../../features/wave/wave_store.dart';
import '../../features/wrapped/wrapped_store.dart';
import '../../providers/yandex/ym_auth.dart';
import 'swipe_store.dart';
import 'transparency_store.dart';
import 'user_fonts.dart';

/// Ключи `bloom.json`, которые считаются НАСТРОЙКАМИ. Порядок и состав — с ПК
/// (`SETTINGS_KEYS`), с поправкой на телефонные хранилища: у нас свои ключи
/// жестов, таймера сна и стилей плеера, а `bloom_volume`/`bloom_search_source`
/// нет вовсе.
const List<String> kSettingsKeys = [
  'settings', // тема, акцент, язык, радиус, таб-бар, автовоспроизведение
  'playerView', // выравнивание подписи, вид очереди и плашка «Далее»
  'playerStyle',
  'sliderStyle',
  'miniStyle',
  'playButtonShape', // форма кнопки — одна на плеер и карточку над таб-баром
  'playerBg', // фон полноэкранного плеера — как `bloom_bg_prefs` на ПК
  'playerBgCoverFx', // и что делать с обложкой, когда она стоит этим фоном
  'trackAnim',
  'lyrics', // where the lyrics go, keeping them and for how long
  'swipes',
  'transparency',
  'speed',
  'sleep',
  'custom', // контексты кастомизации: фон, обложка, ползунок
  'coverMode', // своя обложка всегда или только у треков без обложки
  'presets', // сами пресеты — как `bloom_presets` на ПК
  'libOrder',
  'plAuto',
];

/// Вернуть настройки к умолчаниям. Библиотеку, историю, профиль и авторизации
/// не трогает.
Future<void> resetSettings(WidgetRef ref) async {
  final store = ref.read(jsonStoreProvider);
  store.removeAll(kSettingsKeys);
  await store.flush();

  ref.invalidate(settingsProvider);
  ref.invalidate(titleAlignProvider);
  ref.invalidate(queueViewProvider);
  ref.invalidate(nextUpProvider);
  ref.invalidate(playerStyleProvider);
  ref.invalidate(sliderStyleProvider);
  ref.invalidate(miniStyleProvider);
  ref.invalidate(playButtonShapeProvider);
  ref.invalidate(playerBgProvider);
  ref.invalidate(coverBgFxProvider);
  ref.invalidate(trackAnimProvider);
  ref.invalidate(lyricsPrefsProvider);
  ref.invalidate(swipeProvider);
  ref.invalidate(transparencyProvider);
  ref.invalidate(speedProvider);
  ref.invalidate(sleepTimerProvider);
  ref.invalidate(customProvider);
  ref.invalidate(coverModeProvider);
  ref.invalidate(presetsProvider);
  ref.invalidate(libOrderProvider);
  ref.invalidate(plAutoProvider);
  // Расписание авто-обновления заводится в `main()` руками, а не в `build()`
  // стора: пересобранный стор остался бы без таймера до перезапуска.
  ref.read(plAutoProvider.notifier).startScheduler();

  logInfo('reset', 'настройки сброшены к умолчаниям');
}

/// Стереть всё. Возврата нет — вызывать только после подтверждения.
Future<void> hardReset(WidgetRef ref) async {
  // Сначала тишина: дальше исчезнут и файлы офлайн-копий, и очередь.
  await ref.read(audioHandlerProvider).stop();

  // Свои треки — до чистки библиотеки: после неё уже не узнать, за каким id
  // стояло постоянное разрешение SAF и копия внутри приложения (их лимит на
  // приложение — 512, и не вернуть их нельзя).
  final lib = ref.read(libraryProvider);
  await forgetLocalTracks(lib.tracks.values);

  final store = ref.read(jsonStoreProvider);
  store.removeAll([...store.keys]);
  await store.flush();
  ref.read(dbProvider).wipe();

  // Каталоги сносим целиком и заводим заново: по одному индексу их содержимое
  // уже не обойти — сам индекс мы только что стёрли.
  // `fonts` — свои шрифты: на ПК полный сброс тоже сносит `bloom_fonts`, а
  // сброс настроек их не трогает.
  await _wipeDirs(['offline', 'covers', 'tracks', 'fonts']);
  ref.invalidate(userFontsProvider);

  ref.invalidate(playbackProvider);
  ref.invalidate(sessionProvider);
  ref.invalidate(libraryProvider);
  ref.invalidate(playLogProvider);
  // Витрины главной — их кэш лежал там же и собран по стёртому топу.
  ref.invalidate(forYouProvider);
  ref.invalidate(similarToProvider);
  ref.invalidate(daysProvider);
  // Отметки достижений и отложенные XP читаются из kv один раз: без этого
  // старые отметки висели бы в памяти и первая же сверка записала бы их назад.
  ref.invalidate(unlockedAchievementsProvider);
  ref.invalidate(levelBankedProvider);
  ref.invalidate(profileSinceProvider);
  ref.invalidate(profileProvider);
  ref.invalidate(recentSearchesProvider);
  // Открытые карточки — отдельный стор от запросов: без этой строки ключ
  // `recentItems` с диска исчезал, а список висел в памяти до перезапуска, и
  // первое же открытие сущности записывало всю стёртую историю обратно.
  ref.invalidate(recentItemsProvider);
  // Кеш аватарок артистов — тот же случай, что тексты и обложки: сущностей,
  // ради которых он собран, больше нет.
  ref.invalidate(artistAvatarsProvider);
  ref.invalidate(offlineProvider);
  ref.invalidate(mediaLibProvider);
  ref.invalidate(waveProvider);
  ref.invalidate(waveStoreProvider);
  ref.invalidate(lastfmProvider);
  ref.invalidate(ymAuthProvider);
  // The kept lyrics went with the database; the missed ones live in memory.
  ref.invalidate(lyricsCacheProvider);
  ref.invalidate(lyricsProvider);
  // Тумблеры и отметки просмотра «Итогов» лежат в `bloom.json` под ключом
  // `wrapped`: сам ключ уже стёрт, гасим стор, чтобы он не висел в памяти до
  // перезапуска.
  ref.invalidate(wrappedPrefsProvider);
  // Связка с ПК жила в стёртой базе. Не invalidate: расписание кругов заведено
  // в `main()` и пересобранный стор остался бы без него.
  ref.read(pcProvider.notifier).unpair();
  await resetSettings(ref);

  logInfo('reset', 'полный сброс: библиотека, настройки и файлы стёрты');
}

/// Снести и создать заново каталоги в служебной папке приложения.
Future<void> _wipeDirs(List<String> names) async {
  final root = await appPrivateDir();
  for (final name in names) {
    final dir = Directory('${root.path}/$name');
    try {
      if (dir.existsSync()) await dir.delete(recursive: true);
      await dir.create(recursive: true);
    } catch (e) {
      // Файл занят проигрывателем или нет прав — остальные каталоги это не
      // отменяет, а мусор в одном не стоит падения посреди сброса.
      logWarn('reset', 'каталог $name не стёрся: $e');
    }
  }
}
