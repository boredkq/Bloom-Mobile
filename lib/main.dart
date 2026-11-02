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
  // Portrait only: the layout is built for a narrow screen and falls apart in
  // landscape. Android's manifest says the same; this is for iOS and in case
  // the system hands the activity over sideways.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // The log opens first, so it catches what happens to the other stores.
  await BloomLog.instance.open();
  _catchUnhandled();
  logInfo('app', 'start · ${Platform.operatingSystemVersion}');
  // The store is read BEFORE the first frame, or the library and theme blink
  // empty and screens need loading states.
  final store = await _step('bloom.json', JsonStore.open);
  // The listener's data: library, play log, follows.
  final db = await _step('bloom.db', BloomDb.open);
  // User fonts before the first frame, or the chosen one flashes as Inter.
  await _step('fonts', () => initUserFonts(store));
  await _step('covers', initCoverStore);
  await _step('cover cache', initCoverCache);
  await _step('offline', initOfflineStore);
  await _step('own tracks', initLocalTracks);

  // The notification channel is created BEFORE the first frame, so there's no
  // `context.l` yet and I load translations from the delegate directly, in the
  // language the app will show.
  //
  // Android remembers the channel's name at creation: after a language change
  // it updates on the next launch.
  final saved = readSavedLocale(store.readMap('settings'));
  final l10n = await _step(
    'translations',
    () => AppLocalizations.delegate.load(
      saved ??
          basicLocaleListResolution(
            PlatformDispatcher.instance.locales,
            AppLocalizations.supportedLocales,
          ),
    ),
  );

  final handler = await _initAudioService(l10n);

  // I create the container by hand to touch playbackProvider BEFORE the first
  // frame: the controller must subscribe to the handler at once, or shade
  // buttons lead nowhere until the player opens.
  final container = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(store),
      dbProvider.overrideWithValue(db),
      audioHandlerProvider.overrideWithValue(handler),
    ],
  );
  container.read(playbackProvider);
  // Kept lyrics past their time go at launch.
  container
      .read(lyricsCacheProvider)
      .start(container.read(lyricsPrefsProvider).keep);
  unawaited(startCoverCache(container.read(coverKeepProvider)));
  // Scrobbles left from the last run go out by themselves.
  container.read(lastfmProvider);
  // The Yandex token comes up right away: until the store exists the platform
  // counts as off and the first search would skip it.
  container.read(ymAuthProvider);
  // The auto accent bridge lives as long as the process: the colour follows the
  // cover always, not only on one settings page.
  container.read(autoAccentProvider);
  // Today's visit and app time from the first second. Lives until the process
  // ends.
  UsageTracker(container.read(daysProvider.notifier)).start();
  // Playlist auto-update schedule. The timer lives as long as the process:
  // nothing can wake a closed app, but the next launch sees an overdue period
  // by `lastRun`.
  container.read(plAutoProvider.notifier).startScheduler();
  // Sync with the paired computer: at launch, on return and now and then.
  container.read(pcProvider.notifier).start();
  // A picture from another device can be shared by two playlists or a playlist
  // and the profile, so a file goes only when nothing refers to it.
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

  // Restoring the last session waits for the first frame: resolving a stream
  // hits the network and asks for notification permission, with no reason to
  // hold an empty screen.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    // Pairs with every `→` above: launch reached the screen. A log without this
    // line means stuck on the splash, and the last step with no `✓` says where.
    logInfo('boot', '✓ first frame');
    _restoreSession(container);
  });
}

/// A launch step with marks in the log: `→ name` before, `✓ name (N ms)` after.
/// All of launch happens before the first frame, so whatever hangs or throws
/// leaves the user on the splash forever, with nothing on screen to tell. An
/// unclosed `→` shows the place.
Future<T> _step<T>(String name, Future<T> Function() run) async {
  logInfo('boot', '→ $name');
  final started = DateTime.now();
  final result = await run();
  final took = DateTime.now().difference(started).inMilliseconds;
  logInfo('boot', '✓ $name ($took ms)');
  return result;
}

