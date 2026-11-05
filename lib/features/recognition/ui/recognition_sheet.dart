import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme/bloom_theme.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/providers/registry.dart';
import '../../../features/player/play_source.dart';
import '../../../features/search/search_session.dart';
import '../../../features/search/ui/search_layer.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/pressable.dart';
import '../models.dart';
import '../recognition_controller.dart';
import '../recognition_history.dart';
import 'listening_pulse.dart';

/// Opens the recognition sheet.
Future<void> showRecognitionSheet(BuildContext context) {
  return showBloomSheetChild<void>(
    context: context,
    header: SheetTitle(context.l.recTitle),
    child: const RecognitionSheetContent(),
  );
}

class RecognitionSheetContent extends ConsumerStatefulWidget {
  const RecognitionSheetContent({super.key});

  @override
  ConsumerState<RecognitionSheetContent> createState() =>
      _RecognitionSheetContentState();
}

class _RecognitionSheetContentState
    extends ConsumerState<RecognitionSheetContent> {
  bool _searchingMatch = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(recognitionProvider.notifier).startListening();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final l = context.l;
    final state = ref.watch(recognitionProvider);
    final history = ref.watch(recognitionHistoryProvider);

    final isListening = state is RecognitionListening;
    final isIdentifying = state is RecognitionIdentifying;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          // Pulsing / Soundwave center button
          ListeningPulseWidget(
            isListening: isListening,
            isIdentifying: isIdentifying,
            onTap: () {
              if (isListening || isIdentifying) {
                ref.read(recognitionProvider.notifier).cancel();
              } else {
                ref.read(recognitionProvider.notifier).startListening();
              }
            },
          ),
          const SizedBox(height: 16),

          // Status & Messages
          if (isListening) ...[
            Text(
              l.recListening,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: t.fg,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l.recNoMatchDesc,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: t.muted),
            ),
          ] else if (isIdentifying) ...[
            Text(
              l.recIdentifying,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: t.fg,
              ),
            ),
          ] else if (state is RecognitionMatch) ...[
            _MatchCard(
              result: state.result,
              searchingMatch: _searchingMatch,
              onPlay: () => _playMatch(state.result),
              onSearch: () => _openInSearch(state.result),
              onCopy: () => _copyTrack(state.result),
              onListenAgain: () =>
                  ref.read(recognitionProvider.notifier).startListening(),
            ),
          ] else if (state is RecognitionNoMatch) ...[
            _NoMatchView(
              onRetry: () =>
                  ref.read(recognitionProvider.notifier).startListening(),
            ),
          ] else if (state is RecognitionError) ...[
            _ErrorView(
              error: state,
              onRetry: () =>
                  ref.read(recognitionProvider.notifier).startListening(),
            ),
          ] else ...[
            Text(
              l.recTapToListen,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: t.muted),
            ),
          ],

          const SizedBox(height: 24),

          // History list if available
          if (history.isNotEmpty && !isListening && !isIdentifying) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l.recHistory,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: t.muted,
                  ),
                ),
                Pressable(
                  onTap: () =>
                      ref.read(recognitionHistoryProvider.notifier).clear(),
                  child: Text(
                    l.recClearHistory,
                    style: TextStyle(fontSize: 12, color: t.subtle),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _HistorySection(
              history: history,
              onSelect: (entry) {
                _playMatch(entry.result);
              },
            ),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Future<void> _playMatch(RecognitionResult result) async {
    setState(() => _searchingMatch = true);
    try {
      final reg = ref.read(registryProvider);
      final activeId = ref.read(activeProviderIdProvider);
      final res = await reg.searchAll(
        result.searchPhrase,
        providerId: activeId,
      );

      if (res.tracks.isNotEmpty && mounted) {
        Navigator.of(context).pop();
        ref.read(playbackProvider.notifier).playQueue(
          res.tracks,
          0,
          source: PlainSource.search(result.searchPhrase, result.title),
        );
      } else if (mounted) {
        toaster.show(context.l.recNoMatch, kind: ToastKind.warn);
      }
    } catch (_) {
      if (mounted) {
        toaster.show(context.l.recNoMatch, kind: ToastKind.warn);
      }
    } finally {
      if (mounted) setState(() => _searchingMatch = false);
    }
  }

  void _openInSearch(RecognitionResult result) {
    Navigator.of(context).pop();
    final navigator = currentBranchNavigator();
    if (navigator != null) {
      if (!searchOpen.value) {
        openSearchIn(navigator);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final session = ref.read(searchSessionProvider);
        session.controller.text = result.searchPhrase;
        session.run();
      });
    }
  }

  void _copyTrack(RecognitionResult result) {
    Clipboard.setData(
      ClipboardData(text: '${result.artist} - ${result.title}'),
    );
    toaster.show(context.l.playerCopied, kind: ToastKind.success);
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({
    required this.result,
    required this.searchingMatch,
    required this.onPlay,
    required this.onSearch,
    required this.onCopy,
    required this.onListenAgain,
  });

  final RecognitionResult result;
  final bool searchingMatch;
  final VoidCallback onPlay;
  final VoidCallback onSearch;
  final VoidCallback onCopy;
  final VoidCallback onListenAgain;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final l = context.l;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.ovlLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Cover(url: result.coverUrl, size: 68, radius: 12),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: t.fg,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      result.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: t.accent,
                      ),
                    ),
                    if (result.album != null || result.year != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (result.album != null) result.album,
                          if (result.year != null) result.year,
                        ].join(' • '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: t.muted),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SheetButton(
            label: l.recPlayInBloom,
            icon: Bi.musicNoteBold,
            tone: ButtonTone.accent,
            onTap: searchingMatch ? null : onPlay,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SheetButton(
                  label: l.recOpenSearch,
                  icon: Bi.search,
                  tone: ButtonTone.plate,
                  onTap: onSearch,
                ),
              ),
              const SizedBox(width: 8),
              Pressable(
                onTap: onCopy,
                child: Container(
                  height: 48,
                  width: 48,
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: t.ovlLine),
                  ),
                  child: Center(
                    child: BloomIcon(Bi.copy, size: 20, color: t.fg),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: Pressable(
              onTap: onListenAgain,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  l.recTryAgain,
                  style: TextStyle(
                    fontSize: 13,
                    color: t.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoMatchView extends StatelessWidget {
  const _NoMatchView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final l = context.l;

    return Column(
      children: [
        BloomIcon(Bi.dangerCircle, size: 36, color: t.muted),
        const SizedBox(height: 10),
        Text(
          l.recNoMatch,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: t.fg,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l.recNoMatchDesc,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: t.muted),
        ),
        const SizedBox(height: 14),
        SheetButton(
          label: l.recTryAgain,
          icon: Bi.soundwave,
          tone: ButtonTone.plate,
          onTap: onRetry,
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final RecognitionError error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final l = context.l;

    final msg = switch (error.kind) {
      RecognitionErrorKind.permissionDenied => l.recPermDenied,
      _ => error.message ?? l.recNoMatch,
    };

    return Column(
      children: [
        BloomIcon(Bi.dangerCircle, size: 36, color: t.muted),
        const SizedBox(height: 10),
        Text(
          msg,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: t.fg,
          ),
        ),
        const SizedBox(height: 14),
        SheetButton(
          label: l.recTryAgain,
          icon: Bi.soundwave,
          tone: ButtonTone.plate,
          onTap: onRetry,
        ),
      ],
    );
  }
}

class _HistorySection extends StatelessWidget {
  const _HistorySection({required this.history, required this.onSelect});

  final List<RecognitionHistoryEntry> history;
  final ValueChanged<RecognitionHistoryEntry> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 220),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: history.length > 8 ? 8 : history.length,
        separatorBuilder: (_, _) => const SizedBox(height: 6),
        itemBuilder: (context, index) {
          final item = history[index];
          return Pressable(
            onTap: () => onSelect(item),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: t.surface.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: t.ovlLine.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  Cover(url: item.result.coverUrl, size: 40, radius: 8),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.result.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: t.fg,
                          ),
                        ),
                        Text(
                          item.result.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: t.muted),
                        ),
                      ],
                    ),
                  ),
                  BloomIcon(Bi.play, size: 16, color: t.accent),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
