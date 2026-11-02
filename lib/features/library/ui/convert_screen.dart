/// Transfer to platform screen: searches a playlist's tracks on the picked
/// platform and builds a new playlist from what's found. The platform is picked
/// in the menu sheet and the scan starts at once: an extra pick-then-press step
/// adds only a press.
///
/// The source's cover isn't given to the copy: it's a file in the app's
/// directory, and with two playlists on one picture, deleting either would
/// leave the other with none.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/l10n/source_label.dart';
import '../../../core/providers/match.dart';
import '../../../core/store/library_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/platform_logo.dart';
import '../../../shared/ui/pressable.dart';
import '../../../shared/ui/subpage_header.dart';
import '../../../shared/ui/track_actions.dart';
import '../convert_playlist.dart';
import '../../../shared/ui/glass.dart';

/// Platform picker sheet, followed by the transfer itself.
Future<void> showConvertSheet(
  BuildContext context,
  WidgetRef ref,
  UserPlaylist playlist,
  List<Track> tracks,
) async {
  final targets = [
    for (final provider in ref.read(registryProvider).all)
      if (provider.source != MusicSource.local) provider.source,
  ];
  if (targets.isEmpty || tracks.isEmpty) return;

  await showBloomSheetChild<void>(
    context: context,
    header: SheetHero(
      cover: playlist.cover,
      title: context.l.cvTitle,
      subtitle: playlist.name,
    ),
    // The sheet closes through its own navigator (from outside `Navigator.of`
    // finds the tab's), and the transfer screen opens with the root one, to
    // cover the tab bar and mini player.
    child: Builder(
      builder: (sheetContext) => SheetPanel(
        children: [
          for (final target in targets)
            PlatformRow(
              source: target,
              onTap: () {
                final root = Navigator.of(sheetContext, rootNavigator: true);
                Navigator.of(sheetContext).pop();
                root.push<void>(
                  MaterialPageRoute(
                    builder: (_) => ConvertScreen(
                      playlist: playlist,
                      tracks: tracks,
                      target: target,
                    ),
                  ),
                );
              },
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
  late final TextEditingController _name;

  List<ConvertItem> _items = const [];
  Map<String, ConvertDecision> _decisions = const {};
  int _done = 0;
  bool _scanning = true;

  /// Once the screen closes the scan must stop: it hits the network track by
  /// track, and a hundred requests to nowhere aren't needed.
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _scan();
  }

  @override
  void dispose() {
    _closed = true;
    _name.dispose();
    super.dispose();
  }

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
      _decisions = defaultDecisions(items);
      _scanning = false;
    });
  }

  void _decide(String srcId, ConvertDecision decision) =>
      setState(() => _decisions = {..._decisions, srcId: decision});

  /// Takes the best candidate everywhere there is one, doubtful ones included.
  void _takeBest() => setState(() {
    _decisions = {
      for (final item in _items)
        item.src.id: item.cands.isNotEmpty && item.status != ConvertStatus.same
            ? TakeMatch(item.cands.first.track)
            : _decisions[item.src.id] ?? const KeepOriginal(),
    };
  });

  void _create() {
    final tracks = convertResult(_items, _decisions);
    if (tracks.isEmpty) return;
    final l10n = context.l;
    // I take the router BEFORE closing the screen: after `pop` this context has
    // left the tree and can't navigate to the new playlist.
    final router = GoRouter.of(context);
    final name = _name.text.trim().isEmpty ? _autoName : _name.text.trim();
    final created = ref
        .read(libraryProvider.notifier)
        .createPlaylist(name, tracks: tracks);

    Navigator.of(context).pop();
    router.go('/library/list/${created.id}');
    toaster.show(
      l10n.cvCreated(created.name, l10n.tracksCount(tracks.length)),
      kind: ToastKind.success,
    );
  }

  String get _autoName =>
      '${widget.playlist.name} (${widget.target.label10n(context.l)})';

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return BloomPage(
      body: SubPage(
        title: l.cvTitle,
        onBack: () => Navigator.of(context).pop(),
        child: _scanning
            ? _Scanning(
                source: widget.target,
                done: _done,
                total: widget.tracks.length,
              )
            : _review(),
      ),
    );
  }

  Widget _review() {
    final l = context.l;
    final stats = convertStats(_items, _decisions);
    final result = convertResult(_items, _decisions).length;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            children: [
              SheetField(
                controller: _name,
                hint: _autoName,
                onChanged: (_) => setState(() {}),
                onSubmit: _create,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 2, 8, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.cvSummary(stats.moved, stats.kept, stats.skipped),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    BloomButton(label: l.cvTakeBest, onTap: _takeBest),
                  ],
                ),
              ),
              for (final item in _items)
                _ItemRow(
                  item: item,
                  target: widget.target,
                  decision: _decisions[item.src.id] ?? const KeepOriginal(),
                  onDecide: (d) => _decide(item.src.id, d),
                ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            6,
            16,
            12 + bottomBarsInset(context),
          ),
          child: BloomButton(
            label: l.cvCreate(result),
            tone: ButtonTone.accent,
            height: 48,
            onTap: result == 0 ? null : _create,
          ),
        ),
      ],
    );
  }
}

