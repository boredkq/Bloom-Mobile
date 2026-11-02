/// Last.fm settings on the [PlatformPage] layout. The guide is in a sheet, the
/// key fields under a button: they're typed once.
///
/// Sign-in in two steps through the browser; coming back tries for the session
/// silently, "Done" is the fallback.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/platform_logo.dart';
import '../../../shared/ui/subpage_header.dart';
import '../../lastfm/lastfm_store.dart';
import 'platform_page.dart';
import 'settings_rows.dart';

const BrandMark _mark = BrandMark.service(Service.lastfm);

class LastfmSettingsScreen extends ConsumerStatefulWidget {
  const LastfmSettingsScreen({super.key});

  @override
  ConsumerState<LastfmSettingsScreen> createState() =>
      _LastfmSettingsScreenState();
}

class _LastfmSettingsScreenState extends ConsumerState<LastfmSettingsScreen>
    with WidgetsBindingObserver {
  late final TextEditingController _key = TextEditingController(
    text: ref.read(lastfmProvider).apiKey,
  );
  late final TextEditingController _secret = TextEditingController(
    text: ref.read(lastfmProvider).apiSecret,
  );

  /// Without saved keys there's no signing in: open at once then.
  late bool _keysOpen = !ref.read(lastfmProvider).hasKeys;

  bool _keyVisible = false;
  bool _secretVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _key.dispose();
    _secret.dispose();
    super.dispose();
  }

  /// Back from the browser: the controller holds the token, so "Done" is rarely
  /// needed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!ref.read(lastfmProvider).oauthPending) return;
    _finish(silent: true);
  }

  Future<void> _finish({bool silent = false}) async {
    final ok = await ref
        .read(lastfmProvider.notifier)
        .finishOAuth(silent: silent);
    if (!ok || !mounted) return;
    setState(() => _keysOpen = false);
    toaster.show(
      context.l.lfmToastConnected(ref.read(lastfmProvider).user),
      kind: ToastKind.success,
    );
  }

  void _saveKeys() {
    final ok = ref
        .read(lastfmProvider.notifier)
        .saveKeys(_key.text, _secret.text);
    if (!ok) return;
    toaster.show(context.l.lfmToastKeysSaved);
    setState(() {});
  }

  void _logout() {
    ref.read(lastfmProvider.notifier).logout();
    toaster.show(context.l.lfmToastDisconnected);
    setState(() => _keysOpen = false);
  }

  void _guide() => showPlatformGuide(
    context,
    mark: _mark,
    title: context.l.lfmGuideTitle,
    steps: [
      context.l.lfmStep1,
      context.l.lfmStep2,
      context.l.lfmStep3,
      context.l.lfmStep4,
    ],
    note: context.l.lfmGuideNote,
  );

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final s = ref.watch(lastfmProvider);

    return PlatformPage(
      mark: _mark,
      onBack: () => context.go('/settings'),
      status: s.connected ? l.lfmConnectedAs(s.user) : l.lfmNotConnected,
      statusColor: s.connected ? kPlatformOk : null,
      body: s.connected ? _connectedBody(s) : _loginBody(s),
      actions: [
        if (s.connected)
          PlatformAction(label: l.lfmLogout, onTap: _logout)
        else ...[
          // The sign-in has started: no need to open the browser again.
          if (s.oauthPending)
            PlatformAction(
              label: l.lfmDone,
              busy: s.busy,
              onTap: () => _finish(),
            ),
          PlatformAction(
            label: l.lfmLogin,
            busy: s.busy && !s.oauthPending,
            onTap: () => ref.read(lastfmProvider.notifier).startOAuth(),
          ),
          PlatformAction(
            label: _keysOpen ? l.commonHide : l.lfmKeys,
            onTap: () => setState(() => _keysOpen = !_keysOpen),
          ),
        ],
      ],
    );
  }

  Widget _connectedBody(LastfmState s) {
    final l = context.l;
    final controller = ref.read(lastfmProvider.notifier);
    final card = SettingsGroupCard(
      dividerInset: 16,
      rows: [
        SettingsToggleRow(
          title: l.lfmScrobble,
          subtitle: l.lfmScrobbleSub,
          value: s.scrobbleEnabled,
          onChanged: controller.setScrobble,
        ),
        // Last.fm's own term, not translated.
        SettingsToggleRow(
          title: 'Now Playing',
          subtitle: l.lfmNowPlayingSub,
          value: s.nowPlayingEnabled,
          onChanged: controller.setNowPlaying,
        ),
      ],
    );
    if (s.pending == 0) return card;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        card,
        const SizedBox(height: 10),
        Text(
          l.lfmPending(s.pending),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _loginBody(LastfmState s) {
    final l = context.l;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlatformCard(
          mark: _mark,
          title: l.lfmGuideTitle,
          subtitle: l.lfmGuideSubtitle,
          onTap: _guide,
        ),
        if (_keysOpen) ...[
          const SizedBox(height: 10),
          PlatformField(
            controller: _key,
            hint: 'API Key',
            mono: true,
            obscure: !_keyVisible,
            icon: _keyVisible ? Bi.eye : Bi.eyeClosed,
            onIcon: () => setState(() => _keyVisible = !_keyVisible),
          ),
          const SizedBox(height: 8),
          PlatformField(
            controller: _secret,
            hint: 'API Secret',
            mono: true,
            obscure: !_secretVisible,
            icon: _secretVisible ? Bi.eye : Bi.eyeClosed,
            onIcon: () => setState(() => _secretVisible = !_secretVisible),
          ),
          const SizedBox(height: 10),
          PlatformAction(label: l.lfmSaveKeys, height: 48, onTap: _saveKeys),
        ],
        if (s.note case final note?) ...[
          const SizedBox(height: 14),
          Builder(
            builder: (context) => Text(
              _noteText(l, note),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color:
                    note.kind == LfmNoteKind.error ||
                        note.kind == LfmNoteKind.sessionLost
                    ? context.bloom.danger
                    : context.bloom.text2,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The service's own texts show as they are.
String _noteText(AppLocalizations l, LfmNote note) => switch (note.kind) {
  LfmNoteKind.gettingToken => l.lfmGettingToken,
  LfmNoteKind.confirmAccess => l.lfmConfirmAccess,
  LfmNoteKind.checking => l.lfmChecking,
  LfmNoteKind.notConfirmed => l.lfmNotConfirmed,
  LfmNoteKind.loginFirst => l.lfmLoginFirst,
  LfmNoteKind.needKeys => l.lfmNeedKeys,
  LfmNoteKind.networkError => l.lfmNetworkError,
  LfmNoteKind.error => l.lfmError(note.message ?? ''),
  LfmNoteKind.sessionLost => l.lfmSessionLost,
};
