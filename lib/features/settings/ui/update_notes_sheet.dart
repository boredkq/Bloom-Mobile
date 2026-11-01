/// "What's new" and "Update history", as sheets. A major version shows its
/// picture and the summary on a plate, a patch "In this version" and its items.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/subpage_header.dart';
import '../update_notes_store.dart';
import 'settings_rows.dart';
import 'settings_sheets.dart';

Future<void> showUpdateNote(BuildContext context, UpdateNote note) {
  return showBloomSheetChild<void>(
    context: context,
    child: Builder(
      builder: (sheet) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            UpdateNoteView(note: note),
            const SizedBox(height: 24),
            BloomButton(
              label: sheet.l.commonClose,
              tone: ButtonTone.plate,
              pill: false,
              height: 54,
              onTap: () => Navigator.of(sheet).pop(),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A tap opens the note over the list; closing it comes back to the history.
Future<void> showUpdateHistory(BuildContext context) {
  return showBloomSheetChild<void>(
    context: context,
    header: settingsSheetHeader(context, context.l.updHistory),
    child: const _HistoryList(),
  );
}

/// A note whole: its picture, "Bloom 1.0.0", the date, the text. Public: the
/// "Version" page shows it too.
class UpdateNoteView extends StatelessWidget {
  const UpdateNoteView({super.key, required this.note});

  final UpdateNote note;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final l = context.l;
    final theme = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).languageCode;
    final date = formatNoteDate(note.date, locale);
    final image = note.image;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (image != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(t.radius),
            child: Image.network(
              image,
              fit: BoxFit.fitWidth,
              // Pictures are optional: the text reads without one.
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : AspectRatio(
                      aspectRatio: 16 / 9,
                      child: ColoredBox(color: t.text.withValues(alpha: 0.04)),
                    ),
            ),
          ),
          const SizedBox(height: 20),
        ],
        Text('Bloom ${note.version}', style: theme.titleLarge),
        if (date.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(date, style: theme.bodyMedium?.copyWith(color: t.text2)),
        ],
        const SizedBox(height: 18),
        if (!note.hasContent) Text(l.updNotesEmpty, style: theme.bodyMedium),
        if (note.summary.isNotEmpty) _SummaryPlate(text: note.summary),
        if (note.summary.isNotEmpty && note.items.isNotEmpty)
          const SizedBox(height: 18),
        if (note.items.isNotEmpty) _Items(items: note.items),
      ],
    );
  }
}

class _SummaryPlate extends StatelessWidget {
  const _SummaryPlate({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: t.text.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(t.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsCaption(context.l.updWhatsNew.toUpperCase()),
          const SizedBox(height: 8),
          Text(
            text,
            style: theme.bodyMedium?.copyWith(color: t.text, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// A patch's items under a rail: a tick at each, the last one turning the corner.
class _Items extends StatelessWidget {
  const _Items({required this.items});

  final List<String> items;

  static const double _gap = 8;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final style = theme.bodyMedium?.copyWith(color: t.text2, height: 1.35);
    final line = t.text.withValues(alpha: 0.16);
    final tickY = ((style?.fontSize ?? 14) * 0.7).roundToDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(context.l.updInThis, style: theme.titleMedium),
        const SizedBox(height: 12),
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : _gap),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 12,
                  top: i == 0 ? 0 : -_gap,
                  bottom: i == items.length - 1 ? null : 0,
                  height: i == items.length - 1
                      ? tickY + (i == 0 ? 0 : _gap)
                      : null,
                  child: SizedBox(width: 1, child: ColoredBox(color: line)),
                ),
                Positioned(
                  left: 12,
                  top: tickY,
                  child: SizedBox(
                    width: 8,
                    height: 1,
                    child: ColoredBox(color: line),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 32),
                  child: Text(items[i], style: style),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _HistoryList extends ConsumerStatefulWidget {
  const _HistoryList();

  @override
  ConsumerState<_HistoryList> createState() => _HistoryListState();
}

class _HistoryListState extends ConsumerState<_HistoryList> {
  Future<List<NoteHeadline>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Not in `initState`: the locale comes from inherited `Localizations`.
    // Asked once, or `FutureBuilder` would restart it every frame.
    final locale = Localizations.localeOf(context).languageCode;
    _future ??= ref.read(updateNotesProvider).history(locale);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final theme = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).languageCode;

    return FutureBuilder<List<NoteHeadline>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 34),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ),
          );
        }
        final items = snapshot.data ?? const <NoteHeadline>[];
        if (snapshot.hasError || items.isEmpty) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            child: Text(
              snapshot.hasError ? l.updNotesError : l.updHistoryEmpty,
              style: theme.bodyMedium,
            ),
          );
        }
        return SheetPanel(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) sheetDivider(indent: 18),
              SettingsLinkRow(
                title: 'v${items[i].version}',
                subtitle: formatNoteDate(items[i].date, locale),
                onTap: () => _open(context, items[i].version, locale),
              ),
            ],
          ],
        );
      },
    );
  }

  /// The list already fetched the manifest, so the note opens at once and needs
  /// no spinner.
  Future<void> _open(
    BuildContext context,
    String version,
    String locale,
  ) async {
    final note = await ref.read(updateNotesProvider).note(version, locale);
    if (!context.mounted || note == null) return;
    await showUpdateNote(context, note);
  }
}