class _Scanning extends StatelessWidget {
  const _Scanning({
    required this.source,
    required this.done,
    required this.total,
  });

  final MusicSource source;
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PlatformLogo(source, size: 40),
            const SizedBox(height: 16),
            Text(
              context.l.cvScanning(source.label10n(context.l)),
              textAlign: TextAlign.center,
              style: theme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text('$done / $total', style: theme.bodyMedium),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: total == 0
                  ? LinearProgressIndicator(
                      minHeight: 4,
                      backgroundColor: t.pill,
                      color: t.accent,
                    )
                  : BloomBar(
                      value: done / total,
                      color: t.accent,
                      track: t.pill,
                    ),
            ),
            const SizedBox(height: 14),
            Text(
              context.l.cvScanHint,
              textAlign: TextAlign.center,
              style: theme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Result row for one track: what was found and what happens to it.
class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.target,
    required this.decision,
    required this.onDecide,
  });

  final ConvertItem item;
  final MusicSource target;
  final ConvertDecision decision;
  final ValueChanged<ConvertDecision> onDecide;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final l = context.l;
    final theme = Theme.of(context).textTheme;
    final skipped = decision is SkipTrack;

    final (String tag, Color color) = switch (decision) {
      TakeMatch() => (l.cvTagMoved, t.accent),
      SkipTrack() => (l.cvTagSkipped, t.muted),
      KeepOriginal() => switch (item.status) {
        ConvertStatus.same => (l.cvTagOnTarget, t.text2),
        ConvertStatus.notfound => (
          item.failed ? l.cvSearchFailed : l.cvNotFound(target.label10n(l)),
          t.danger,
        ),
        _ => (l.cvTagOriginal, t.text2),
      },
    };

    // Nothing to pick from for those already on the platform or not found: the
    // row just tells what happens.
    final canChoose = item.cands.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Pressable(
        onTap: canChoose || item.status != ConvertStatus.same
            ? () => _choose(context)
            : null,
        scale: 0.98,
        child: GlassBox(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Opacity(
              opacity: skipped ? 0.5 : 1,
              child: Row(
                children: [
                  Cover(url: item.src.cover, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TwoLines(
                      item.src.name,
                      tag,
                      gap: 3,
                      titleStyle: theme.titleSmall,
                      subStyle: theme.bodySmall?.copyWith(color: color),
                    ),
                  ),
                  if (canChoose || item.status != ConvertStatus.same)
                    const SheetChevron(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Decision sheet for a track: candidates, keep original, skip.
  Future<void> _choose(BuildContext context) async {
    final l = context.l;
    await showBloomSheetChild<void>(
      context: context,
      header: SheetHero(
        cover: item.src.cover,
        title: item.src.name,
        subtitle: item.src.artist,
      ),
      // The sheet closes through its own navigator: from outside `Navigator.of`
      // would find the page's and close the transfer itself.
      child: Builder(
        builder: (sheetContext) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.cands.isNotEmpty)
              SheetPanel(
                children: [
                  for (final cand in item.cands)
                    _candidateRow(
                      context,
                      cand,
                      picked: switch (decision) {
                        TakeMatch(:final track) => track.id == cand.track.id,
                        _ => false,
                      },
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        onDecide(TakeMatch(cand.track));
                      },
                    ),
                ],
              ),
            SheetPanel(
              children: [
                SheetRow(
                  icon: Bi.undoLeftRound,
                  label: l.cvKeepOriginal,
                  trailing: decision is KeepOriginal ? const SheetTick() : null,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    onDecide(const KeepOriginal());
                  },
                ),
                SheetRow(
                  icon: Bi.close,
                  label: l.cvSkip,
                  trailing: decision is SkipTrack ? const SheetTick() : null,
                  danger: true,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    onDecide(const SkipTrack());
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A track the platform offered: the score is how sure the match is.
Widget _candidateRow(
  BuildContext context,
  ScoredMatch match, {
  required bool picked,
  required VoidCallback onTap,
}) {
  final t = context.bloom;
  return SheetRow(
    leading: Cover(url: match.track.cover, size: 40),
    gap: 12,
    label: match.track.name,
    subtitle: match.track.artist,
    color: picked ? t.accent : null,
    trailing: Text(
      '${(match.score * 100).round()}%',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: match.score >= kAutoMatchScore ? t.accent : t.text2,
      ),
    ),
    onTap: onTap,
  );
}
