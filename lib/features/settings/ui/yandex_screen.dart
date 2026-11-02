/// Yandex Music: OAuth device flow, "Connect" opens the Yandex ID page and
/// shows a code while the token is polled. State lives in [ymAuthProvider];
/// here it's the look and wording the typed reasons.
library;

import 'dart:async' show scheduleMicrotask;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../providers/yandex/ym_auth.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/glass.dart';
import '../../../shared/ui/platform_logo.dart';
import 'platform_page.dart';

class YandexSettingsScreen extends ConsumerStatefulWidget {
  const YandexSettingsScreen({super.key});

  @override
  ConsumerState<YandexSettingsScreen> createState() =>
      _YandexSettingsScreenState();
}

class _YandexSettingsScreenState extends ConsumerState<YandexSettingsScreen> {
  /// Kept: in [dispose] `ref` is dead and throws.
  late final YmAuthController _auth = ref.read(ymAuthProvider.notifier);

  @override
  void initState() {
    super.initState();
    // Status anew on opening, polling stops on leaving.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _auth.refresh();
    });
  }

  @override
  void dispose() {
    // Cancelling changes a provider this screen listens to, and in `dispose`
    // the screen is already dead: a sync call trips an assert. A microtask
    // moves it past the tree's teardown.
    scheduleMicrotask(_auth.cancelAuth);
    super.dispose();
  }

  void _guide() => showPlatformGuide(
    context,
    mark: const BrandMark.platform(MusicSource.yandex),
    title: context.l.ymGuideTitle,
    steps: [
      context.l.ymStep1,
      context.l.ymStep2,
      context.l.ymStep3,
      context.l.ymStep4,
    ],
    note: context.l.ymGuideNote,
  );

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final l = context.l;
    final theme = Theme.of(context).textTheme;
    final s = ref.watch(ymAuthProvider);

    final note = s.note == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(
              _noteText(l, s.note!),
              textAlign: TextAlign.center,
              style: theme.bodySmall?.copyWith(
                color: s.note!.kind == YmAuthNoteKind.error
                    ? t.danger
                    : t.text2,
              ),
            ),
          );

    return PlatformPage(
      mark: const BrandMark.platform(MusicSource.yandex),
      onBack: () => context.go('/settings'),
      status: s.checking
          ? l.ymChecking
          : s.authed
          ? l.ymConnected
          : l.ymNotConnected,
      statusColor: s.authed && !s.checking ? kPlatformOk : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (s.authed)
            _PlusBadge(hasPlus: s.hasPlus)
          else ...[
            PlatformCard(
              mark: const BrandMark.platform(MusicSource.yandex),
              title: l.ymGuideTitle,
              subtitle: l.ymGuideSubtitle,
              onTap: _guide,
            ),
            if (s.userCode case final code?) ...[
              const SizedBox(height: 12),
              _CodeCard(code: code, verifyUrl: s.verifyUrl),
            ],
          ],
          ?note,
        ],
      ),
      actions: [
        if (s.authed)
          PlatformAction(
            label: l.ymLogout,
            onTap: () => ref.read(ymAuthProvider.notifier).logout(),
          )
        else if (s.userCode case final _?)
          PlatformAction(
            label: l.ymOpenPage,
            onTap: () => openVerifyPage(s.verifyUrl ?? 'https://ya.ru/device'),
          )
        else
          PlatformAction(
            label: l.ymConnect,
            busy: s.connecting,
            onTap: () => ref.read(ymAuthProvider.notifier).startAuth(),
          ),
      ],
    );
  }
}

/// `ym.err.*` come from the network layer; an unknown code shows as it is, it's
/// the service's text.
String _noteText(AppLocalizations l, YmAuthNote note) => switch (note.kind) {
  YmAuthNoteKind.gettingCode => l.ymGettingCode,
  YmAuthNoteKind.waiting => l.ymWaiting,
  YmAuthNoteKind.codeExpired => l.ymCodeExpired,
  YmAuthNoteKind.error => describeYmError(l, note.errorCode ?? ''),
};

/// In the user's language.
String describeYmError(AppLocalizations l, String code) => switch (code) {
  'ym.err.auth' => l.ymErrAuth,
  'ym.err.noToken' => l.ymNotConnected,
  'ym.err.needPlus' => l.ymErrNeedPlus,
  'ym.err.network' || 'ym.err.badJson' => l.ymErrNetwork,
  _ => code,
};

class _PlusBadge extends StatelessWidget {
  const _PlusBadge({required this.hasPlus});

  final bool? hasPlus;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final l = context.l;
    final body = Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5);
    // The first half stands out, the second is plain. Status unknown: one grey
    // line.
    return switch (hasPlus) {
      true => Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: l.ymPlusActiveA,
              style: body?.copyWith(
                color: kPlatformOk,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(text: ' ${l.ymPlusActiveB}', style: body),
          ],
        ),
        textAlign: TextAlign.center,
      ),
      false => Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: l.ymPlusNoneA,
              style: body?.copyWith(color: t.text, fontWeight: FontWeight.w700),
            ),
            TextSpan(text: ' ${l.ymPlusNoneB}', style: body),
          ],
        ),
        textAlign: TextAlign.center,
      ),
      null => Text(l.ymPlusUnknown, style: body, textAlign: TextAlign.center),
    };
  }
}

/// Large digits (a tap copies) and the confirmation page's address. A button
/// reopens it: the browser doesn't always rise by itself.
class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.code, required this.verifyUrl});

  final String code;
  final String? verifyUrl;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final l = context.l;
    final theme = Theme.of(context).textTheme;
    final url = verifyUrl ?? 'https://ya.ru/device';

    return GlassBox(
      borderRadius: BorderRadius.circular(t.radius),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '${l.ymCodePromptA} ', style: theme.bodySmall),
                  TextSpan(
                    text: url,
                    style: theme.bodySmall?.copyWith(
                      color: t.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(text: ' ${l.ymCodePromptB}', style: theme.bodySmall),
                ],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            // Typing digits by hand in another browser is awkward.
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: code));
                showToast(context, l.ymCodeCopied);
              },
              child: Text(
                code,
                textAlign: TextAlign.center,
                style: theme.headlineSmall?.copyWith(
                  color: t.accent,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
