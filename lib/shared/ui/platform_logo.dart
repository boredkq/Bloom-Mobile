/// Логотипы площадок и бейджи источника — порт `entities/track/ui/SourceBadge`
/// с десктопа.
///
/// Логотип сам по себе рисуется В СВОИХ ФИРМЕННЫХ ЦВЕТАХ: бренды не
/// перекрашиваются под тему — то же правило, по которому их названия не
/// переводятся. В бейджах знак одноцветный: по умолчанию брендовый цвет
/// площадки, а по настройке «бейджи в цвете акцента» — акцент.
library;

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../app/theme/tokens.dart';
import '../../core/entities/entities.dart';
import '../../core/store/settings_store.dart';
import 'bloom_icon.dart';

const Map<MusicSource, String> _assets = {
  MusicSource.soundcloud: 'assets/platform/soundcloud.svg',
  MusicSource.ytmusic: 'assets/platform/YouTube.svg',
  MusicSource.yandex: 'assets/platform/yandex_music.svg',
};

/// Одноцветные версии — для перекраски в один цвет. Отдельный файл нужен только
/// YouTube: в цветном ассете треугольник нарисован белой заливкой поверх
/// прямоугольника, и при `srcIn` знак схлопнулся бы в сплошное пятно. У
/// SoundCloud и Яндекса силуэт и так одной заливкой.
const Map<MusicSource, String> _monoAssets = {
  MusicSource.ytmusic: 'assets/platform/youtube_mono.svg',
};

/// Фирменный цвет площадки — тот же, что в `BRAND` на десктопе.
const Map<MusicSource, Color> platformColor = {
  MusicSource.soundcloud: Color(0xFFFF5500),
  MusicSource.ytmusic: Color(0xFFFF0033),
  MusicSource.yandex: Color(0xFFFED42B),
};

/// Оптическая поправка размера: `size` — это сторона квадрата, в который знак
/// вписывается по `contain`, а не его воспринимаемая величина. Ассет YouTube —
/// широкий прямоугольник (viewBox 313×216) и почти сплошная заливка, поэтому по
/// ширине он занимает весь квадрат и рядом с редкими силуэтами SoundCloud и
/// Яндекса выглядит заметно крупнее при одном и том же `size`. Поджимаем его,
/// чтобы «вес» знаков совпадал — на десктопе этой поправки нет, там лого стоят
/// в менее плотных строках.
const Map<MusicSource, double> _opticalScale = {MusicSource.ytmusic: 0.82};

/// Логотип площадки. У локальных файлов логотипа нет — рисуем пустоту.
class PlatformLogo extends StatelessWidget {
  const PlatformLogo(this.source, {super.key, this.size = 16, this.color});

  final MusicSource source;

  /// Сторона квадрата, в который вписывается знак, ДО оптической поправки
  /// ([_opticalScale]).
  final double size;

  /// Перекрасить знак в один цвет (бейджи). `null` — фирменные цвета ассета.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (source == MusicSource.local) {
      return BloomIcon(
        Bi.folder,
        size: size,
        color: color ?? context.bloom.text,
      );
    }
    final mono = color != null;
    final asset = (mono ? _monoAssets[source] : null) ?? _assets[source];
    if (asset == null) return SizedBox(width: size, height: size);
    final box = size * (_opticalScale[source] ?? 1);
    return SvgPicture.asset(
      asset,
      width: box,
      height: box,
      fit: BoxFit.contain,
      colorFilter: mono ? ColorFilter.mode(color!, BlendMode.srcIn) : null,
    );
  }
}

/// Доля бейджа, которую занимает знак площадки (у каждого лого своя
/// «воздушность»). У SoundCloud и Яндекса — те же коэффициенты, что на десктопе.
/// У YouTube меньше десктопного 0.62: бейдж на телефоне мелкий, и сплошной
/// широкий прямоугольник в нём распирает плашку. Итоговая ширина знака ещё
/// умножается на [_opticalScale].
const Map<MusicSource, double> _logoScale = {
  MusicSource.soundcloud: 0.60,
  MusicSource.yandex: 0.58,
  MusicSource.ytmusic: 0.54,
};

