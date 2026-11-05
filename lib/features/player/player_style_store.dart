/// Player style: standard, vinyl, and Levyra player deck styles.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/json_store.dart' show jsonStoreProvider;

enum PlayerStyle {
  /// A rounded square cover.
  standard,

  /// A round cover that spins while playing.
  vinyl,

  /// Apple Music player with ambient backdrop, SF typography, Apple transports.
  appleMusic,

  /// Spotify player with dark gradient, green accents, white circular play.
  spotify,

  /// YouTube Music player with pill tabs, thumbs up/down, and YTM transport.
  youtubeMusic,

  /// Fluid ambient surface with flowing light (Levyra Flow).
  flow,

  /// Glowing atmospheric velvet aura (Levyra Aura / Velvet).
  aura,

  /// Floating vinyl card sleeve with physical depth (Levyra Sleeve / Card).
  sleeve,

  /// Sharp cinematic gallery poster (Levyra Poster / Artwork).
  poster,

  /// Floating artwork surrounded by an ethereal glowing halo ring (Levyra Halo).
  halo,

  /// Audio-reactive rhythmic pulse ripples (Levyra Pulse).
  pulse,

  /// Asymmetric two-tone editorial magazine layout (Levyra Folio / Editorial).
  folio,

  /// Dynamic Material 3 Expressive pill squircle (Levyra Expressive).
  expressive;

  bool get isVinyl => this == PlayerStyle.vinyl;
  bool get isAppleMusic => this == PlayerStyle.appleMusic;
  bool get isSpotify => this == PlayerStyle.spotify;
  bool get isYouTubeMusic => this == PlayerStyle.youtubeMusic;
  bool get isFolio => this == PlayerStyle.folio;

  static PlayerStyle of(Object? name) {
    if (name is! String) return PlayerStyle.standard;
    for (final s in values) {
      if (s.name == name) return s;
    }
    // Backward compatibility with Levyra storage identifiers & aliases:
    switch (name.toLowerCase()) {
      case 'apple_music':
      case 'applemusic':
      case 'apple':
        return appleMusic;
      case 'spotify':
      case 'spotify_style':
        return spotify;
      case 'youtube_music':
      case 'ytm':
      case 'youtube':
      case 'youtubemusic':
        return youtubeMusic;
      case 'canvas_card':
      case 'card':
        return sleeve;
      case 'canvas_immersive':
      case 'immersive':
      case 'velvet':
        return aura;
      case 'editorial':
        return folio;
      case 'gallery':
      case 'artwork':
        return poster;
      default:
        return standard;
    }
  }
}

final playerStyleProvider =
    NotifierProvider<PlayerStyleController, PlayerStyle>(
      PlayerStyleController.new,
    );

class PlayerStyleController extends Notifier<PlayerStyle> {
  @override
  PlayerStyle build() {
    final raw = ref.read(jsonStoreProvider).read('playerStyle');
    return PlayerStyle.of(raw);
  }

  void setStyle(PlayerStyle style) {
    if (style == state) return;
    state = style;
    ref.read(jsonStoreProvider).write('playerStyle', style.name);
  }
}
