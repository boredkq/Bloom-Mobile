/// The library's plus sheet: a name field and two rows that continue the sheet.
/// Import: a link field, where its tracks go, listed open, and From file. Convert:
/// a playlist and the platform to move it to, then the transfer screen. The tick
/// by a field shows only when the field has something.
///
/// No cover at creation: it's set in the playlist itself.
///
/// From file ignores the target: a transfer file is itself made of playlists,
/// with no way to nest them in the chosen one.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/l10n/source_label.dart';
import '../../../core/store/library_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/platform_logo.dart';
import '../../../shared/ui/pressable.dart';
import '../import_file.dart';
import '../import_url.dart';
import 'convert_screen.dart';
import 'list_hero.dart';

/// How the import page ended.
sealed class _Outcome {
  const _Outcome();
}

/// A link import already happened inside the sheet: it's asynchronous, with its
/// own spinner.
class _Imported extends _Outcome {
  const _Imported(this.result);
  final ImportResult result;
}

/// From file was picked. The caller does the import: the system dialog opens
/// after the menu closes, and a sheet hanging over it would look stuck.
class _FileRequested extends _Outcome {
  const _FileRequested();
}

/// Platform by a link's look, only for the icon in the field; no network.
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

/// Opens the plus sheet. A created playlist opens right away.
Future<void> showCreatePlaylistSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  final name = await showBloomSheetChild<String>(
    context: context,
    child: _NameBody(
      onImport: (sheet) =>
          openNextSheet(sheet, () => unawaited(_showImportPage(context, ref))),
      onConvert: (sheet) => openNextSheet(
        sheet,
        () => unawaited(
          showBloomModal<void>(
            context: context,
            builder: (_) => const _ConvertBody(),
          ),
        ),
      ),
    ),
  );
  if (name == null) return;
  final playlist = ref.read(libraryProvider.notifier).createPlaylist(name);
  if (context.mounted) context.go('/library/list/${playlist.id}');
}

Future<void> _showImportPage(BuildContext context, WidgetRef ref) async {
  final l10n = context.l;
  final outcome = await showBloomSheetChild<_Outcome>(
    context: context,
    scrolls: false,
    child: const _ImportBody(),
  );
  switch (outcome) {
    case null:
      return;
    case _Imported(:final result):
      toaster.show(
        importResultText(l10n, result),
        kind: result.added == 0 ? ToastKind.info : ToastKind.success,
      );
      // I go to the created playlist, as with ordinary creation; importing into
      // all tracks or favourites has nowhere to go.
      if (result.createdId != null && context.mounted) {
        context.go('/library/list/${result.createdId}');
      }
    case _FileRequested():
      // Going nowhere: a file may hold any number of playlists, and opening one
      // at random makes no sense. The flow shows the toast.
      await importPlaylistFile(ref, l10n);
  }
}

class _NameBody extends StatefulWidget {
  const _NameBody({required this.onImport, required this.onConvert});

  /// Both get the sheet's own context: they continue this sheet.
  final ValueChanged<BuildContext> onImport;
  final ValueChanged<BuildContext> onConvert;

  @override
  State<_NameBody> createState() => _NameBodyState();
}

class _NameBodyState extends State<_NameBody> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SheetField(
        controller: _name,
        hint: context.l.cpNameHint,
        autofocus: true,
        onChanged: (_) => setState(() {}),
        onSubmit: _submit,
      ),
      SheetPanel(
        children: [
          SheetRow(
            icon: Bi.export,
            label: context.l.cpImport,
            trailing: const SheetChevron(),
            onTap: () => widget.onImport(context),
          ),
          SheetRow(
            icon: Bi.shuffle,
            label: context.l.cpConvert,
            trailing: const SheetChevron(),
            onTap: () => widget.onConvert(context),
          ),
        ],
      ),
    ],
  );
}

class _ImportBody extends ConsumerStatefulWidget {
  const _ImportBody();

  @override
  ConsumerState<_ImportBody> createState() => _ImportBodyState();
}

class _ImportBodyState extends ConsumerState<_ImportBody> {
  final _url = TextEditingController();

  bool _busy = false;
  ImportTarget _target = const ImportTarget.create();

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
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
      toaster.show(
        describeImportFailure(context.l, e.reason),
        kind: ToastKind.warn,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      toaster.show(context.l.cpSourceNoAnswer, kind: ToastKind.error);
    }
  }

  bool _picked(ImportTarget target) =>
      target.kind == _target.kind && target.playlistId == _target.playlistId;

  /// One of the library's own lists.
  Widget _systemRow(
    ImportTarget target,
    String id,
    String label,
    double size,
  ) => _PickRow(
    art: OutlineArt(
      icon: systemListGlyph(id)!,
      iconSize: size,
      borderRadius: BorderRadius.circular(Cover.defaultRadius(context.bloom)),
    ),
    label: label,
    picked: _picked(target),
    onTap: () => setState(() => _target = target),
  );

  Widget _playlistRow(UserPlaylist playlist) {
    final target = ImportTarget(
      ImportTargetKind.playlist,
      playlistId: playlist.id,
    );
    return _PlaylistPick(
      playlist: playlist,
      picked: _picked(target),
      onTap: () => setState(() => _target = target),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playlists = ref.watch(libraryProvider).playlists;
    const create = ImportTarget.create();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetField(
          controller: _url,
          hint: context.l.cpLinkHint,
          autofocus: true,
          busy: _busy,
          // Platform icon in the field, once the link is recognised.
          trailing: switch (detectLinkSource(_url.text)) {
            final source? => PlatformLogo(source, size: 18),
            null => null,
          },
          onChanged: (_) => setState(() {}),
          onSubmit: _runImport,
        ),
        Flexible(
          child: _PickPanel(
            rows: [
              // An action, not a list: its plus stands bare.
              _PickRow(
                art: Center(
                  child: BloomIcon(Bi.add, size: 22, color: context.bloom.text),
                ),
                label: context.l.commonCreatePlaylist,
                picked: _picked(create),
                onTap: () => setState(() => _target = create),
              ),
              _systemRow(
                const ImportTarget(ImportTargetKind.library),
                'all',
                context.l.commonAllTracks,
                18,
              ),
              _systemRow(
                const ImportTarget(ImportTargetKind.favorites),
                'fav',
                context.l.commonFavorites,
                16,
              ),
              for (final playlist in playlists) _playlistRow(playlist),
            ],
          ),
        ),
        SheetPanel(
          children: [
            SheetRow(
              icon: Bi.fileText,
              label: context.l.cpFromFile,
              onTap: () => Navigator.of(context).pop(const _FileRequested()),
            ),
          ],
        ),
      ],
    );
  }
}

