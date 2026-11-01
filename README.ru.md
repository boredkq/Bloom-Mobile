<div align="center">

<img src="assets/brand/bloom_mark.png" width="96" height="96" alt="Bloom" />

# Bloom Mobile

**Музыка из всех источников в одном плеере.**

Мобильный плеер: локальная медиатека, Yandex Music, SoundCloud и YouTube Music в одном приложении

[**📦 Релизы**](https://github.com/use-bloom/mobile/releases) · [**🖥 Десктоп**](https://github.com/use-bloom/desktop)

[English](README.md) · **Русский**

</div>

## 💿 Площадки

| Площадка | Примечания |
| --- | --- |
| 🟠 **SoundCloud** | Нативное воспроизведение |
| 🔴 **YouTube Music** | Нативное воспроизведение |
| 🟡 **Yandex Music** | Нативное воспроизведение |

## 🚀 Разработка

```bash
flutter pub get

flutter run -d <device>
flutter test                  # маппинг без сети
dart run tool/sc_smoke.dart   # живой smoke против api-v2 SoundCloud

flutter build apk --release   # android
flutter build ios --release   # ios, нужен macOS
```

Требуется [Flutter](https://docs.flutter.dev/get-started/install) 3.41+.
