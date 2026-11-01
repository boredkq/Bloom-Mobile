/// Свои обложки плейлистов: выбор картинки из галереи и её хранение.
///
/// Файл галереи копируется в каталог приложения (`covers/`) — то, что вернул
/// image_picker, лежит в кеше и может пропасть в любой момент, а обложка нужна
/// столько же, сколько сам плейлист.
///
/// В плейлисте хранится НЕ абсолютный путь, а `local:<имя файла>`: контейнер
/// приложения на iOS переезжает между запусками, и записанный сегодня путь
/// завтра указывал бы в пустоту.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show Uint8List;

import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';

import 'app_dirs.dart';
import 'cover_cache.dart';

const String _prefix = 'local:';

Directory? _dir;

/// Готовит каталог обложек. Зовётся из `main()` до первого кадра — дальше путь
/// нужен синхронно, прямо в `build`.
Future<void> initCoverStore() async {
  final root = await appPrivateDir();
  final dir = Directory('${root.path}/covers');
  try {
    if (!dir.existsSync()) await dir.create(recursive: true);
    _dir = dir;
  } catch (_) {
    // Нет прав на запись — свои обложки просто не будут доступны.
  }
}

bool isLocalCover(String? cover) => cover != null && cover.startsWith(_prefix);

/// Значение поля `cover` для своей картинки с именем [name]. Нужно тем, кто
/// кладёт картинку в каталог мимо здешних функций: обложки своих треков
/// вынимает из тегов нативная сторона, и в Dart приходит уже готовое имя файла.
String localCoverRef(String name) => '$_prefix$name';

/// Каталог своих картинок; `null` — он не поднялся. Отдаётся наружу ровно для
/// того же: нативной стороне нужно, куда писать вынутую из тега обложку.
String? coversDirPath() => _dir?.path;

/// Абсолютный путь своей обложки; `null` — если это не своя обложка или
/// каталог не поднялся.
String? localCoverPath(String? cover) {
  final dir = _dir;
  if (dir == null || !isLocalCover(cover)) return null;
  return '${dir.path}/${cover!.substring(_prefix.length)}';
}

/// A cover's picture: one's own from the disk, or a platform's through the
/// cover cache. `null` — no cover.
ImageProvider? coverImage(String? cover) {
  if (cover == null || cover.isEmpty) return null;
  final path = localCoverPath(cover);
  if (path != null) return FileImage(File(path));
  if (isLocalCover(cover)) return null; // one's own, but no folder
  return coverCacheReady ? CachedCover(cover) : NetworkImage(cover);
}

/// Метаданные снимка (EXIF, дата, геометка) нам не нужны — берём только сам
/// файл. Флаг НЕ косметический: при `true` image_picker на iOS 13 идёт в
/// `PHPhotoLibrary requestAuthorization` («Full metadata are available only in
/// PHAsset, which requires gallery permission» — комментарий в самом плагине),
/// а это системный запрос доступа ко ВСЕЙ медиатеке и обязательный
/// `NSPhotoLibraryUsageDescription` в Info.plist. С `false` на iOS 13 открывается
/// просто выбор файла, а на iOS 14+ и так работает `PHPickerViewController`,
/// который разрешений не спрашивает вовсе.
///
/// Поставишь обратно `true` — вернуть и ключ в `ios/Runner/Info.plist`, иначе
/// iOS убьёт приложение в момент запроса.
const bool kPickMetadata = false;

/// Выбрать картинку из галереи и положить её к себе. Возвращает значение для
/// поля `cover` (`local:...`) или `null`, если выбор отменён.
///
/// Сторона ограничена 1024 px: обложке больше не нужно, а хранить полный
/// снимок с камеры в каталоге приложения — лишние мегабайты.
Future<String?> pickCover() async {
  final dir = _dir;
  if (dir == null) return null;
  final XFile? picked;
  try {
    picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 90,
      requestFullMetadata: kPickMetadata,
    );
  } catch (_) {
    return null; // отказ в доступе к галерее
  }
  if (picked == null) return null;
  try {
    final name = 'cover_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await picked.saveTo('${dir.path}/$name');
    return '$_prefix$name';
  } catch (_) {
    return null;
  }
}

/// Выбрать картинку из галереи БЕЗ сохранения — путь к тому, что вернул
/// image_picker. Нужна там, где картинку ещё будут резать (аватар и обложка
/// профиля): исходник берётся крупнее обложки, а в каталог приложения ляжет
/// уже обрезок.
Future<String?> pickImageFile({int maxSide = 2048}) async {
  try {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: maxSide.toDouble(),
      maxHeight: maxSide.toDouble(),
      requestFullMetadata: kPickMetadata,
    );
    return picked?.path;
  } catch (_) {
    return null; // отказ в доступе к галерее
  }
}

