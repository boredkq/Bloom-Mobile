<div align="center">

<img src="assets/brand/bloom_mark.png" width="96" height="96" alt="Bloom" />

# Bloom Mobile

**Music from every source in one player.**

A mobile player: local library, Yandex Music, SoundCloud, and YouTube Music in a single app

[**📦 Releases**](https://github.com/use-bloom/mobile/releases) · [**🖥 Desktop**](https://github.com/use-bloom/desktop)

**English** · [Русский](README.ru.md)

</div>

## ✨ Key Features

- 🎛️ **Studio Audio Engine & DSP**:
  - **10-Band Equalizer**: 31 Hz to 16 kHz hardware-accelerated parametric bands.
  - **16 Calibrated Presets**: Flat, Bass Boost, Vocal, Rock, Pop, Electronic, Jazz, Acoustic, Classical, Night, Gym, Car, AirPods Pro, Sony WH-1000XM4/5, Sennheiser HD600, plus custom user presets.
  - **Bass Boost & Spatial Virtualizer**: Studio low-end enhancement and 3D soundstage widening.
  - **True-Peak Headroom Guard**: Dynamic input gain adjustment to prevent inter-sample clipping and DAC distortion.
  - **Equal-Power Crossfade**: Constant acoustic energy ($\cos^2 + \sin^2 \equiv 1$) transitions eliminating loudness dips.
  - **Smart Album Gapless**: Intelligent sequential album track detection for bit-perfect continuous playback.
  - **ReplayGain & Volume Normalization**: Consistent perceived loudness across diverse sources.

- 🎙️ **Acoustic Music Recognition**:
  - Instant ambient track identification via pure Dart Shazam fingerprint engine (Radix-2 FFT & spectral peak extraction).
  - Real-time native microphone audio capture (`bloom/recognition`).
  - Interactive radar pulse wave UI and recognition history.

- 🎤 **Karaoke & Rich Synchronized Lyrics**:
  - **Syllable-by-Syllable Tracking**: TTML word-level timing with GPU shader glow mask.
  - **Universal Mirror Pool**: Multi-tier mirror fallback (LyricsPlus pool, direct Yandex `/tracks/{id}/supplement`, Musixmatch, Spotify).
  - **Automatic Romanization**: Instant phonetic transcription for Korean (Hangul), Japanese (Kana to Romaji), and Cyrillic.
  - **Customizable Lyrics Preferences**: Real-time syllable toggle, romanization, font sizing (compact/normal/large), alignment, and offline caching.

- 🎨 **10 Player Deck Styles (ported from Levyra)**:
  - **Standard**: Classic clean album artwork presentation.
  - **Vinyl**: Realistic rotating vinyl disc with center label and realistic grooves.
  - **Flow**: Flowing soft-corner artwork with ambient gradient wash.
  - **Aura (Velvet)**: Multi-layer atmospheric reactive neon glow behind the cover.
  - **Sleeve**: Vinyl jacket card with 3D drop shadow and physical disc slit.
  - **Poster**: Full-bleed cinematic gallery print framing.
  - **Halo**: Floating artwork surrounded by an ethereal glowing halo ring.
  - **Pulse**: Concentric audio-reactive rhythm ripple waves.
  - **Folio**: Two-tone asymmetric editorial magazine layout.
  - **Expressive**: Bouncy Material 3 Expressive squircle geometry.

- 🌐 **Unified Streaming & Library**:
  - SoundCloud, YouTube Music, Yandex Music, and local device audio files.
  - Last.fm scrobbling and PC remote synchronization.

## 💿 Platforms

| Platform | Notes |
| --- | --- |
| 🟠 **SoundCloud** | Native streaming |
| 🔴 **YouTube Music** | Native streaming |
| 🟡 **Yandex Music** | Native streaming |

## 🚀 Development

```bash
flutter pub get

flutter run -d <device>
flutter test                  # unit tests, dsp math, recognition & lyrics
dart run tool/sc_smoke.dart   # live smoke against the SoundCloud api-v2

flutter build apk --release   # android
flutter build ios --release   # ios, needs macOS
```

Requires [Flutter](https://docs.flutter.dev/get-started/install) 3.41+.
