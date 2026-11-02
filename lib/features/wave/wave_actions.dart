/// Starting the wave from the UI: the one point where [WaveStartResult] becomes
/// a toast. The controller knows nothing of toasts, and the failure text is
/// shared by all screens starting a wave.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/entities/entities.dart';
import '../../core/l10n/l10n.dart';
import '../../shared/ui/bloom_toast.dart';
import 'wave_controller.dart';
import 'wave_store.dart';

/// Whether a track's platform has a radio. Wave by track shows only for those:
/// elsewhere it would open a menu to refuse.
bool canStartWaveFrom(WidgetRef ref, Track track) =>
    ref.read(waveProvider.notifier).seedOf(track) != null;

/// Whether a wave can start from an artist: an artist station on Yandex,
/// elsewhere the radio of at least one loaded track.
bool canStartWaveFromArtist(
  WidgetRef ref,
  Artist artist,
  List<Track> knownTracks,
) {
  if (artist.source == MusicSource.yandex) return true;
  final wave = ref.read(waveProvider.notifier);
  return knownTracks.any((t) => wave.seedOf(t) != null);
}

/// My wave.
Future<void> startPersonalWave(BuildContext context, WidgetRef ref) =>
    _run(context, ref, (wave) => wave.startPersonal());

/// Wave by track. [seedFirst] starts with the track itself.
Future<void> startWaveFromTrack(
  BuildContext context,
  WidgetRef ref,
  Track track, {
  bool seedFirst = false,
}) => _run(
  context,
  ref,
  (wave) => wave.startByTrack(track, seedFirst: seedFirst),
);

/// Similar to queue. With no list it takes what's playing now.
Future<void> startWaveFromQueue(
  BuildContext context,
  WidgetRef ref, [
  List<Track>? tracks,
]) => _run(context, ref, (wave) => wave.startByQueue(tracks));

/// Wave by artist. [seedTracks] is what their page already loaded.
Future<void> startWaveFromArtist(
  BuildContext context,
  WidgetRef ref,
  Artist artist, {
  List<Track> seedTracks = const [],
}) => _run(
  context,
  ref,
  (wave) => wave.startByArtist(artist, seedTracks: seedTracks),
);

/// A wave in the style of [name], one of [track]'s artists.
Future<void> startWaveFromArtistName(
  BuildContext context,
  WidgetRef ref,
  Track track,
  String name,
) => _run(context, ref, (wave) => wave.startByArtistName(track, name));

/// Shakes up My Wave (starts it, when it isn't on).
Future<void> shakeWave(BuildContext context, WidgetRef ref) =>
    _run(context, ref, (wave) => wave.shake());

/// Stops the wave: the queue plays out, but loads no more.
void stopWave(BuildContext context, WidgetRef ref) {
  ref.read(waveProvider.notifier).stop();
  showToast(context, context.l.waveToastStopped);
}

/// Sets or clears a dislike. A disliked playing track gets skipped by the wave
/// at once; see [WaveController.toggleDislike].
void toggleWaveDislike(BuildContext context, WidgetRef ref, Track track) {
  final l10n = context.l;
  final messenger = ScaffoldMessenger.of(context);
  final on = ref.read(waveProvider.notifier).toggleDislike(track);
  messenger.toast(on ? l10n.waveToastDisliked : l10n.waveToastUndisliked);
}

bool isWaveDisliked(WidgetRef ref, String trackId) =>
    ref.watch(waveStoreProvider).isDisliked(trackId);

/// Shared path: picks hit the network, so messenger and translations come
/// BEFORE waiting: the screen that started the wave has closed by then.
Future<void> _run(
  BuildContext context,
  WidgetRef ref,
  Future<WaveStartResult> Function(WaveController) start,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l;
  final result = await start(ref.read(waveProvider.notifier));
  if (result == WaveStartResult.ok || result == WaveStartResult.busy) return;
  messenger.toast(waveResultMessage(l10n, result), kind: ToastKind.warn);
}

/// Text of a failed start.
String waveResultMessage(AppLocalizations l10n, WaveStartResult result) =>
    switch (result) {
      WaveStartResult.ok || WaveStartResult.busy => '',
      WaveStartResult.notEnoughData => l10n.waveToastNotEnough,
      WaveStartResult.noSeed => l10n.waveToastNoSeed,
      WaveStartResult.queueEmpty => l10n.waveToastQueueEmpty,
      WaveStartResult.noSeedsInQueue => l10n.waveToastNoSeedsInQueue,
      WaveStartResult.artistNoSeeds => l10n.waveToastArtistNoSeeds,
      WaveStartResult.noSimilar => l10n.waveToastNoSimilar,
      WaveStartResult.ymNoAuth => l10n.waveToastYmNoAuth,
    };
