/// Transfer to platform screen: the new playlist's name for a title, how the
/// look-up goes, then how it went. Sure matches are taken; the unclear and the
/// missing ones are listed (all of them a tab away), a row opens a sheet with its
/// candidates, best first, and Keep the original / Skip.
///
/// The platform is picked before this screen and the scan starts at once. The
/// result is a new playlist, the old one stays; the toast can undo it.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/bloom_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/l10n/source_label.dart';
import '../../../core/store/cover_store.dart';
import '../../../core/store/library_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/big_tabs.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/entity_tiles.dart';
import '../../../shared/ui/pressable.dart';
import '../../../shared/ui/subpage_header.dart';
import '../../../shared/ui/track_actions.dart';
import '../../../shared/util/format.dart';
import '../convert_playlist.dart';

/// The platforms a playlist can move to.
List<MusicSource> convertTargets(WidgetRef ref) => [
  for (final provider in ref.read(registryProvider).all)
    if (provider.source != MusicSource.local) provider.source,
];

/// Closes the sheet of [sheet] and starts the transfer. The sheet closes through
/// its own navigator (from outside `Navigator.of` finds the tab's), and the
/// transfer screen opens with the root one, to cover the tab bar and mini player.
void closeSheetAndConvert(
  BuildContext sheet, {
  required UserPlaylist playlist,
  required List<Track> tracks,
  required MusicSource target,
}) {
  final root = Navigator.of(sheet, rootNavigator: true);
  Navigator.of(sheet).pop();
  root.push<void>(
    MaterialPageRoute(
      builder: (_) =>
          ConvertScreen(playlist: playlist, tracks: tracks, target: target),
    ),
  );
}

/// Platform picker sheet, followed by the transfer itself.
Future<void> showConvertSheet(
  BuildContext context,
  WidgetRef ref,
  UserPlaylist playlist,
  List<Track> tracks,
) async {
  final targets = convertTargets(ref);
  if (targets.isEmpty || tracks.isEmpty) return;

  await showBloomSheetChild<void>(
    context: context,
    header: SheetHero(
      cover: playlist.cover,
      title: context.l.cvTitle,
      subtitle: playlist.name,
    ),
    child: Builder(
      builder: (sheetContext) => SheetPanel(
        children: [
          for (final target in targets)
            PlatformRow(
              source: target,
              onTap: () => closeSheetAndConvert(
                sheetContext,
                playlist: playlist,
                tracks: tracks,
                target: target,
              ),
            ),
        ],
      ),
    ),
  );
}

class ConvertScreen extends ConsumerStatefulWidget {
  const ConvertScreen({
    super.key,
    required this.playlist,
    required this.tracks,
    required this.target,
  });

  final UserPlaylist playlist;

  /// Source playlist's contents in its own order.
  final List<Track> tracks;

  final MusicSource target;

  @override
  ConsumerState<ConvertScreen> createState() => _ConvertScreenState();
}

class _ConvertScreenState extends ConsumerState<ConvertScreen> {
  final TextEditingController _name = TextEditingController();
  final FocusNode _nameFocus = FocusNode();

  List<ConvertItem> _items = const [];

  /// Only what the user decided; [convertDecision] knows the rest.
  Map<String, ConvertDecision> _chosen = const {};
  int _done = 0;
  bool _scanning = true;
  bool _showAll = false;
  bool _creating = false;

