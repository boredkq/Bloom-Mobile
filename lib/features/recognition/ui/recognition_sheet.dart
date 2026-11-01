/// Music recognition modal sheet (Shazam style).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../features/player/player_controller.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/pressable.dart';
import '../recognition_models.dart';
import '../recognition_service.dart';

Future<void> showRecognitionSheet(BuildContext context, WidgetRef ref) async {
  await showBloomSheetChild<void>(
    context: context,
    child: const _RecognitionContent(),
  );
}

class _RecognitionContent extends ConsumerStatefulWidget {
  const _RecognitionContent();

  @override
  ConsumerState<_RecognitionContent> createState() =>
      _RecognitionContentState();
}

class _RecognitionContentState extends ConsumerState<_RecognitionContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  final RecognitionService _service = RecognitionService();
  RecognitionStatus _status = RecognitionStatus.listening;
  RecognitionResult? _result;

  @override
  void initState() {
    super.initState();
    _startRecognition();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _startRecognition() async {
    setState(() {
      _status = RecognitionStatus.listening;
      _result = null;
    });

    // Simulate listening sample window (4 seconds)
    await Future<void>.delayed(const Duration(milliseconds: 3800));
    if (!mounted) return;

    setState(() => _status = RecognitionStatus.identifying);

    // Call recognition service
    final outcome = await _service.identify();
    if (!mounted) return;

    setState(() {
      if (outcome != null) {
        _status = RecognitionStatus.found;
        _result = outcome;
      } else {
        _status = RecognitionStatus.notFound;
      }
    });
  }

  Future<void> _playFoundTrack(RecognitionResult res) async {
    Navigator.of(context).maybePop();
    showToast(context, 'Ищем трек: ${res.title}...');

    try {
      final searchResults = await ref
          .read(registryProvider)
          .searchAll(res.searchPhrase);
      if (searchResults.tracks.isNotEmpty && mounted) {
        final track = searchResults.tracks.first;
        await ref.read(playbackProvider.notifier).play(track);
      } else if (mounted) {
        showToast(context, 'Трек не найден на подключенных площадках');
      }
    } catch (e) {
      if (mounted) showToast(context, 'Ошибка воспроизведения: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final l = context.l;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l.recognitionTitle,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: t.text,
            ),
          ),
          const SizedBox(height: 24),
          if (_status.isInProgress) ...[
            _PulseWaves(animation: _pulse, status: _status),
            const SizedBox(height: 24),
            Text(
              _status == RecognitionStatus.listening
                  ? l.recognitionListening
                  : l.recognitionIdentifying,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: t.text2),
            ),
          ] else if (_status == RecognitionStatus.found && _result != null) ...[
            _FoundTrackCard(
              result: _result!,
              onPlay: () => _playFoundTrack(_result!),
            ),
          ] else ...[
            Icon(Icons.music_off_rounded, size: 48, color: t.muted),
            const SizedBox(height: 12),
            Text(
              l.recognitionNotFound,
              style: TextStyle(fontSize: 15, color: t.text2),
            ),
            const SizedBox(height: 20),
            Pressable(
              onTap: _startRecognition,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: t.accent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  l.recognitionRetry,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: t.accentText,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _PulseWaves extends StatelessWidget {
  const _PulseWaves({required this.animation, required this.status});

  final Animation<double> animation;
  final RecognitionStatus status;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return SizedBox(
      width: 140,
      height: 140,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          final val = animation.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 90 + val * 45,
                height: 90 + val * 45,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: t.accent.withValues(alpha: 0.12 * (1.0 - val * 0.5)),
                ),
              ),
              Container(
                width: 80 + val * 24,
                height: 80 + val * 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: t.accent.withValues(alpha: 0.22),
                ),
              ),
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: t.accent,
                  boxShadow: [
                    BoxShadow(color: t.glow, blurRadius: 18, spreadRadius: 2),
                  ],
                ),
                child: Center(
                  child: BloomIcon(Bi.soundwave, color: t.accentText, size: 34),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FoundTrackCard extends StatelessWidget {
  const _FoundTrackCard({required this.result, required this.onPlay});

  final RecognitionResult result;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final l = context.l;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: t.ovlBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: t.ovlLine),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 58,
                  height: 58,
                  child: result.coverUrl != null
                      ? Image.network(
                          result.coverUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => ColoredBox(
                            color: t.coverEmpty,
                            child: Icon(Icons.music_note, color: t.iconFg),
                          ),
                        )
                      : ColoredBox(
                          color: t.coverEmpty,
                          child: Icon(Icons.music_note, color: t.iconFg),
                        ),
                ),
              ),
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
                        fontWeight: FontWeight.w600,
                        color: t.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      result.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: t.text2),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Pressable(
          onTap: onPlay,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              color: t.accent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.play_arrow_rounded, color: t.accentText, size: 22),
                const SizedBox(width: 6),
                Text(
                  l.recognitionPlay,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: t.accentText,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
