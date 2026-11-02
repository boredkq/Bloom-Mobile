/// Platform registration: the one place where the core learns about concrete
/// providers.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n/l10n.dart';
import '../core/providers/provider_text.dart';
import '../core/providers/registry.dart';
import '../providers/soundcloud/sc_provider.dart';
import '../providers/yandex/ym_provider.dart';
import '../providers/ytmusic/ytm_provider.dart';

final registryProvider = Provider<ProviderRegistry>((ref) {
  providerTextSource = () {
    final l = globalL10n;
    return l == null
        ? null
        : ProviderText(
            untitled: l.commonUntitled,
            unknownArtist: l.commonUnknownArtist,
            album: l.commonAlbum,
            playlist: l.commonPlaylist,
            artist: l.commonArtist,
            likesOf: l.iuLikesTitle,
          );
  };
  // Yandex always registers but shows only after login: its `isEnabled` looks
  // at the saved token (see `ymAuthProvider`). YouTube Music needs no login, so
  // it's always on.
  return ProviderRegistry()
    ..register(const SoundCloudProvider())
    ..register(const YtmusicProvider())
    ..register(const YandexProvider());
});

/// Platform picked in search; [kAllProviders] searches them all.
final activeProviderIdProvider = StateProvider<String>((ref) => kAllProviders);
