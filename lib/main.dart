import 'dart:async' show TimeoutException, unawaited;
import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'app/welcome.dart';
import 'app/theme/bloom_theme.dart';
import 'core/l10n/l10n.dart';
import 'core/log/bloom_log.dart';
import 'core/db/db.dart';
import 'core/store/cover_cache.dart';
import 'core/store/cover_store.dart';
import 'core/store/json_store.dart';
import 'core/store/settings_store.dart';
import 'core/store/days_store.dart';
import 'features/lastfm/lastfm_store.dart';
import 'features/customization/ui/app_background.dart';
import 'features/library/local_tracks.dart';
import 'features/library/pl_auto_store.dart';
import 'features/lyrics/lyrics_store.dart';
import 'features/offline/offline_store.dart';
import 'features/pc/pc_store.dart';
import 'features/player/audio_handler.dart';
import 'features/player/player_controller.dart';
import 'features/player/session_store.dart';
import 'features/settings/auto_accent.dart';
import 'features/settings/user_fonts.dart';
import 'providers/yandex/ym_auth.dart';
import 'shared/ui/bloom_toast.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Только портрет. Вся вёрстка считана под узкий экран, и в ландшафте она
  // разъезжается — с этим замком приложение, открытое с телефона на боку,
  // само разворачивается обратно. На Android то же самое стоит в манифесте
  // (там разворот происходит ещё до старта движка), здесь — ради iOS и на
  // случай, если система всё же отдаст активити лежащей.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // Журнал работы поднимаем первым — чтобы в него попало и то, что случится с
  // остальными хранилищами (`Настройки → Система → Логи`).
  await BloomLog.instance.open();
  _catchUnhandled();
  logInfo('app', 'запуск · ${Platform.operatingSystemVersion}');
  // Хранилище читаем ДО первого кадра: иначе библиотека и тема моргнут
  // пустыми, а экраны придётся городить с состояниями загрузки.
  final store = await _step('bloom.json', JsonStore.open);
  // Данные слушателя — база, как на ПК: библиотека, журнал, подписки.
  final db = await _step('bloom.db', BloomDb.open);
  // Свои шрифты — до первого кадра: иначе выбранный мелькнёт Inter.
  await _step('шрифты', () => initUserFonts(store));
  await _step('обложки', initCoverStore);
  await _step('кеш обложек', initCoverCache);
  await _step('офлайн', initOfflineStore);
  await _step('свои треки', initLocalTracks);

  // Канал уведомлений заводится ДО первого кадра, поэтому `context.l` тут ещё
  // неоткуда взять — переводы грузим напрямую из делегата. Язык тот же, что
  // потом увидит приложение: сохранённый, а если не выбирали — системный.
  //
  // Название канала Android запоминает при создании и позже само не меняет:
  // после смены языка в настройках оно обновится со следующего запуска.
  final saved = readSavedLocale(store.readMap('settings'));
  final l10n = await _step(
    'переводы',
    () => AppLocalizations.delegate.load(
      saved ??
          basicLocaleListResolution(
            PlatformDispatcher.instance.locales,
            AppLocalizations.supportedLocales,
          ),
    ),
  );

  final handler = await _initAudioService(l10n);

  // Контейнер создаём руками, чтобы дёрнуть playbackProvider ДО первого кадра:
  // контроллер должен подписаться на хендлер сразу, иначе кнопки в шторке до
  // открытия плеера ведут в никуда.
  final container = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(store),
      dbProvider.overrideWithValue(db),
      audioHandlerProvider.overrideWithValue(handler),
    ],
  );
  container.read(playbackProvider);
  // Kept lyrics past their time go at launch, as `Lyrics::start` on the PC.
  container
      .read(lyricsCacheProvider)
      .start(container.read(lyricsPrefsProvider).keep);
  unawaited(startCoverCache(container.read(coverKeepProvider)));
  // Scrobbles left from the last run go out by themselves.
  container.read(lastfmProvider);
  // Токен Яндекса поднимаем сразу: пока стор не создан, площадка считается
  // выключенной и первый же поиск прошёл бы мимо неё.
  container.read(ymAuthProvider);
  // Мост авто-акцента живёт столько же, сколько процесс: цвет должен ехать за
  // обложкой всегда, а не только пока открыт экран «Интерфейс».
  container.read(autoAccentProvider);
  // Сегодняшний визит и время в приложении — с первой же секунды, как
  // `Stats::start` на ПК. Живёт до конца процесса, снимать его некому и незачем.
  UsageTracker(container.read(daysProvider.notifier)).start();
  // Расписание авто-обновления плейлистов — как `startPlAutoScheduler` на ПК.
  // Таймер живёт столько же, сколько процесс: разбудить закрытое приложение
  // нечем, зато при следующем запуске просроченный период виден по `lastRun`.
  container.read(plAutoProvider.notifier).startScheduler();
  // Синхронизация с ПК, если он сопряжён: при запуске, по возвращении и
  // время от времени — «Настройки → Компьютер».
  container.read(pcProvider.notifier).start();
  // Картинку с ПК могут делить два плейлиста или плейлист и профиль: файл
  // удаляется, только когда на него никто не ссылается.
  coverInUse = (cover) {
    if (db.value(
          'SELECT 1 FROM lists WHERE cover = ? UNION ALL SELECT 1 FROM tracks WHERE cover = ? LIMIT 1',
          [cover, cover],
        ) !=
        null) {
      return true;
    }
    final card = db.getMap('profile');
    return card['avatar'] == cover || card['banner'] == cover;
  };

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: BloomApp(firstRun: takeFirstRun(db)),
    ),
  );

  // Восстановление прошлой сессии — после первого кадра: резолв стрима идёт в
  // сеть и просит разрешение на уведомления, и держать ради этого пустой экран
  // незачем.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    // Парная отметка ко всем `→` выше: запуск дошёл до экрана. Строка «запуск»
    // без неё в журнале и означает «застряли на сплеше» — а на чём именно,
    // видно по последнему шагу, у которого нет своей `✓`.
    logInfo('boot', '✓ первый кадр');
    _restoreSession(container);
  });
}

