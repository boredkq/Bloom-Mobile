/// Bridge between the player and the system: notification shade, lock screen,
/// headset buttons, background playback.
///
/// The handler is DUMB on purpose: it owns [AudioPlayer] and broadcasts its
/// state but decides nothing. Any outside command goes to [PlaybackCommands],
/// so next in the shade and next in the app play the same thing.
///
/// It owns the player because playback must outlive the UI: Flutter's engine
/// can be killed while the service stays.
library;

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/entities/entities.dart';
import '../../core/l10n/l10n.dart';
import '../../core/log/bloom_log.dart';

/// What the handler can ask of the player. `PlaybackController` implements it.
abstract class PlaybackCommands {
  Future<void> commandPlay();
  Future<void> commandPause();
  Future<void> commandNext();
  Future<void> commandPrev();
  Future<void> commandStop();
  Future<void> commandSkipTo(int index);
  Future<void> commandToggleFav();
}

/// Name of the like button, returned to [BloomAudioHandler.customAction].
const _favAction = 'fav';

/// iOS: the lock screen star. audio_service shows no custom buttons there, so
/// the like goes past it through the system `likeCommand`.
const _iosLike = MethodChannel('bloom/like');

class BloomAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer player = AudioPlayer();

  /// Set by the controller at launch. Before that there's nothing to play, so
  /// no outside commands.
  PlaybackCommands? commands;

  /// I resolve the stream link BEFORE `setUrl`, with just_audio sitting `idle`
  /// all the while. Without this flag the shade would show a stopped player
  /// mid-change.
  bool _resolving = false;

  /// The playing track is a favourite: the shade's heart is filled.
  bool _fav = false;

  BloomAudioHandler() {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      _iosLike.setMethodCallHandler((call) async {
        if (call.method == 'toggle') await customAction(_favAction);
      });
    }
    player.playbackEventStream.listen(
      _broadcast,
      onError: (Object e, StackTrace st) {
        // The only place that hears about a failure of ExoPlayer itself; the
        // rest of the app just sees a track not starting.
        logError('player', 'playback failure', e);
        _broadcast(player.playbackEvent);
      },
    );
    // `playing` changes with no playbackEvent, or the shade's button sticks.
    player.playingStream.listen((_) => _broadcast(player.playbackEvent));
  }

  static const _stateMap = {
    ProcessingState.idle: AudioProcessingState.idle,
    ProcessingState.loading: AudioProcessingState.loading,
    ProcessingState.buffering: AudioProcessingState.buffering,
    ProcessingState.ready: AudioProcessingState.ready,
    ProcessingState.completed: AudioProcessingState.completed,
  };

  /// What went to the shade last, so the log gets only changes.
  String? _lastReported;

  void _broadcast(PlaybackEvent event) {
    // The player pauses on purpose while resolving, so the last track doesn't
    // play on, but to the shade it's still playing: the button would blink on
    // every change.
    final playing = _resolving || player.playing;
    // Every state change goes to the log, straight to disk. This is the last
    // point Dart sees before it all goes native: on `playing=true` the system
    // takes the service to the foreground and shows the shade, and if the
    // process dies there, the log ends at this line with no error.
    final report = '${player.processingState.name} · playing=$playing';
    if (report != _lastReported) {
      _lastReported = report;
      logInfo('player', 'player: $report', now: true);
    }
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          // A custom action rather than a notification button: audio_service
          // puts it in the session's custom actions, and the system builds the
          // shade from them. Android 13+; older versions have no button.
          MediaControl.custom(
            androidIcon: _fav
                ? 'drawable/ic_notif_heart_filled'
                : 'drawable/ic_notif_heart',
            label: _fav
                ? globalL10n?.taRemoveFromFavorites ?? 'Remove from likes'
                : globalL10n?.taAddToFavorites ?? 'Like',
            name: _favAction,
          ),
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        // Three buttons in the collapsed shade.
        androidCompactActionIndices: const [0, 1, 2],
        processingState: _resolving
            ? AudioProcessingState.loading
            : _stateMap[player.processingState]!,
        playing: playing,
        updatePosition: player.position,
        bufferedPosition: player.bufferedPosition,
        speed: player.speed,
        queueIndex: event.currentIndex,
      ),
    );
  }

  /// The controller says it went off to resolve a link, or finished.
  void setResolving(bool value) {
    if (_resolving == value) return;
    _resolving = value;
    _broadcast(player.playbackEvent);
  }

  /// The controller says whether the playing track is a favourite.
  void setFav(bool value) {
    if (_fav == value) return;
    _fav = value;
    _broadcast(player.playbackEvent);
    if (defaultTargetPlatform == TargetPlatform.iOS) unawaited(_syncIosLike());
  }

  Future<void> _syncIosLike() async {
    try {
      await _iosLike.invokeMethod<void>('set', {
        'active': _fav,
        'title': _fav
            ? globalL10n?.taRemoveFromFavorites ?? 'Remove from likes'
            : globalL10n?.taAddToFavorites ?? 'Like',
      });
    } on PlatformException {
      // The channel didn't answer: the star just won't update.
    } on MissingPluginException {
      // Tests.
    }
  }

  /// What the shade and lock screen show.
  void setTrack(Track? track, {int? queueIndex}) {
    if (track == null) {
      mediaItem.add(null);
      return;
    }
    mediaItem.add(_toMediaItem(track));
    if (queueIndex != null) {
      playbackState.add(playbackState.value.copyWith(queueIndex: queueIndex));
    }
  }

  /// The whole queue, seen by Android Auto and the shade's list.
  void setQueue(List<Track> tracks) {
    queue.add(tracks.map(_toMediaItem).toList());
  }

  MediaItem _toMediaItem(Track track) => MediaItem(
    id: track.id,
    title: track.name,
    artist: track.artist,
    album: track.album,
    // Zero from a platform means unknown: passing it on gives the shade a dead
    // progress bar.
    duration: track.duration > Duration.zero ? track.duration : null,
    artUri: _artUri(track.cover),
  );

  Uri? _artUri(String? cover) {
    if (cover == null || cover.isEmpty) return null;
    if (cover.startsWith('http')) return Uri.tryParse(cover);
    return Uri.file(cover);
  }

  // All below comes from OUTSIDE: shade, lock screen, headset. The fallback to
  // the bare player covers a command before the controller connects.

  @override
  Future<void> play() => commands?.commandPlay() ?? player.play();

  @override
  Future<void> pause() => commands?.commandPause() ?? player.pause();

  @override
  Future<void> skipToNext() async => commands?.commandNext();

  @override
  Future<void> skipToPrevious() async => commands?.commandPrev();

  @override
  Future<void> skipToQueueItem(int index) async =>
      commands?.commandSkipTo(index);

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    if (name == _favAction) return commands?.commandToggleFav();
    return super.customAction(name, extras);
  }

  @override
  Future<void> stop() async {
    await commands?.commandStop();
    await player.stop();
    await super.stop();
  }

  /// The app was swiped from recents: I stop the sound and remove the shade, or
  /// a closed app keeps a playing notification.
  @override
  Future<void> onTaskRemoved() => stop();
}