/// How long I wait for the audio service before starting without it. Far above
/// what a live system needs (tens of ms), and below what anyone will watch a
/// splash for.
const Duration _audioInitTimeout = Duration(seconds: 12);

/// One handler per process. [AudioService.init] may answer after I gave up; its
/// `builder` then runs late, and a second [BloomAudioHandler] would mean a
/// second `AudioPlayer` playing on top.
BloomAudioHandler? _audioHandler;
BloomAudioHandler _buildAudioHandler() => _audioHandler ??= BloomAudioHandler();

/// Brings up the playback service: shade, lock screen, background music. It has
/// a timeout because the service outlives the app: on the next launch the
/// plugin binds to the running one and waits for `onConnected`. If the system
/// froze it (Samsung is eager), no answer ever comes: `AudioService.init`
/// neither throws nor finishes and the splash stays until a reboot.
///
/// If it fails I start without it: sound plays, with no shade or background
/// playback. Far better than an app that won't open.
Future<BloomAudioHandler> _initAudioService(AppLocalizations l10n) async {
  try {
    return await _step(
      'audio service',
      () => AudioService.init(
        builder: _buildAudioHandler,
        config: AudioServiceConfig(
          androidNotificationChannelId: 'com.bxzlik.bloom.playback',
          androidNotificationChannelName: l10n.notifChannelName,
          androidNotificationChannelDescription: l10n.notifChannelDescription,
          // Only the pair ongoing and stopForegroundOnPause works: the shade
          // can't be swiped while playing, but can on pause.
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
          androidNotificationIcon: 'drawable/ic_stat_bloom',
        ),
      ).timeout(_audioInitTimeout),
    );
  } on TimeoutException {
    logError(
      'boot',
      'the audio service did not answer in ${_audioInitTimeout.inSeconds} s: '
          'starting without it (no notification or background play)',
    );
  } catch (e) {
    logError('boot', 'the audio service did not start: starting without it', e);
  }
  return _buildAudioHandler();
}

/// Unhandled errors go to the log. Two doors: `FlutterError.onError` for the
/// widget tree, `PlatformDispatcher.onError` for the rest (dropped `Future`s).
/// Default behaviour stays: errors still print to the console.
void _catchUnhandled() {
  final presentError = FlutterError.onError;
  FlutterError.onError = (details) {
    logError('flutter', details.exceptionAsString(), details.stack?.toString());
    presentError?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    logError('dart', '$error', stack);
    return false; // false lets the platform handle it as usual
  };
}

/// Restores the last session's track, queue and position. Off by default: the
/// system kills the app constantly, and raising the queue silently on every
/// launch isn't my call.
void _restoreSession(ProviderContainer container) {
  final settings = container.read(settingsProvider);
  if (!settings.restoreQueue) return;
  final data = container.read(sessionProvider);
  // A cleared queue doesn't come back into the player.
  if (data == null || data.cleared) return;
  logInfo(
    'player',
    'restoring the session: ${data.track.name} '
        '(${settings.autoplay ? 'playing' : 'paused'})',
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
    // The background picture lies UNDER the UI, and only those that must let it
    // through drop their fill: router pages, the shell, artist and set pages
    // (see `pageBackground`). The full player and sheets over it stay solid:
    // the background isn't wanted in the player.
    final bgOn = ref.watch(backgroundOnProvider);
    // System bars follow the theme, or white status icons vanish on light.
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
      // `locale: null` takes the system's language, matched against
      // supportedLocales, where English comes first and so acts as the
      // fallback. A language picked by hand is passed explicitly.
      locale: ref.watch(settingsProvider).locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // My own messenger key: toasts can come with no screen, from playlist
      // auto-update's timer.
      scaffoldMessengerKey: bloomMessengerKey,
      scrollBehavior: const _SpringScroll(),
      theme: buildBloomTheme(
        tokens,
        transparentPages: bgOn,
        fontFamily: ref.watch(uiFontProvider),
      ),
      // The background goes under the navigator: one for the whole app, neither
      // repainted per transition nor moving with a page.
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