/// Размер бейджа на обложке. Два на всё приложение, чтобы строки и карточки
/// разных экранов не разъезжались: [kRowBadge] в строке списка, [kCardBadge] на
/// крупной карточке ленты или сетки.
///
/// Карточный крупнее десктопного (26 на обложке 172): обложка на телефоне
/// вдвое мельче, и знак на ней должен читаться с той же дистанции.
const double kRowBadge = 18;
const double kCardBadge = 30;

/// Бейдж источника поверх обложки — круглая полупрозрачная «стеклянная» плашка
/// (затемнение + размытие фона), чтобы знак читался на любой картинке и не
/// перекрывал её. Ставится в угол обложки: `Positioned` снаружи, отступы 3 у
/// строк и 6 у крупных карточек — как `.cov-badge` на десктопе.
///
/// Цвет знака: фирменный цвет площадки, а при включённой настройке
/// [SettingsState.accentBadges] — акцент. У локальных треков площадки нет,
/// бейдж не рисуется вовсе.
class SourceBadge extends ConsumerWidget {
  const SourceBadge(this.source, {super.key, this.size = 16});

  final MusicSource source;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = platformColor[source];
    if (brand == null) return const SizedBox.shrink();

    final t = context.bloom;
    final accentBadges = ref.watch(
      settingsProvider.select((s) => s.accentBadges),
    );
    // Обводки нет — как на десктопе с 3.0. Десктопное расширение кружка на 2
    // сверх номинала не переносим: на телефоне бейдж так читается крупнее.

    return ClipOval(
      child: BackdropFilter(
        // CSS `blur(3px)` — это σ 1.5, а не 3.
        filter: ImageFilter.blur(sigmaX: 1.5, sigmaY: 1.5),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withValues(alpha: 0.38),
          ),
          child: PlatformLogo(
            source,
            size: size * (_logoScale[source] ?? 0.6),
            color: accentBadges ? t.accent : brand,
          ),
        ),
      ),
    );
  }
}

/// Сервис-интеграция (настройки: Last.fm, Discord).
enum Service { lastfm, discord }

const Map<Service, String> _serviceAssets = {
  Service.lastfm: 'assets/platform/last-fm.svg',
  Service.discord: 'assets/platform/Discord.svg',
};

/// Оба знака одноцветные, и в файлах залиты ЧЁРНЫМ — на тёмной теме их
/// просто не видно. Поэтому, в отличие от логотипов площадок, красим их сами:
/// в фирменный цвет сервиса, силуэт при этом не меняется.
const Map<Service, Color> serviceColor = {
  Service.lastfm: Color(0xFFD51007),
  Service.discord: Color(0xFF5865F2),
};

/// Знак интеграции — площадки ИЛИ сервиса, одним типом.
///
/// Нужен там, где вид не зависит от того, что именно за интеграцией стоит:
/// страницы настроек одинаковы у SoundCloud и у Last.fm, а [MusicSource] и
/// [Service] — разные перечисления и общего предка у них нет.
class BrandMark {
  const BrandMark.platform(MusicSource this.source) : service = null;
  const BrandMark.service(Service this.service) : source = null;

  final MusicSource? source;
  final Service? service;

  /// Фирменный цвет. У локальных файлов площадки нет — там `null`.
  Color? get color =>
      source != null ? platformColor[source] : serviceColor[service];

  Widget logo({double size = 16, Color? color}) => source != null
      ? PlatformLogo(source!, size: size, color: color)
      : ServiceLogo(service!, size: size, color: color);
}

class ServiceLogo extends StatelessWidget {
  const ServiceLogo(this.service, {super.key, this.size = 16, this.color});

  final Service service;
  final double size;

  /// Переопределить цвет (например приглушить у ещё не подключённого сервиса).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      _serviceAssets[service]!,
      width: size,
      height: size,
      fit: BoxFit.contain,
      colorFilter: ColorFilter.mode(
        color ?? serviceColor[service]!,
        BlendMode.srcIn,
      ),
    );
  }
}
