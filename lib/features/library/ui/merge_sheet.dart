/// Шторка «Объединить с…»: выбрать плейлисты, из которых собрать новый.
///
/// Порт десктопной `MergeModal` — тот же состав: имя (подставляется само, пока
/// его не тронули), мультивыбор остальных плейлистов, «Убрать дубликаты» (по
/// умолчанию включено) и «Удалить исходные» (по умолчанию нет), плюс строка со
/// счётом того, что получится.
///
/// Сама шторка ничего не создаёт: она возвращает решение, а плейлист собирает
/// вызывающий — как и «+» библиотеки (`showCreatePlaylistSheet`). Иначе после
/// создания было бы некуда уйти: навигация живёт снаружи шторки.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/library_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../merge.dart';

/// Что человек выбрал в шторке.
class _MergePlan {
  const _MergePlan({
    required this.name,
    required this.ids,
    required this.dedup,
    required this.deleteSources,
  });

  final String name;

  /// Плейлисты, которые подмешиваем к исходному, в порядке выбора.
  final List<String> ids;

  final bool dedup;
  final bool deleteSources;
}

/// Открыть шторку и собрать плейлист по её итогу.
Future<void> showMergeSheet(
  BuildContext context,
  WidgetRef ref,
  UserPlaylist source,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l;
  // Объединять не с чем — говорим об этом сразу, а не пустой шторкой.
  final others = _mergeable(ref.read(libraryProvider), source);
  if (others.isEmpty) {
    messenger.toast(l10n.mgNothingToMerge, kind: ToastKind.info);
    return;
  }

  final plan = await showBloomSheetChild<_MergePlan>(
    context: context,
    header: SheetHero(
      cover: source.cover,
      title: source.name,
      subtitle: l10n.mgTitle,
    ),
    child: _MergeBody(source: source),
  );
  if (plan == null) return;

  final lib = ref.read(libraryProvider);
  final library = ref.read(libraryProvider.notifier);
  final picked = [
    for (final id in plan.ids)
      ...lib.playlists.where((p) => p.id == id).map(lib.tracksOf),
  ];
  final tracks = mergeTracks([
    lib.tracksOf(source),
    ...picked,
  ], dedup: plan.dedup);

  final created = library.createPlaylist(plan.name, tracks: tracks);
  if (plan.deleteSources) {
    library.deletePlaylist(source.id);
    for (final id in plan.ids) {
      library.deletePlaylist(id);
    }
  }
  if (context.mounted) context.go('/library/list/${created.id}');
  messenger.toast(
    l10n.mgMerged(created.name, l10n.tracksCount(tracks.length)),
    kind: ToastKind.success,
  );
}

/// С чем вообще можно объединять: все плейлисты, кроме самого исходного.
/// Импортированные альбомы не исключаем — в отличие от «добавить трек», здесь
/// альбом не правится, а читается.
List<UserPlaylist> _mergeable(LibraryState lib, UserPlaylist source) => [
  for (final pl in lib.playlists)
    if (pl.id != source.id) pl,
];

class _MergeBody extends ConsumerStatefulWidget {
  const _MergeBody({required this.source});

  final UserPlaylist source;

  @override
  ConsumerState<_MergeBody> createState() => _MergeBodyState();
}

class _MergeBodyState extends ConsumerState<_MergeBody> {
  late final TextEditingController _name = TextEditingController(
    // Имя по умолчанию — как на ПК: «Вечер +». Пока его не тронули, оно
    // остаётся подсказкой, а не выбором человека.
    text: '${widget.source.name} +',
  );

  /// Выбранные плейлисты в порядке нажатия: он же и порядок склейки.
  final List<String> _picked = [];

  bool _dedup = true;
  bool _deleteSources = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    // Молча ничего не делать нельзя: галочка нажата, значит человек ждёт
    // результата — говорим, чего для него не хватает.
    if (_picked.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).toast(context.l.mgPickHint, kind: ToastKind.warn);
      return;
    }
    if (name.isEmpty) return;
    Navigator.of(context).pop(
      _MergePlan(
        name: name,
        ids: [..._picked],
        dedup: _dedup,
        deleteSources: _deleteSources,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final lib = ref.watch(libraryProvider);
    final others = _mergeable(lib, widget.source);
    final lists = [
      lib.tracksOf(widget.source),
      for (final id in _picked)
        ...lib.playlists.where((p) => p.id == id).map(lib.tracksOf),
    ];
    final total = mergeTracks(lists, dedup: _dedup).length;
    final dups = mergeDupCount(lists);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetField(
          controller: _name,
          hint: context.l.mgNameHint,
          onChanged: (_) => setState(() {}),
          onSubmit: _submit,
        ),
        // Счёт того, что получится, — сразу под именем: он меняется от каждой
        // отметки, и видеть его надо там же, где отмечаешь.
        SheetCaption(
          _picked.isEmpty
              ? context.l.mgPickHint
              : context.l.mgResult(context.l.tracksCount(total)),
          padding: const EdgeInsets.fromLTRB(kSheetEdge, 2, kSheetEdge, 8),
          trailing: _dedup && dups > 0
              ? Text(
                  context.l.mgDupsDropped(dups),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: t.accent),
                )
              : null,
        ),
        SheetPanel(
          children: [
            for (final other in others)
              _PlaylistRow(
                playlist: other,
                tracks: lib.tracksOf(other).length,
                covers: lib.tracksOf(other).map((track) => track.cover),
                // The number says in what order the tracks land in the new
                // playlist, which a tick wouldn't.
                order: _picked.indexOf(other.id),
                onTap: () => setState(() {
                  if (!_picked.remove(other.id)) _picked.add(other.id);
                }),
              ),
          ],
        ),
        SheetPanel(
          children: [
            SheetSwitchRow(
              icon: Bi.copy,
              label: context.l.mgDedup,
              value: _dedup,
              onChanged: (v) => setState(() => _dedup = v),
              padding: const EdgeInsets.all(16),
            ),
            SheetSwitchRow(
              icon: Bi.trashBinTrash,
              label: context.l.mgDeleteSources,
              value: _deleteSources,
              danger: true,
              onChanged: (v) => setState(() => _deleteSources = v),
              padding: const EdgeInsets.all(16),
            ),
          ],
        ),
      ],
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({
    required this.playlist,
    required this.tracks,
    required this.covers,
    required this.order,
    required this.onTap,
  });

  final UserPlaylist playlist;
  final int tracks;
  final Iterable<String?> covers;

  /// Номер в порядке склейки; `-1` — не выбран.
  final int order;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final picked = order >= 0;

    return SheetRow(
      leading: Cover(url: playlist.cover, size: 40, covers: covers),
      gap: 12,
      label: playlist.name,
      subtitle: context.l.tracksCount(tracks),
      color: picked ? t.accent : t.text,
      trailing: picked ? CountBadge(order + 2, height: 24, size: 12) : null,
      onTap: onTap,
    );
  }
}
