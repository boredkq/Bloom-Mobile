/// Шторка «+» библиотеки — порт десктопного меню `LibAddMenu`.
///
/// Два вида, как на ПК: главный (поле имени + строка «Импорт») и импорт (поле
/// ссылки, выбор цели, «Из файла», «Назад»). Галочка справа появляется только
/// когда в поле что-то есть — там это `plName.trim() && <button>`.
///
/// Чего с ПК нет: «Связать папку» — следить на телефоне не за чем, одиночные
/// файлы добавляются плюсом в шапке «Всех треков» (`local_tracks.dart`).
/// Обложки при создании нет и на ПК — её ставят уже в самом плейлисте.
///
/// «Из файла» цель НЕ учитывает, как и на ПК: файл переноса сам состоит из
/// плейлистов, вкладывать их в выбранный некуда.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/library_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/platform_logo.dart';
import '../../../shared/ui/pressable.dart';
import '../import_file.dart';
import '../import_url.dart';

/// Чем кончилась шторка.
sealed class _Outcome {
  const _Outcome();
}

/// Ввели имя — плейлист создаёт вызывающий, ему же потом в него уходить.
class _NameEntered extends _Outcome {
  const _NameEntered(this.name);
  final String name;
}

/// Импорт по ссылке уже случился внутри шторки: он асинхронный и со своим
/// спиннером.
class _Imported extends _Outcome {
  const _Imported(this.result);
  final ImportResult result;
}

/// Выбрали «Из файла». Сам импорт делает вызывающий: системный диалог на ПК
/// открывается уже ПОСЛЕ закрытия меню, и висящая над ним шторка выглядела бы
/// зависшей.
class _FileRequested extends _Outcome {
  const _FileRequested();
}

/// Площадка по виду ссылки — только для значка в поле (порт
/// `detectLinkProvider`, без сети).
MusicSource? detectLinkSource(String url) {
  final u = url.trim();
  if (u.isEmpty) return null;
  if (RegExp(r'soundcloud\.com|snd\.sc', caseSensitive: false).hasMatch(u)) {
    return MusicSource.soundcloud;
  }
  if (RegExp(r'music\.yandex\.[a-z]+', caseSensitive: false).hasMatch(u)) {
    return MusicSource.yandex;
  }
  if (RegExp(
    r'music\.youtube\.com|(?:^|\.)youtube\.com|youtu\.be',
    caseSensitive: false,
  ).hasMatch(u)) {
    return MusicSource.ytmusic;
  }
  return null;
}

/// Открыть шторку «+». Созданный плейлист сразу открывается — как на ПК, где
/// `createNamedPlaylist` выбирает его в библиотеке.
Future<void> showCreatePlaylistSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l;
  final outcome = await showBloomSheetChild<_Outcome>(
    context: context,
    child: const _AddBody(),
  );
  if (outcome == null) return;

  switch (outcome) {
    case _NameEntered(:final name):
      final playlist = ref.read(libraryProvider.notifier).createPlaylist(name);
      if (context.mounted) context.go('/library/list/${playlist.id}');
    case _Imported(:final result):
      messenger.toast(
        importResultText(l10n, result),
        kind: result.added == 0 ? ToastKind.info : ToastKind.success,
      );
      // В созданный плейлист уходим, как и при обычном создании; при импорте
      // «во все треки» / «в любимые» уходить некуда.
      if (result.createdId != null && context.mounted) {
        context.go('/library/list/${result.createdId}');
      }
    case _FileRequested():
      // Никуда не уходим: в файле плейлистов может быть сколько угодно, и
      // открывать наугад один из них незачем. Тост показывает сам поток.
      await importPlaylistFile(ref, messenger, l10n);
  }
}

class _AddBody extends ConsumerStatefulWidget {
  const _AddBody();

  @override
  ConsumerState<_AddBody> createState() => _AddBodyState();
}

class _AddBodyState extends ConsumerState<_AddBody> {
  final _name = TextEditingController();
  final _url = TextEditingController();