/// Разобрать `data:image/...;base64,...` в байты и расширение файла. `null` —
/// строка не data-url или не base64.
///
/// Своя картинка в файле переноса (пресеты, обложка плейлиста) едет именно
/// так: имя файла из `covers/` на чужом устройстве не значит ничего.
({Uint8List bytes, String ext})? decodeDataUrl(String value) {
  if (!value.startsWith('data:')) return null;
  final comma = value.indexOf(',');
  if (comma < 0) return null;
  final header = value.substring(5, comma);
  if (!header.contains('base64')) return null;
  try {
    return (
      bytes: base64Decode(value.substring(comma + 1)),
      ext: switch (header.split(';').first) {
        'image/png' => 'png',
        'image/gif' => 'gif',
        'image/webp' => 'webp',
        _ => 'jpg',
      },
    );
  } catch (_) {
    return null;
  }
}

/// Обратное [decodeDataUrl]: своя картинка → `data:`-строка. `null` — это не
/// своя картинка (ссылку возвращать не наша забота) или файла уже нет.
Future<String?> encodeLocalImage(String? cover) async {
  final path = localCoverPath(cover);
  if (path == null) return null;
  try {
    final bytes = await File(path).readAsBytes();
    return 'data:${_mimeOfPath(path)};base64,${base64Encode(bytes)}';
  } catch (_) {
    return null;
  }
}

String _mimeOfPath(String path) => switch (path.split('.').last.toLowerCase()) {
  'png' => 'image/png',
  'gif' => 'image/gif',
  'webp' => 'image/webp',
  _ => 'image/jpeg',
};

/// Разводит имена файлов, записанных в одну миллисекунду: выбор нескольких
/// картинок разом — обычное дело, и второй файл затёр бы первый.
int _copySeq = 0;

/// Положить готовые байты картинкой приложения. Возвращает значение поля
/// (`local:...`) или `null`, если записать не вышло.
///
/// Расширение — только ради честного имени: картинку с диска Flutter узнаёт по
/// самим байтам, а вот выгрузка пресета берёт по имени mime-тип.
Future<String?> saveLocalImage(
  Uint8List bytes, {
  String prefix = 'img',
  String ext = 'png',
}) async {
  final dir = _dir;
  if (dir == null) return null;
  try {
    final name =
        '${prefix}_${DateTime.now().millisecondsSinceEpoch}_${_copySeq++}.$ext';
    await File('${dir.path}/$name').writeAsBytes(bytes, flush: true);
    return '$_prefix$name';
  } catch (_) {
    return null;
  }
}

/// Скопировать готовый файл к себе КАК ЕСТЬ, сохранив расширение. Возвращает
/// значение поля (`local:...`) или `null`, если скопировать не вышло.
///
/// Отличие от [pickCover]: там картинка едет через `image_picker` с
/// `maxWidth`, то есть пережимается в JPEG. Для картинок кастомизации это
/// недопустимо — анимация гифки пережатия не переживает.
Future<String?> copyLocalFile(File source, {String prefix = 'img'}) async {
  final dir = _dir;
  if (dir == null) return null;
  try {
    final ext = source.path.split('.').last.toLowerCase();
    // Расширение берём только если оно похоже на расширение: у файла из
    // галереи его может не быть вовсе, и тогда в имя уехал бы весь путь.
    final suffix = ext.isNotEmpty && ext.length <= 5 && !ext.contains('/')
        ? '.$ext'
        : '.img';
    final name =
        '${prefix}_${DateTime.now().millisecondsSinceEpoch}_${_copySeq++}$suffix';
    await source.copy('${dir.path}/$name');
    return '$_prefix$name';
  } catch (_) {
    return null;
  }
}

/// Пользуется ли ещё чем-то в базе эта картинка. Ставит `main()`: картинка с
/// другого устройства лежит под именем-хешем, и одну и ту же могут взять два
/// плейлиста или плейлист и профиль.
bool Function(String cover)? coverInUse;

/// Убрать файл своей обложки — плейлист удалили или обложку сменили.
Future<void> deleteCover(String? cover) async {
  final path = localCoverPath(cover);
  if (path == null || (coverInUse?.call(cover!) ?? false)) return;
  try {
    final file = File(path);
    if (file.existsSync()) await file.delete();
  } catch (_) {
    // Не удалилась — не беда, это просто мусор в каталоге.
  }
}