/// The convert page: a playlist, a platform, then the transfer screen. An empty
/// playlist can be picked, but has nothing to move.
class _ConvertBody extends ConsumerStatefulWidget {
  const _ConvertBody();

  @override
  ConsumerState<_ConvertBody> createState() => _ConvertBodyState();
}

class _ConvertBodyState extends ConsumerState<_ConvertBody> {
  String? _playlistId;
  MusicSource? _target;

  @override
  Widget build(BuildContext context) {
    final lib = ref.watch(libraryProvider);
    final playlists = lib.playlists;
    final playlist = playlists.where((p) => p.id == _playlistId).firstOrNull;
    final target = _target;
    final tracks = playlist == null ? const <Track>[] : lib.tracksOf(playlist);

    return SheetShell(
      scrolls: false,
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(kSheetEdge, 10, kSheetEdge, 0),
        child: SheetButton(
          label: context.l.cpConvertRun,
          tone: ButtonTone.accent,
          onTap: playlist == null || target == null || tracks.isEmpty
              ? null
              : () => closeSheetAndConvert(
                  context,
                  playlist: playlist,
                  tracks: tracks,
                  target: target,
                ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetCaption(context.l.cpConvertTitle),
          Flexible(
            child: playlists.isEmpty
                ? SheetPanel(
                    children: [
                      SizedBox(
                        height: 64,
                        child: Center(
                          child: Text(
                            context.l.cpNoPlaylists,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: context.bloom.muted),
                          ),
                        ),
                      ),
                    ],
                  )
                : _PickPanel(
                    rows: [
                      for (final p in playlists)
                        _PlaylistPick(
                          playlist: p,
                          picked: p.id == _playlistId,
                          onTap: () => setState(() => _playlistId = p.id),
                        ),
                    ],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final source in convertTargets(ref))
                  _PlatformPick(
                    source: source,
                    picked: source == _target,
                    onTap: () => setState(() => _target = source),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Rows to pick from on one plate. A long list scrolls inside it, so what stands
/// under it stays on screen.
class _PickPanel extends StatelessWidget {
  const _PickPanel({required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => SheetPanel(
    children: [
      Flexible(
        child: ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: rows.length,
          itemBuilder: (_, i) => rows[i],
          separatorBuilder: (_, _) => const SheetLine(),
        ),
      ),
    ],
  );
}

/// A row to pick: one box for every picture, so the names line up; the picked one
/// has a film and a tick.
class _PickRow extends StatelessWidget {
  const _PickRow({
    required this.art,
    required this.label,
    required this.picked,
    required this.onTap,
    this.subtitle,
    this.pinned = false,
  });

  final Widget art;
  final String label;
  final String? subtitle;
  final bool pinned;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      color: t.text.withValues(alpha: picked ? 0.09 : 0),
      child: SheetRow(
        leading: SizedBox.square(dimension: 40, child: art),
        gap: 12,
        label: label,
        labelMark: pinned ? BloomIcon(Bi.pin, size: 13, color: t.text2) : null,
        subtitle: subtitle,
        trailing: picked ? const SheetTick() : null,
        onTap: onTap,
      ),
    );
  }
}

/// A playlist as a row to pick: its cover or collage, how many tracks it has.
class _PlaylistPick extends ConsumerWidget {
  const _PlaylistPick({
    required this.playlist,
    required this.picked,
    required this.onTap,
  });

  final UserPlaylist playlist;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);
    final count = playlist.trackIds.length;
    return _PickRow(
      art: Cover(
        url: playlist.cover,
        size: 40,
        covers: lib.tracksOf(playlist).map((track) => track.cover),
      ),
      label: playlist.name,
      subtitle: count > 0
          ? context.l.tracksCount(count)
          : context.l.libNoTracks,
      pinned: playlist.pinned,
      picked: picked,
      onTap: onTap,
    );
  }
}

/// A platform's logo to pick: plain until picked, then in its colour on a film.
class _PlatformPick extends StatelessWidget {
  const _PlatformPick({
    required this.source,
    required this.picked,
    required this.onTap,
  });

  final MusicSource source;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Semantics(
      button: true,
      selected: picked,
      label: source.label10n(context.l),
      child: Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 52,
          height: 52,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: t.text.withValues(alpha: picked ? 0.1 : 0),
          ),
          alignment: Alignment.center,
          child: PlatformLogo(source, size: 24, color: picked ? null : t.muted),
        ),
      ),
    );
  }
}
