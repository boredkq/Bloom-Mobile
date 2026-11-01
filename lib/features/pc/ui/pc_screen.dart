/// «Настройки → Компьютер»: сопряжение с Bloom на ПК и синхронизация —
/// телефонная пара раздела «Интеграции → Телефон» ПК.
///
/// Каркас — [PlatformPage], как у площадок и Last.fm: значок посреди экрана,
/// статус под ним, действия внизу. Не сопряжён — под значком шаги, как
/// подключить; сопряжён — «Синхронизировать сейчас» и «Отключить».
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/sync/pc_client.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/danger_confirm.dart';
import '../../../shared/ui/glass.dart';
import '../../settings/ui/platform_page.dart';
import '../pc_store.dart';

class PcSettingsScreen extends ConsumerWidget {
  const PcSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final s = ref.watch(pcProvider);
    final pc = ref.read(pcProvider.notifier);
    final link = s.link;

    return PlatformPage(
      icon: Bi.monitor,
      onBack: () => context.go('/settings'),
      status: _status(context, s),
      statusColor: switch (s.status) {
        _ when link == null => null,
        PcStatus.ok || PcStatus.idle || PcStatus.syncing => kPlatformOk,
        PcStatus.repair || PcStatus.failed => context.bloom.danger,
        PcStatus.offline => null,
      },
      body: link == null ? const _HowTo() : null,
      actions: [
        if (link == null || s.status == PcStatus.repair) ...[
          PlatformAction(
            label: link == null ? l.pcScan : l.pcReconnect,
            onTap: () => context.go('/settings/pc/scan'),
          ),
          PlatformAction(
            label: l.pcEnterCode,
            onTap: () => _enterCode(context),
          ),
        ],
        if (link != null && s.status != PcStatus.repair)
          PlatformAction(
            label: l.pcSyncNow,
            busy: s.status == PcStatus.syncing,
            onTap: () async {
              await pc.sync(force: true);
              if (!context.mounted) return;
              final now = ref.read(pcProvider).status;
              if (now == PcStatus.ok) {
                showToast(context, l.pcSynced, kind: ToastKind.success);
              }
            },
          ),
        if (link != null)
          PlatformAction(
            label: l.pcUnpair,
            onTap: () async {
              final yes = await confirmDanger(
                context,
                icon: Bi.monitor,
                title: l.pcUnpairTitle,
                body: l.pcUnpairBody(link.name),
                button: l.pcUnpair,
              );
              if (!yes || !context.mounted) return;
              pc.unpair();
              showToast(context, l.pcUnpaired);
            },
          ),
      ],
    );
  }

  String _status(BuildContext context, PcState s) {
    final l = context.l;
    final link = s.link;
    if (link == null) return l.pcNotPaired;
    final head = l.pcPairedTo(link.name);
    final tail = switch (s.status) {
      PcStatus.syncing => l.pcSyncing,
      PcStatus.offline => l.pcOffline,
      PcStatus.repair => l.pcRepair,
      PcStatus.failed => l.pcFailed,
      _ when s.lastSync > 0 => l.pcSyncedAt(_when(context, s.lastSync)),
      _ => null,
    };
    return tail == null ? head : '$head\n$tail';
  }

  /// Сегодня — время, раньше — дата и время.
  static String _when(BuildContext context, int ms) {
    final at = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final locale = Localizations.localeOf(context).toLanguageTag();
    final today =
        at.year == now.year && at.month == now.month && at.day == now.day;
    return (today ? DateFormat.Hm(locale) : DateFormat.MMMd(locale).add_Hm())
        .format(at);
  }
}

/// Не сопряжён: как подключить — шаги прямо на странице.
class _HowTo extends StatelessWidget {
  const _HowTo();

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final steps = [l.pcStep1, l.pcStep2, l.pcStep3];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassBox(
          borderRadius: BorderRadius.circular(t.radius),
          child: Column(
            children: [
              for (final (i, step) in steps.indexed)
                GuideStep(index: i + 1, text: step),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
          child: Text(
            l.pcGuideNote,
            style: theme.bodySmall?.copyWith(color: t.text2, height: 1.6),
          ),
        ),
      ],
    );
  }
}

String pairMessage(AppLocalizations l, PairResult r, String name) =>
    switch (r) {
      PairResult.ok => l.pcPaired(name),
      PairResult.notBloom => l.pcErrNotBloom,
      PairResult.unreachable => l.pcErrUnreachable,
      PairResult.wrong => l.pcErrWrong,
      PairResult.closed => l.pcErrClosed,
      PairResult.tooMany => l.pcErrTooMany,
      PairResult.failed => l.pcErrFailed,
    };

// ── Сканер ─────────────────────────────────────────────────────────────────

/// Камера во весь экран: первый QR Bloom — сопряжение, и назад.
class PcScanScreen extends ConsumerStatefulWidget {
  const PcScanScreen({super.key});

  @override
  ConsumerState<PcScanScreen> createState() => _PcScanScreenState();
}

