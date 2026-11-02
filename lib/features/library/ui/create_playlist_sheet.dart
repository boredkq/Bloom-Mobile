/// The library's plus sheet. Two views: main (a name field and an Import row)
/// and import (a link field, a target choice, From file, Back). The tick on the
/// right shows only when the field has something.
///
/// No cover at creation: it's set in the playlist itself.
///
/// From file ignores the target: a transfer file is itself made of playlists,
/// with no way to nest them in the chosen one.
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
import '../import_file.dart';
import '../import_url.dart';

/// How the sheet ended.
sealed class _Outcome {
  const _Outcome();
}

/// A name was entered: the caller creates the playlist, and then goes to it.
class _NameEntered extends _Outcome {
  const _NameEntered(this.name);
  final String name;
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

  /// An import target. A playlist stands with its cover: among many it's found
  /// by the picture sooner than by the name.
  Widget _targetRow((ImportTarget, String, BloomGlyph, String?) option) {
    final (target, label, icon, cover) = option;
    final selected =
        target.kind == _target.kind && target.playlistId == _target.playlistId;
    return SheetRow(
      icon: icon,
      leading: cover == null ? null : Cover(url: cover, size: 40),
      gap: cover == null ? 22 : 12,
      label: label,
      color: selected ? context.bloom.accent : null,
      trailing: selected ? const SheetTick() : null,
      onTap: () => setState(() {
        _target = target;
        _targetOpen = false;
      }),
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
          SheetRow(
            icon: Bi.import,
            label: context.l.cpImport,
            trailing: const SheetChevron(),
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
        // Platform icon in the field, once the link is recognised.
        trailing: switch (detectLinkSource(_url.text)) {
          final source? => PlatformLogo(source, size: 18),
          null => null,
        },
        onChanged: (_) => setState(() {}),
        onSubmit: _runImport,
      ),
      SheetPanel(
        children: [
          SheetRow(
            icon: Bi.folderPathConnect,
            label: context.l.cpDestination(_targetLabel(playlists)),
            trailing: const SheetChevron(),
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
              // Playlists show with covers: an own list is known by its picture
              // faster than by name, and one icon for all tells nothing apart.
              for (final p in playlists)
                (
                  ImportTarget(ImportTargetKind.playlist, playlistId: p.id),
                  p.name,
                  Bi.musicLibrary2,
                  p.cover ?? '',
                ),
            ])
              _targetRow(option),
          ],
        ],
      ),
      SheetPanel(
        children: [
          SheetRow(
            icon: Bi.file,
            label: context.l.cpFromFile,
            onTap: () => Navigator.of(context).pop(const _FileRequested()),
          ),
          sheetDivider(),
          SheetRow(
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