/// Шаг запуска с отметками в журнале: `→ имя` перед началом, `✓ имя (N мс)`
/// после.
///
/// Весь запуск идёт ДО первого кадра, поэтому что здесь зависнет или бросит —
/// то и оставит человека на сплеше навсегда, и понять по экрану ничего нельзя.
/// Пары отметок и хватает: незакрытая `→` показывает и место сбоя, и то,
/// сколько шаг успел прожить.
Future<T> _step<T>(String name, Future<T> Function() run) async {
  logInfo('boot', '→ $name');
  final started = DateTime.now();
  final result = await run();
  final took = DateTime.now().difference(started).inMilliseconds;
  logInfo('boot', '✓ $name ($took мс)');
  return result;
}

/// Сколько ждём аудио-службу, прежде чем запуститься без неё.
///
/// Двенадцать секунд — заведомо больше, чем нужно живой системе (обычные
/// десятки миллисекунд), и заведомо меньше, чем человек согласен смотреть на
/// сплеш.
const Duration _audioInitTimeout = Duration(seconds: 12);

/// Хендлер один на процесс.
///
/// [AudioService.init] может ответить и после того, как мы устали ждать, —
/// тогда `builder` позовут запоздало, и второй [BloomAudioHandler] означал бы
/// второй `AudioPlayer`, то есть второй звук поверх первого.
BloomAudioHandler? _audioHandler;
BloomAudioHandler _buildAudioHandler() => _audioHandler ??= BloomAudioHandler();

/// Поднять службу воспроизведения — шторка, экран блокировки, фоновая музыка.
///
/// Отдельно от `main()` и под защитой не от красоты: служба живёт дольше
/// приложения, и в следующий запуск мы приходим к УЖЕ работающей — плагин
/// биндится к ней и ждёт `onConnected`. Если система эту службу подморозила
/// (Samsung усыпляет приложения охотнее прочих), ответа не будет никогда:
/// `AudioService.init` не бросает и не завершается, а мы стоим на сплеше до
/// перезагрузки телефона. Отсюда и таймаут.
///
/// Не поднялась — запускаемся без неё: звук играет (плеер-то наш, внутри
/// хендлера), нет шторки и фонового воспроизведения. Это несравнимо лучше
/// приложения, которое не открывается вовсе.
Future<BloomAudioHandler> _initAudioService(AppLocalizations l10n) async {
  try {
    return await _step(
      'аудио-служба',
      () => AudioService.init(
        builder: _buildAudioHandler,
        config: AudioServiceConfig(
          androidNotificationChannelId: 'com.bxzlik.bloom.playback',
          androidNotificationChannelName: l10n.notifChannelName,
          androidNotificationChannelDescription: l10n.notifChannelDescription,
          // Пара «ongoing + stopForegroundOnPause» — единственная рабочая:
          // шторку нельзя смахнуть, пока играет, но на паузе она снова
          // смахивается.
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
          androidNotificationIcon: 'drawable/ic_stat_bloom',
        ),
      ).timeout(_audioInitTimeout),
    );
  } on TimeoutException {
    logError(
      'boot',
      'аудио-служба не ответила за ${_audioInitTimeout.inSeconds} с — '
          'запускаюсь без неё (шторки и фона не будет)',
    );
  } catch (e) {
    logError('boot', 'аудио-служба не поднялась — запускаюсь без неё', e);
  }
  return _buildAudioHandler();
}

