/// Сколько места занимают кеши приложения — данные для раздела «Хранилище».
///
/// Порт `TelemetrySection.tsx`: кольцо «Занято» там считает СУММУ перечисленных
/// в разделе кешей, а не весь каталог приложения, — иначе очистка строки не
/// уменьшала бы круг. Знаменатель кольца на ПК даёт `navigator.storage.estimate`,
/// здесь — память телефона (нативный `diskSpace`).
///
/// Категории те же, что на десктопе: офлайн-копии, тексты и картинки
/// кастомизации. Библиотеки и своих обложек тут нет намеренно — это не кеш, а
/// то, что человек собрал руками, и стирать его пунктом «Очистить всё» нельзя.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/cover_store.dart';
import '../customization/custom_store.dart';
import '../customization/media_store.dart';
import '../lyrics/lyrics_store.dart';
import '../offline/offline_store.dart';

/// Тот же канал, что у системных диалогов файлов: обе стороны — про файловую
/// систему телефона, второй канал ради одного метода заводить незачем.
const MethodChannel _channel = MethodChannel('bloom/files');

/// Что за кеш — по нему же берутся иконка, название и текст очистки на экране.
enum CacheKind { offline, lyrics, custom }

class CacheStat {
  const CacheStat({
    required this.kind,
    required this.count,
    required this.bytes,
  });

  final CacheKind kind;
  final int count;
  final int bytes;

  bool get isEmpty => count == 0;
}

class StorageStats {
  const StorageStats({required this.caches, this.deviceTotal});

  final List<CacheStat> caches;

  /// Вся память телефона; `null` — платформа не ответила (нет нативной
  /// стороны, тесты). Тогда доли занятого не показываем.
  final int? deviceTotal;

  CacheStat of(CacheKind kind) =>
      caches.firstWhere((c) => c.kind == kind, orElse: () => _empty(kind));

  int get bytes => caches.fold(0, (sum, c) => sum + c.bytes);
  int get count => caches.fold(0, (sum, c) => sum + c.count);

  /// Доля занятого от памяти телефона, 0..1; `null` — знаменатель неизвестен.
  double? get fraction {
    final total = deviceTotal;
    if (total == null || total <= 0) return null;
    return (bytes / total).clamp(0.0, 1.0);
  }

  static CacheStat _empty(CacheKind kind) =>
      CacheStat(kind: kind, count: 0, bytes: 0);
}

/// Замеры для экрана «Хранилище».
///
/// `autoDispose`: цифры нужны, только пока экран открыт, а за его пределами
/// каждая проверка — это обход каталогов.
final storageStatsProvider = FutureProvider.autoDispose<StorageStats>((
  ref,
) async {
  // Downloads and pictures recount by themselves, their numbers live in
  // stores; the lyrics are recounted by the screen after a clear or a new
  // time limit.
  ref.watch(offlineProvider.select((s) => s.files.length));
  final media = ref.watch(mediaLibProvider);

  final offline = await ref.read(offlineProvider.notifier).stats();
  final lyrics = ref.read(lyricsCacheProvider).stats();
  final custom = await _mediaStats(media);

  return StorageStats(
    caches: [
      CacheStat(
        kind: CacheKind.offline,
        count: offline.count,
        bytes: offline.bytes,
      ),
      CacheStat(
        kind: CacheKind.lyrics,
        count: lyrics.count,
        bytes: lyrics.bytes,
      ),
      CacheStat(
        kind: CacheKind.custom,
        count: custom.count,
        bytes: custom.bytes,
      ),
    ],
    deviceTotal: await _deviceTotal(),
  );
});

/// Стереть кеш. Возвращает число удалённых записей — его показывает тост.
Future<int> clearCache(WidgetRef ref, CacheKind kind) async {
  final deleted = switch (kind) {
    CacheKind.offline => await ref.read(offlineProvider.notifier).clearAll(),
    CacheKind.lyrics => ref.read(lyricsCacheProvider).clear(),
    // Картинку убираем каскадом: она может стоять фоном или обложкой, и
    // ссылка на удалённый файл оставила бы пустой контекст (десктопный
    // `mediaLibStore.clearAll` делает ровно это).
    CacheKind.custom => _clearMedia(ref),
  };
  ref.invalidate(storageStatsProvider);
  return deleted;
}

int _clearMedia(WidgetRef ref) {
  final ids = [for (final item in ref.read(mediaLibProvider)) item.id];
  for (final id in ids) {
    removeMedia(ref.read, id);
  }
  return ids.length;
}

/// Картинки библиотеки кастомизации: считаем только свои файлы — картинка «по
/// ссылке» места на телефоне не занимает.
Future<({int count, int bytes})> _mediaStats(List<MediaItem> items) async {
  var count = 0;
  var bytes = 0;
  for (final item in items) {
    final path = localCoverPath(item.src);
    if (path == null) continue;
    final file = File(path);
    if (!file.existsSync()) continue;
    count++;
    try {
      bytes += await file.length();
    } catch (_) {
      // Файл исчез между проверкой и чтением — просто не считаем его.
    }
  }
  return (count: count, bytes: bytes);
}

/// Вся память телефона в байтах; `null` — платформа не ответила.
Future<int?> _deviceTotal() async {
  try {
    final space = await _channel.invokeMapMethod<String, Object?>('diskSpace');
    final total = space?['total'];
    return total is num && total > 0 ? total.toInt() : null;
  } on PlatformException {
    return null;
  } on MissingPluginException {
    // Платформа без нативной стороны (тесты, десктоп) — кольцо покажет только
    // объём, без доли.
    return null;
  }
}
