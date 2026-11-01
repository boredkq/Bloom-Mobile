<div align="center">

<img src="assets/brand/bloom_mark.png" width="96" height="96" alt="Bloom" />

# Bloom Mobile

**Music from every source in one player.**

A mobile player: local library, Yandex Music, SoundCloud, and YouTube Music in a single app

[**📦 Releases**](https://github.com/use-bloom/mobile/releases) · [**🖥 Desktop**](https://github.com/use-bloom/desktop)

**English** · [Русский](README.ru.md)

</div>

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
flutter test                  # mapping, no network
dart run tool/sc_smoke.dart   # live smoke against the SoundCloud api-v2

flutter build apk --release   # android
flutter build ios --release   # ios, needs macOS
```

Requires [Flutter](https://docs.flutter.dev/get-started/install) 3.41+.