  /// Once the screen closes the scan must stop: it hits the network track by
  /// track, and a hundred requests to nowhere aren't needed.
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _nameFocus.addListener(_nameFocusChanged);
    _scan();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_name.text.isEmpty && !_nameFocus.hasFocus) _name.text = _autoName;
  }

  @override
  void dispose() {
    _closed = true;
    _nameFocus.dispose();
    _name.dispose();
    super.dispose();
  }

  /// Emptied and left: the made-up name comes back.
  void _nameFocusChanged() => setState(() {
    if (!_nameFocus.hasFocus && _name.text.trim().isEmpty) {
      _name.text = _autoName;
    }
  });

  void _editName() {
    _nameFocus.requestFocus();
    _name.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _name.text.length,
    );
  }

  String get _autoName =>
      '${widget.playlist.name} (${widget.target.label10n(context.l)})';

  Future<void> _scan() async {
    final provider = ref.read(registryProvider).byId(widget.target.id);
    if (provider == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final items = await scanPlaylistConversion(
      provider,
      widget.tracks,
      cancelled: () => _closed,
      onProgress: (done, _) {
        if (!_closed && mounted) setState(() => _done = done);
      },
    );
    if (_closed || !mounted) return;
    setState(() {
      _items = items;
      _scanning = false;
    });
  }

  void _decide(ConvertItem item, ConvertDecision decision) =>
      setState(() => _chosen = {..._chosen, item.src.id: decision});

  Future<void> _create() async {
    final tracks = convertResult(_items, _chosen);
    if (_creating || tracks.isEmpty) return;
    _creating = true;
    final l10n = context.l;
    // I take these BEFORE closing the screen: after `pop` this context has left
    // the tree and can't reach them.
    final router = GoRouter.of(context);
    final library = ref.read(libraryProvider.notifier);
    final name = _name.text.trim().isEmpty ? _autoName : _name.text.trim();

    final cover = await coverForCopy(widget.playlist.cover);
    if (!mounted) {
      unawaited(deleteCover(cover));
      return;
    }
    // Empty, not null: with no picture the copy is a collage, like the source.
    final created = library.createPlaylist(
      name,
      tracks: tracks,
      cover: cover ?? '',
    );
    final location = '/library/list/${created.id}';

    Navigator.of(context).pop();
    router.go(location);
    toaster.show(
      l10n.cvCreated(created.name, l10n.tracksCount(tracks.length)),
      action: ToastAction(
        fn: () {
          if (router.state.uri.path == location) router.go('/library');
          library.deletePlaylist(created.id);
          unawaited(deleteCover(created.cover));
        },
      ),
    );
  }

  String _status() {
    final l = context.l;
    if (_scanning) return l.cvScanning(_done, widget.tracks.length);
    final stats = convertStats(_items, _chosen);
    return [
      l.cvMoved(stats.moved, _items.length),
      if (stats.waiting > 0) l.cvWaiting(stats.waiting),
      if (stats.skipped > 0) l.cvSkipped(stats.skipped),
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final l = context.l;
    final theme = Theme.of(context).textTheme;
    final unclear = [
      for (final item in _items)
        if (item.unclear) item,
    ];
    final shown = _showAll ? _items : unclear;
    final canTakeBest = unclear.any(
      (item) =>
          item.cands.isNotEmpty && convertDecision(item, _chosen) is! TakeMatch,
    );
    final canCreate = !_scanning && convertResult(_items, _chosen).isNotEmpty;

    return BloomPage(
      body: SubPage(
        title: l.cvTitle,
        onBack: () => Navigator.of(context).pop(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _NameField(
                    controller: _name,
                    focusNode: _nameFocus,
                    onEdit: _editName,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _status(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodySmall?.copyWith(color: t.text2),
                  ),
                  if (_scanning) ...[
                    const SizedBox(height: 10),
                    BloomBar(
                      value: _done / widget.tracks.length,
                      color: t.accent,
                      track: t.pill,
                      animated: const Duration(milliseconds: 200),
                    ),
                  ],
                ],
              ),
            ),
            if (!_scanning) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: BigTabs<bool>(
                      size: 18,
                      current: _showAll,
                      onPick: (all) => setState(() => _showAll = all),
                      tabs: [
                        BigTab(false, l.cvUnclear, count: unclear.length),
                        BigTab(true, l.commonAllTracks, count: _items.length),
                      ],
                    ),
                  ),
                  if (canTakeBest)
                    BloomButton(
                      label: l.cvTakeBest,
                      height: 32,
                      onTap: () => setState(
                        () => _chosen = convertTakeBest(_items, _chosen),
                      ),
                    ),
                ],
              ),
            ],
            Expanded(
              child: _scanning || shown.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(32, 28, 32, 0),
                      child: SizedBox(
                        width: double.infinity,
                        child: Text(
                          _scanning ? l.cvScanHint : l.cvAllSure,
                          textAlign: TextAlign.center,
                          style: theme.bodyMedium?.copyWith(color: t.muted),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(top: 6, bottom: 6),
                      itemCount: shown.length,
                      itemBuilder: (context, i) {
                        final item = shown[i];
                        return _ItemRow(
                          key: ValueKey(item.src.id),
                          item: item,
                          decision: convertDecision(item, _chosen),
                          onTap: () => _choose(item),
                        );
                      },
                    ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                12 + bottomBarsInset(context),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: BloomButton(
                      label: l.commonCreatePlaylist,
                      tone: ButtonTone.accent,
                      height: 48,
                      onTap: canCreate ? _create : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: BloomButton(
                      label: l.commonClose,
                      tone: ButtonTone.plate,
                      height: 48,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A track's choice in a sheet: the candidates, or why there are none, and the
  /// two ways to do without them. The sheet closes through its own navigator:
  /// from outside `Navigator.of` would find the page's and close the transfer.
  Future<void> _choose(ConvertItem item) async {
    final l = context.l;
    final t = context.bloom;
    final target = widget.target.label10n(l);
    final decision = convertDecision(item, _chosen);
    await showBloomSheetChild<void>(
      context: context,
      header: SheetHero(
        cover: item.src.cover,
        title: item.src.name,
        subtitle: _artistLine(item.src),
      ),
      child: Builder(
        builder: (sheet) {
          void pick(ConvertDecision next) {
            Navigator.of(sheet).pop();
            _decide(item, next);
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (item.cands.isNotEmpty)
                SheetPanel(
                  children: [
                    for (final cand in item.cands)
                      SheetRow(
                        leading: Cover(url: cand.track.cover, size: 40),
                        gap: 12,
                        label: cand.track.name,
                        subtitle: _artistLine(cand.track),
                        trailing: BloomCheck(
                          on: switch (decision) {
                            TakeMatch(:final track) =>
                              track.id == cand.track.id,
                            _ => false,
                          },
                        ),
                        onTap: () => pick(TakeMatch(cand.track)),
                      ),
                  ],
                )
              else
                SheetCaption(
                  item.failed
                      ? l.cvSearchFailed
                      : item.status == ConvertStatus.same
                      ? l.cvAlreadyOn(target)
                      : l.cvNotFound(target),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  kSheetEdge,
                  8,
                  kSheetEdge,
                  8,
                ),
                child: Row(
                  children: [
                    BloomTag(
                      text: l.cvKeepOriginal,
                      color: t.text,
                      active: decision is KeepOriginal,
                      size: 14,
                      vertical: 11,
                      onTap: () => pick(const KeepOriginal()),
                    ),
                    const SizedBox(width: 8),
                    BloomTag(
                      text: l.cvSkip,
                      color: t.text,
                      active: decision is SkipTrack,
                      size: 14,
                      vertical: 11,
                      onTap: () => pick(const SkipTrack()),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// "artist · time", the time only when it's known.
String _artistLine(Track track) => [
  if (track.artist.isNotEmpty) track.artist,
  if (track.duration > Duration.zero) mmss(track.duration),
].join(' · ');

/// The new playlist's name as a title; the pencil puts the cursor in it.
class _NameField extends StatelessWidget {
  const _NameField({
    required this.controller,
    required this.focusNode,
    required this.onEdit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Row(
      children: [
        Expanded(
          child: BloomField(
            controller: controller,
            focusNode: focusNode,
            hint: context.l.mgNameHint,
            style: Theme.of(context).textTheme.titleLarge,
            padding: EdgeInsets.zero,
            maxLength: 120,
            action: TextInputAction.done,
            onSubmitted: (_) => focusNode.unfocus(),
          ),
        ),
        const SizedBox(width: 12),
        Pressable(
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: BloomIcon(
              Bi.pen,
              size: 20,
              color: focusNode.hasFocus ? t.text : t.muted,
            ),
          ),
        ),
      ],
    );
  }
}

/// A source track: its cover, name and "artist · time", what it goes in as.
class _ItemRow extends StatelessWidget {
  const _ItemRow({
    super.key,
    required this.item,
    required this.decision,
    required this.onTap,
  });

  final ConvertItem item;
  final ConvertDecision decision;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final l = context.l;
    final theme = Theme.of(context).textTheme;
    final tag = switch (decision) {
      TakeMatch() => l.cvTagMoved,
      SkipTrack() => l.cvTagSkipped,
      KeepOriginal() => switch (item.status) {
        ConvertStatus.same => l.cvTagOnTarget,
        ConvertStatus.notfound => l.cvTagNotFound,
        _ => l.cvTagOriginal,
      },
    };

    return Pressable(
      onTap: onTap,
      scale: 0.98,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Cover(url: item.src.cover, size: kTrackRowCover),
            const SizedBox(width: 12),
            Expanded(
              child: TwoLines(
                item.src.name,
                _artistLine(item.src),
                gap: 3,
                titleStyle: theme.titleSmall,
                subStyle: theme.bodySmall,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              tag,
              style: bloomText(
                size: 12,
                weight: 700,
                color: decision is TakeMatch ? t.accent : t.muted,
              ),
            ),
            const SizedBox(width: 4),
            const SheetChevron(),
          ],
        ),
      ),
    );
  }
}