class _PcScanScreenState extends ConsumerState<PcScanScreen> {
  final MobileScannerController _camera = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );

  /// Код уже взят и идёт сопряжение — остальные кадры не в счёт.
  bool _busy = false;

  /// Последний не-Bloom код: про него уже сказали, второй раз не надо.
  String? _rejected;

  @override
  void dispose() {
    unawaited(_camera.dispose());
    super.dispose();
  }

  Future<void> _onCode(BarcodeCapture capture) async {
    final text = capture.barcodes.firstOrNull?.rawValue;
    if (_busy || text == null || text == _rejected) return;
    final l = context.l;
    if (PairOffer.parse(text) == null) {
      _rejected = text;
      showToast(context, l.pcErrNotBloom, kind: ToastKind.warn);
      return;
    }
    setState(() => _busy = true);
    unawaited(HapticFeedback.mediumImpact());
    final r = await ref.read(pcProvider.notifier).pairQr(text);
    if (!mounted) return;
    final name = ref.read(pcProvider).link?.name ?? '';
    showToast(
      context,
      pairMessage(l, r, name),
      kind: r == PairResult.ok ? ToastKind.success : ToastKind.error,
    );
    if (r == PairResult.ok) {
      context.go('/settings/pc');
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _camera,
            onDetect: _onCode,
            errorBuilder: (context, _) => Center(
              child: Text(
                context.l.pcNoCamera,
                style: theme.bodyMedium?.copyWith(color: Colors.white70),
              ),
            ),
          ),
          // Рамка, куда навести код.
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.85),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(t.radius + 10),
              ),
              child: _busy
                  ? const Center(
                      child: BloomSpinner(
                        size: 28,
                        stroke: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : null,
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: CircleIconButton(
                    icon: Bi.altArrowLeft,
                    size: 48,
                    iconSize: 22,
                    background: Colors.transparent,
                    color: Colors.white,
                    onTap: () => context.go('/settings/pc'),
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
                  child: Text(
                    context.l.pcScanHint,
                    textAlign: TextAlign.center,
                    style: theme.bodyMedium?.copyWith(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Код ────────────────────────────────────────────────────────────────────

/// Шторка «Ввести код»: найти ПК с открытым окном сопряжения, потом шесть цифр.
Future<void> _enterCode(BuildContext context) =>
    showBloomSheetChild<void>(context: context, child: const _CodeSheet());

class _CodeSheet extends ConsumerStatefulWidget {
  const _CodeSheet();

  @override
  ConsumerState<_CodeSheet> createState() => _CodeSheetState();
}

class _CodeSheetState extends ConsumerState<_CodeSheet> {
  final TextEditingController _code = TextEditingController();
  List<FoundPc>? _found; // null — ищем
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _found = null);
    final found = await ref.read(pcProvider.notifier).findForCode();
    if (mounted) setState(() => _found = found);
  }

  Future<void> _connect(FoundPc pc) async {
    final code = _code.text.replaceAll(RegExp(r'\D'), '');
    if (code.length != 6 || _busy) return;
    final l = context.l;
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await ref.read(pcProvider.notifier).pairCode(pc, code);
    if (!mounted) return;
    if (r == PairResult.ok) {
      showToast(
        context,
        pairMessage(l, r, ref.read(pcProvider).link?.name ?? pc.name),
        kind: ToastKind.success,
      );
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _error = pairMessage(l, r, pc.name);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final found = _found;

    Widget note(String text, {Color? color}) => Padding(
      padding: const EdgeInsets.fromLTRB(kSheetEdge, 8, kSheetEdge, 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: theme.bodySmall?.copyWith(color: color ?? t.text2, height: 1.5),
      ),
    );

    if (found == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BloomSpinner(size: 22, stroke: 2.2, color: t.text),
            const SizedBox(height: 12),
            note(l.pcCodeSearching),
          ],
        ),
      );
    }
    if (found.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(kSheetEdge, 8, kSheetEdge, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            note(l.pcCodeNone),
            const SizedBox(height: 8),
            PlatformAction(label: l.pcCodeRetry, height: 48, onTap: _search),
          ],
        ),
      );
    }
    // Обычно ПК один; если окно открыто на двух — берём первый ответивший.
    final pc = found.first;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        kSheetEdge,
        4,
        kSheetEdge,
        12 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              BloomIcon(Bi.monitor, size: 20, color: t.iconFg),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  pc.name.isEmpty ? pc.address : pc.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GlassBox(
            borderRadius: BorderRadius.circular(t.radius),
            child: BloomField(
              controller: _code,
              hint: '••• •••',
              autofocus: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 7,
              formatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
              ],
              onChanged: (v) {
                if (v.replaceAll(' ', '').length == 6) _connect(pc);
              },
              style: theme.headlineSmall?.copyWith(
                color: t.text,
                letterSpacing: 6,
              ),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          note(_error ?? l.pcCodeHint, color: _error != null ? t.danger : null),
          PlatformAction(
            label: l.pcConnect,
            height: 48,
            busy: _busy,
            onTap: () => _connect(pc),
          ),
        ],
      ),
    );
  }
}
