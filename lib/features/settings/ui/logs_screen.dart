/// Settings → System → Log: its own page with copy, save and clear. Newest on
/// top: whoever opens it looks for what just happened; copies and files keep
/// the time order.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/log/bloom_log.dart';
import '../../../core/store/text_files.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/glass.dart';
import '../../../shared/ui/pressable.dart';
import '../../../shared/ui/subpage_header.dart';
import '../../../shared/ui/atoms.dart';

class LogsScreen extends ConsumerStatefulWidget {
  const LogsScreen({super.key});

  @override
  ConsumerState<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends ConsumerState<LogsScreen> {
  /// A snapshot, or the list would move under the finger with each new entry.
  late List<LogEntry> _entries = BloomLog.instance.entries.reversed.toList();

  void _reload() =>
      setState(() => _entries = BloomLog.instance.entries.reversed.toList());

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: BloomLog.instance.text()));
    if (!mounted) return;
    showToast(context, context.l.logsCopied, kind: ToastKind.success);
  }

  Future<void> _save() async {
    final l = context.l;
    final messenger = ScaffoldMessenger.of(context);
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final name = 'bloom-${now.year}-${two(now.month)}-${two(now.day)}.log';
    final ok = await saveTextFile(
      name,
      // A BOM first: the file travels to other computers, and Windows opens
      // UTF-8 without it as ANSI.
      '\u{FEFF}${BloomLog.instance.text()}',
      mime: 'text/plain',
    );
    if (!ok) return; // the dialog was closed: silence
    messenger.toast(l.logsSaved, kind: ToastKind.success);
  }

  Future<void> _clear() async {
    final l = context.l;
    final messenger = ScaffoldMessenger.of(context);
    await BloomLog.instance.clear();
    _reload();
    messenger.toast(l.logsCleared, kind: ToastKind.success);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final empty = _entries.isEmpty;

    return SubPage(
      title: l.sysLogTitle,
      onBack: () => context.go('/settings/system'),
      children: [
        Row(
          children: [
            Expanded(
              child: _LogButton(
                icon: Bi.copy,
                label: l.logsCopy,
                onTap: empty ? null : _copy,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _LogButton(
                icon: Bi.export,
                label: l.logsSave,
                onTap: empty ? null : _save,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _LogButton(
                icon: Bi.trashBinTrash,
                label: l.logsClear,
                danger: true,
                onTap: empty ? null : _clear,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (empty)
          Center(child: CenterNote(l.logsEmpty))
        else
          GlassBox(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: SelectionArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final entry in _entries) _LogLine(entry: entry),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A monospaced line, coloured by level.
class _LogLine extends StatelessWidget {
  const _LogLine({required this.entry});

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final color = switch (entry.level) {
      LogLevel.error => const Color(0xFFFF6B6B),
      LogLevel.warn => t.text,
      LogLevel.info => t.text2,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        entry.format(),
        style: TextStyle(
          // Read as columns by time: a proportional font breaks them.
          fontFamily: 'monospace',
          fontSize: 11,
          height: 1.45,
          color: color,
        ),
      ),
    );
  }
}

/// An icon and a label, a third of the width.
class _LogButton extends StatelessWidget {
  const _LogButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final BloomGlyph icon;
  final String label;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final enabled = onTap != null;
    final color = !enabled
        ? t.muted
        : danger
        ? t.danger
        : t.text;

    return Pressable(
      onTap: onTap,
      scale: 0.97,
      child: GlassBox(
        borderRadius: BorderRadius.circular(t.radius),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              BloomIcon(icon, size: 18, color: color),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
