/// "What's new" and "Update history", as sheets. A note's pages are sections of
/// one scroll, what a finger does anyway. Text is lists only: a line starting
/// with `- ` is an item, others a paragraph.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_mark.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/pressable.dart';
import '../update_notes_store.dart';

Future<void> showUpdateNote(BuildContext context, UpdateNote note) {
  final l = context.l;
  final locale = Localizations.localeOf(context).languageCode;
  return showBloomSheetChild<void>(
    context: context,
    header: _NotesHeader(
      title: note.title.isEmpty ? l.updWhatsNew : note.title,
      subtitle: formatNoteDate(note.date, locale),
    ),
    child: _NoteBody(note: note),
  );
}

/// A tap opens the note over the list; closing it comes back to the history.
Future<void> showUpdateHistory(BuildContext context) {
  final l = context.l;
  return showBloomSheetChild<void>(
    context: context,
    header: _NotesHeader(title: l.updHistory, subtitle: l.updHistorySub),
    child: const _HistoryList(),
  );
}

/// The app's mark, a title, a date or a caption.
class _NotesHeader extends StatelessWidget {
  const _NotesHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
      child: Row(
        children: [
          BloomMark(size: 34, color: t.text),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.titleLarge,
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodyMedium,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The manifest's pages as sections, "Done" at the end.
class _NoteBody extends StatelessWidget {
  const _NoteBody({required this.note});

  final UpdateNote note;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final theme = Theme.of(context).textTheme;
    final pages = [
      for (final page in note.pages)
        if (!page.isEmpty) page,
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (pages.isEmpty)
            Text(l.updNotesEmpty, style: theme.bodyMedium)
          else
            for (var i = 0; i < pages.length; i++) ...[
              if (i > 0) const SizedBox(height: 22),
              UpdateNoteSection(page: pages[i]),
            ],
          const SizedBox(height: 22),
          BloomButton(
            label: l.commonDone,
            icon: Bi.checkCircle,
            tone: ButtonTone.accent,
            pill: false,
            height: 54,
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// A title, the text as a list, a picture. Public: the "Version" page shows it
/// too.
class UpdateNoteSection extends StatelessWidget {
  const UpdateNoteSection({super.key, required this.page});

  final UpdateNotePage page;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final image = page.image;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (page.title.isNotEmpty) ...[
          Text(page.title, style: theme.titleMedium),
          const SizedBox(height: 8),
        ],
        if (page.body.isNotEmpty) _NoteText(body: page.body),
        if (image != null) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(t.radius),
            child: Image.network(
              image,
              fit: BoxFit.cover,
              // Pictures are optional: the text reads without one.
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : AspectRatio(
                      aspectRatio: 16 / 9,
                      child: ColoredBox(color: t.ovlLine2),
                    ),
            ),
          ),
        ],
      ],
    );
  }
}

/// `- ` lines as items, others as paragraphs.
class _NoteText extends StatelessWidget {
  const _NoteText({required this.body});

  final String body;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final style = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: t.text2, height: 1.45);
    final lines = body.split('\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < lines.length; i++)
          if (lines[i].trim().isNotEmpty) ...[
            if (i > 0) const SizedBox(height: 7),
            if (lines[i].trimLeft().startsWith('- '))
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Its own dot: "•" in the font has too much air around it and
                  // the text moves right.
                  Padding(
                    padding: const EdgeInsets.only(top: 7, right: 10),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: t.text2,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      lines[i].trimLeft().substring(2).trim(),
                      style: style,
                    ),
                  ),
                ],
              )
            else
              Text(lines[i].trim(), style: style),
          ],
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
              if (i > 0) sheetDivider(),
              _HistoryRow(item: items[i]),
            ],
          ],
        );
      },
    );
  }
}

class _HistoryRow extends ConsumerWidget {
  const _HistoryRow({required this.item});

  final NoteHeadline item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).languageCode;
    final date = formatNoteDate(item.date, locale);

    return Pressable(
      onTap: () => _open(context, ref, locale),
      scale: 0.98,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 16, 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'v${item.version}',
                    style: theme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.title.isNotEmpty || date.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (item.title.isNotEmpty) item.title,
                        if (date.isNotEmpty) date,
                      ].join(' · '),
                      style: theme.bodySmall?.copyWith(color: t.text2),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            BloomIcon(Bi.altArrowRight, size: 16, color: t.text2),
          ],
        ),
      ),
    );
  }

  /// The list already fetched the manifest, so the note opens at once and needs
  /// no spinner.
  Future<void> _open(BuildContext context, WidgetRef ref, String locale) async {
    final note = await ref.read(updateNotesProvider).note(item.version, locale);
    if (!context.mounted || note == null) return;
    await showUpdateNote(context, note);
  }
}