/// Необработанные ошибки — в журнал работы.
///
/// Обе двери: `FlutterError.onError` ловит падения в дереве виджетов,
/// `PlatformDispatcher.onError` — всё остальное (оборванные `Future`).
/// Поведение по умолчанию сохраняем: ошибка как печаталась в консоль, так и
/// печатается, журнал только запоминает её.
void _catchUnhandled() {
  final presentError = FlutterError.onError;
  FlutterError.onError = (details) {
    logError('flutter', details.exceptionAsString(), details.stack?.toString());
    presentError?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    logError('dart', '$error', stack);
    return false; // false — пусть платформа обработает её как обычно
  };
}

/// Вернуть трек, очередь и позицию прошлой сессии — «Настройки → Аудио».
///
/// Выключено по умолчанию: телефон приложение убивает постоянно, и молча
/// поднимать очередь на каждом запуске мы не вправе. Карточка «Продолжить» на
/// главной работает и без этой настройки — просто по нажатию.
void _restoreSession(ProviderContainer container) {
  final settings = container.read(settingsProvider);
  if (!settings.restoreQueue) return;
  final data = container.read(sessionProvider);
  // Очередь очистили — в плеер её не поднимаем, «Продолжить» остаётся.
  if (data == null || data.cleared) return;
  logInfo(
    'player',
    'восстанавливаю сессию: ${data.track.name} '
        '(${settings.autoplay ? 'играем' : 'на паузе'})',
  );
  unawaited(
    container
        .read(playbackProvider.notifier)
        .resumeSession(data, autoplay: settings.autoplay),
  );
}

class BloomApp extends ConsumerWidget {
  const BloomApp({super.key, this.firstRun = false});

  /// Show the word of welcome over the app.
  final bool firstRun;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(settingsProvider).tokens;
    // Картинка фона живёт ПОД интерфейсом, и заливку снимают ровно те, кто
    // обязан её пропустить: страницы роутера, каркас и страницы артиста и
    // сета (см. `pageBackground`). Полноэкранный плеер и шторки поверх него
    // остаются сплошными — фон в плеере пользователь видеть не хочет.
    final bgOn = ref.watch(backgroundOnProvider);
    // Системные бары красим под тему — иначе на светлой теме белые иконки
    // статус-бара исчезают.
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: tokens.isLight
            ? Brightness.dark
            : Brightness.light,
        systemNavigationBarColor: tokens.bg,
        systemNavigationBarIconBrightness: tokens.isLight
            ? Brightness.dark
            : Brightness.light,
      ),
    );

    return MaterialApp.router(
      title: 'Bloom',
      debugShowCheckedModeBanner: false,
      // `locale: null` — язык берётся у системы и матчится с supportedLocales,
      // где английский стоит первым и потому работает запасным. Как только
      // язык выбран руками, отдаём его явно.
      locale: ref.watch(settingsProvider).locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Свой ключ мессенджера: тосты бывают и без экрана — авто-обновление
      // плейлистов ходит по таймеру.
      scaffoldMessengerKey: bloomMessengerKey,
      scrollBehavior: const _SpringScroll(),
      theme: buildBloomTheme(
        tokens,
        transparentPages: bgOn,
        fontFamily: ref.watch(uiFontProvider),
      ),
      // Фон — под навигатором: он один на всё приложение и не должен ни
      // перерисовываться на каждом переходе, ни ехать вместе со страницей.
      builder: (_, child) => Welcome(
        show: firstRun,
        child: AppBackground(child: child ?? const SizedBox()),
      ),
      routerConfig: bloomRouter,
    );
  }
}

/// The iPhone's springy edge on every phone: Android's stretch goes.
class _SpringScroll extends MaterialScrollBehavior {
  const _SpringScroll();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: RangeMaintainingScrollPhysics());

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}
