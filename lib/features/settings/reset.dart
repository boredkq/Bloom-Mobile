/// The danger zone.
///
/// [resetSettings] brings the settings back to defaults; the library, history,
/// profile and sign-ins stay. [hardReset] wipes it all: `bloom.json`, the
/// database and the files on disk.
///
/// Each store is rebuilt with `ref.invalidate`, reading what's now empty, so
/// the list of providers is kept by hand: one missed and a wiped setting hangs
/// in memory until restart.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/log/bloom_log.dart';
import '../../core/db/db.dart';
import '../../core/store/app_dirs.dart';
import '../../core/store/cover_cache.dart';
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

/// The `bloom.json` keys that count as settings.
const List<String> kSettingsKeys = [
  'settings', // theme, accent, language, tab bar, autoplay
  'playerView', // title alignment, queue look, next up
  'playerStyle',
  'sliderStyle',
  'miniStyle',
  'playButtonShape', // one for the player and the mini player
  'playerBg', // the full player's background
  'playerBgCoverFx', // what's done to a cover standing as it
  'covers', // how long downloaded covers stay
  'lyrics', // where the lyrics go, keeping them and for how long
  'swipes',
  'transparency',
  'speed',
  'sleep',
  'custom', // customization's places: background, cover, slider
  'coverMode', // one's own cover always, or only when none
  'presets', // customization presets
  'libOrder',
  'plAuto',
];

/// The library, history, profile and sign-ins stay.
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
  ref.invalidate(coverKeepProvider);
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
  // The schedule is started by hand at launch, not in the store's `build`: a
  // rebuilt store would be left without its timer until restart.
  ref.read(plAutoProvider.notifier).startScheduler();

  logInfo('reset', 'settings reset to defaults');
}

/// No way back: call only after confirming.
Future<void> hardReset(WidgetRef ref) async {
  // Silence first: the offline files and the queue are about to go.
  await ref.read(audioHandlerProvider).stop();

  // Before clearing the library: after it there's no telling which id held a
  // persistent SAF permission and a copy inside the app (limited to 512, they
  // must be given back).
  final lib = ref.read(libraryProvider);
  await forgetLocalTracks(lib.tracks.values);

  final store = ref.read(jsonStoreProvider);
  store.removeAll([...store.keys]);
  await store.flush();
  ref.read(dbProvider).wipe();

  // Whole folders, made anew: their index was just wiped, so there's no walking
  // through it. `fonts` goes only here, a settings reset leaves them.
  await _wipeDirs(['offline', 'covers', 'tracks', 'fonts']);
  await clearCoverCache();
  ref.invalidate(userFontsProvider);

  ref.invalidate(playbackProvider);
  ref.invalidate(sessionProvider);
  ref.invalidate(libraryProvider);
  ref.invalidate(playLogProvider);
  // Their cache was built from a wiped top.
  ref.invalidate(forYouProvider);
  ref.invalidate(similarToProvider);
  ref.invalidate(daysProvider);
  // Read once from kv: otherwise old marks hang in memory and the first check
  // writes them back.
  ref.invalidate(unlockedAchievementsProvider);
  ref.invalidate(levelBankedProvider);
  ref.invalidate(profileSinceProvider);
  ref.invalidate(profileProvider);
  ref.invalidate(recentSearchesProvider);
  // Apart from the queries: without this the wiped list stays in memory and the
  // first opening writes it all back.
  ref.invalidate(recentItemsProvider);
  // What it was built for is gone.
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
  // The reviews' marks went with the database.
  ref.invalidate(wrappedMarksProvider);
  // The link lived in the wiped database. Not invalidate: rounds are scheduled
  // at launch, a rebuilt store would lose them.
  ref.read(pcProvider.notifier).unpair();
  await resetSettings(ref);

  logInfo('reset', 'full reset: library, settings and files erased');
}

Future<void> _wipeDirs(List<String> names) async {
  final root = await appPrivateDir();
  for (final name in names) {
    final dir = Directory('${root.path}/$name');
    try {
      if (dir.existsSync()) await dir.delete(recursive: true);
      await dir.create(recursive: true);
    } catch (e) {
      // A busy file or no rights: the other folders still go, and litter isn't
      // worth failing in the middle of a reset.
      logWarn('reset', 'folder $name not erased: $e');
    }
  }
}