  bool _importView = false;
  bool _busy = false;
  bool _targetOpen = false;
  ImportTarget _target = const ImportTarget.create();

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  void _submitName() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(_NameEntered(name));
  }

  Future<void> _runImport() async {
    final url = _url.text.trim();
    if (_busy || url.isEmpty) return;
    setState(() => _busy = true);
    try {
      final result = await importFromUrl(ref, url, _target);
      if (!mounted) return;
      Navigator.of(context).pop(_Imported(result));
    } on ImportException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).toast(describeImportFailure(context.l, e.reason), kind: ToastKind.warn);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).toast(context.l.cpSourceNoAnswer, kind: ToastKind.error);
    }
  }

  String _targetLabel(List<UserPlaylist> playlists) => switch (_target.kind) {
    ImportTargetKind.create => context.l.commonCreatePlaylist,
    ImportTargetKind.library => context.l.commonAllTracks,
    ImportTargetKind.favorites => context.l.commonFavorites,
    ImportTargetKind.playlist =>
      playlists
              .where((p) => p.id == _target.playlistId)
              .map((p) => p.name)
              .firstOrNull ??
          context.l.commonCreatePlaylist,
  };

  @override
  Widget build(BuildContext context) {
    final playlists = ref.watch(libraryProvider).playlists;

    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: _importView ? _importBody(playlists) : _mainBody(),
    );
  }

  Widget _mainBody() => Column(
    key: const ValueKey('main'),
    mainAxisSize: MainAxisSize.min,
    children: [
      SheetField(
        controller: _name,
        hint: context.l.cpNameHint,
        autofocus: true,
        onChanged: (_) => setState(() {}),
        onSubmit: _submitName,
      ),
      SheetPanel(
        children: [
          _Row(
            icon: Bi.import,
            label: context.l.cpImport,
            chevron: true,
            onTap: () => setState(() => _importView = true),
          ),
        ],
      ),
    ],
  );

  Widget _importBody(List<UserPlaylist> playlists) => Column(
    key: const ValueKey('import'),
    mainAxisSize: MainAxisSize.min,
    children: [
      SheetField(
        controller: _url,
        hint: context.l.cpLinkHint,
        autofocus: true,
        busy: _busy,
        // Значок площадки внутри поля — как только ссылка узнана.
        trailing: switch (detectLinkSource(_url.text)) {
          final source? => PlatformLogo(source, size: 18),
          null => null,
        },
        onChanged: (_) => setState(() {}),
        onSubmit: _runImport,
      ),
      SheetPanel(
        children: [
          _Row(
            icon: Bi.folderPathConnect,
            label: context.l.cpDestination(_targetLabel(playlists)),
            chevron: true,
            onTap: () => setState(() => _targetOpen = !_targetOpen),
          ),
          if (_targetOpen) ...[
            sheetDivider(),
            for (final option in <(ImportTarget, String, BloomGlyph, String?)>[
              (
                const ImportTarget.create(),
                context.l.commonCreatePlaylist,
                Bi.addCircle,
                null,
              ),
              (
                const ImportTarget(ImportTargetKind.library),
                context.l.commonAllTracks,
                Bi.musicNote,
                null,
              ),
              (
                const ImportTarget(ImportTargetKind.favorites),
                context.l.commonFavorites,
                Bi.heartBold,
                null,
              ),
              // Плейлисты стоят с обложками — как в шторке «Добавить в
              // плейлист»: свой список узнаётся по картинке быстрее, чем по
              // названию, а одинаковый значок у всех не различает ничего.
              for (final p in playlists)
                (
                  ImportTarget(ImportTargetKind.playlist, playlistId: p.id),
                  p.name,
                  Bi.musicLibrary2,
                  p.cover ?? '',
                ),
            ])
              _Row(
                icon: option.$3,
                cover: option.$4,
                label: option.$2,
                selected:
                    option.$1.kind == _target.kind &&
                    option.$1.playlistId == _target.playlistId,
                onTap: () => setState(() {
                  _target = option.$1;
                  _targetOpen = false;
                }),
              ),
          ],
        ],
      ),
      SheetPanel(
        children: [
          _Row(
            icon: Bi.file,
            label: context.l.cpFromFile,
            onTap: () => Navigator.of(context).pop(const _FileRequested()),
          ),
          sheetDivider(),
          _Row(
            icon: Bi.arrowLeft,
            label: context.l.commonBack,
            onTap: () => setState(() {
              _importView = false;
              _targetOpen = false;
            }),
          ),
        ],
      ),
    ],
  );
}

/// Строка шторки. Своя, а не `SheetAction`: те закрывают шторку по нажатию, а
/// здесь пункты переключают вид внутри неё.
class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.onTap,
    this.cover,
    this.chevron = false,
    this.selected = false,
  });

  final BloomGlyph icon;
  final String label;
  final VoidCallback onTap;

  /// Обложка вместо значка — у строк плейлистов. Пустая строка значит «это
  /// плейлист, но своей обложки нет»: там встаёт та же заглушка, что и на
  /// плитке в библиотеке, а не общий значок списка.
  final String? cover;

  final bool chevron;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final art = cover;
    return Pressable(
      onTap: onTap,
      scale: 0.98,
      child: Padding(
        // Обложка выше значка — поля по вертикали ужимаются, чтобы строка с
        // ней не выбивалась из списка (та же мера в «Добавить в плейлист»).
        padding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: art == null ? 15 : 8,
        ),
        child: Row(
          children: [
            if (art == null)
              BloomIcon(icon, size: 22, color: selected ? t.accent : t.text)
            else
              Cover(url: art, size: 40),
            SizedBox(width: art == null ? 16 : 12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: selected ? t.accent : t.text,
                ),
              ),
            ),
            if (selected) BloomIcon(Bi.check, size: 18, color: t.accent),
            if (chevron) BloomIcon(Bi.altArrowRight, size: 20, color: t.muted),
          ],
        ),
      ),
    );
  }
}
