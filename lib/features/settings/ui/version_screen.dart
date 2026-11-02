/// Version: the update check and the new version's notes. The check runs on
/// opening, that's why one comes here; the button is for a second go, or for
/// the release page when there's something new.
///
/// The note stands on the page: reading it is what the page is for. It's the
/// found version's, or the installed one's if the manifest lacks it. The APK
/// isn't installed from here: the release page opens
/// in the browser.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/log/bloom_log.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/glass.dart';
import '../../../shared/ui/subpage_header.dart';
import '../about_store.dart';
import '../update_notes_store.dart';
import 'settings_rows.dart';
import 'update_notes_sheet.dart';

class VersionScreen extends ConsumerStatefulWidget {
  const VersionScreen({super.key});

  @override
  ConsumerState<VersionScreen> createState() => _VersionScreenState();
}

class _VersionScreenState extends ConsumerState<VersionScreen> {
  @override
  void initState() {
    super.initState();
    // The version first: without it there's nothing to compare the release
    // with.
    Future.microtask(() async {
      final about = ref.read(aboutProvider.notifier);
      await about.loadVersion();
      if (mounted) await about.check();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final about = ref.watch(aboutProvider);

    return SubPage(
      title: l.aboutVersion,
      onBack: () => context.go('/settings'),
      children: [
        _StatusCard(about: about),
        const SizedBox(height: 14),
        if (about.phase == UpdatePhase.available)
          BloomButton(
            label: l.aboutOpenRelease,
            icon: Bi.downloadMinimalistic,
            tone: ButtonTone.accent,
            pill: false,
            height: 54,
            onTap: () => _openRelease(about.releaseUrl),
          )
        else
          BloomButton(
            label: l.aboutRecheck,
            icon: Bi.refresh,
            tone: ButtonTone.accent,
            pill: false,
            height: 54,
            busy: about.phase == UpdatePhase.checking,
            onTap: () => ref.read(aboutProvider.notifier).check(),
          ),
        const SizedBox(height: 26),
        // Not before the check ends: until then it's unknown whose note to
        // show.
        if (about.phase == UpdatePhase.uptodate ||
            about.phase == UpdatePhase.available ||
            about.phase == UpdatePhase.error) ...[
          _NoteBlock(
            version:
                about.phase == UpdatePhase.available && about.latest.isNotEmpty
                ? about.latest
                : about.version,
            fallback: about.version,
          ),
        ],
        const SizedBox(height: 22),
        // The notes live in the same manifest as the one above.
        SettingsGroupCard(
          dividerInset: 52,
          rows: [
            SettingsLinkRow(
              icon: Bi.history,
              title: l.updHistory,
              subtitle: l.updHistorySub,
              onTap: () => showUpdateHistory(context),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _openRelease(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// The outcome in large: an icon in a circle, a status line, and which version
/// is installed.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.about});

  final AboutState about;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final l = context.l;
    final theme = Theme.of(context).textTheme;

    final (icon, color, title) = switch (about.phase) {
      UpdatePhase.idle ||
      UpdatePhase.checking => (null, t.accent, l.aboutChecking),
      // The toasts' colours, known across the app.
      UpdatePhase.uptodate => (
        Bi.checkCircleBold,
        kindColor(ToastKind.success, t),
        l.aboutUptodate,
      ),
      UpdatePhase.available => (
        Bi.downloadMinimalistic,
        t.accent,
        l.aboutAvailable(about.latest),
      ),
      UpdatePhase.error => (
        Bi.dangerTriangleBold,
        kindColor(ToastKind.warn, t),
        l.aboutError,
      ),
    };

    return GlassBox(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 30, 20, 30),
        child: Column(
          children: [
            TintCircle(
              size: 72,
              color: color.withValues(alpha: 0.16),
              // One box for the spinner and the icon: the block doesn't jump
              // when the outcome comes.
              child: icon == null
                  ? BloomSpinner(size: 28, stroke: 2.6, color: color)
                  : BloomIcon(icon, size: 34, color: color),
            ),
            const SizedBox(height: 18),
            Text(title, textAlign: TextAlign.center, style: theme.titleLarge),
            const SizedBox(height: 6),
            Text(
              about.version.isEmpty
                  // No answer from the platform: a dash is more honest than a
                  // zero.
                  ? '${l.aboutVersion} —'
                  : l.aboutInstalled(about.version),
              textAlign: TextAlign.center,
              style: theme.bodyMedium?.copyWith(color: t.text2),
            ),
          ],
        ),
      ),
    );
  }
}

/// A version's note. It comes from the network or the cache, so the block shows
/// its spinner and explains an empty outcome: a version may have no note.
class _NoteBlock extends ConsumerStatefulWidget {
  const _NoteBlock({required this.version, required this.fallback});

  /// The found version's or the installed one's.
  final String version;

  /// The installed version, for when the manifest doesn't know the found one
  /// yet.
  final String fallback;

  @override
  ConsumerState<_NoteBlock> createState() => _NoteBlockState();
}

class _NoteBlockState extends ConsumerState<_NoteBlock> {
  Future<UpdateNote?>? _future;
  String? _asked;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensure();
  }

  @override
  void didUpdateWidget(_NoteBlock old) {
    super.didUpdateWidget(old);
    // The check ended and the version changed from installed to found: I ask
    // again. Otherwise one request lives on.
    _ensure();
  }

  void _ensure() {
    if (widget.version.isEmpty || _asked == widget.version) return;
    // Here: `Localizations` can't be reached from `initState`.
    final locale = Localizations.localeOf(context).languageCode;
    final notes = ref.read(updateNotesProvider);
    _asked = widget.version;
    _future = () async {
      final note = await notes.note(widget.version, locale);
      if (note != null) return note;
      // The manifest doesn't know the found version yet: the installed one's
      // note is new to them as well.
      if (widget.fallback.isEmpty || widget.fallback == widget.version) {
        return null;
      }
      return notes.note(widget.fallback, locale);
    }();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final theme = Theme.of(context).textTheme;

    return FutureBuilder<UpdateNote?>(
      future: _future,
      builder: (context, snapshot) {
        if (_future == null ||
            snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Center(child: BloomSpinner(size: 22, stroke: 2.4)),
          );
        }
        if (snapshot.hasError) {
          logWarn('notes', 'note did not load: ${snapshot.error}');
          return Text(l.updNotesError, style: theme.bodyMedium);
        }
        final note = snapshot.data;
        if (note == null) return Text(l.updNotesEmpty, style: theme.bodyMedium);
        return UpdateNoteView(note: note);
      },
    );
  }
}
