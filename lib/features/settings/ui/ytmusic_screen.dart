/// YouTube Music: nothing to set up, all of it works without signing in. The
/// screen says so; the guide says what works.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/ui/platform_logo.dart';
import 'platform_page.dart';

class YtmusicSettingsScreen extends StatelessWidget {
  const YtmusicSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l;

    return PlatformPage(
      mark: const BrandMark.platform(MusicSource.ytmusic),
      onBack: () => context.go('/settings'),
      status: '${l.ytmConfigured} — ${l.ytmNoAuth}',
      statusColor: kPlatformOk,
      body: PlatformCard(
        mark: const BrandMark.platform(MusicSource.ytmusic),
        title: l.ytmGuideTitle,
        subtitle: l.ytmGuideSubtitle,
        onTap: () => showPlatformGuide(
          context,
          mark: const BrandMark.platform(MusicSource.ytmusic),
          title: l.ytmGuideTitle,
          steps: [l.ytmStep1, l.ytmStep2, l.ytmStep3],
          note: l.ytmHelp,
        ),
      ),
    );
  }
}
