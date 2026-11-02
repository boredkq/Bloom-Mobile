/// Platform name in the UI language. Separate from the enum: `MusicSource`
/// lives in the entities layer and knows nothing of Flutter, and only two
/// values get translated.
library;

import '../entities/entities.dart';
import 'l10n.dart';

extension MusicSourceLabel on MusicSource {
  String label10n(AppLocalizations l) => switch (this) {
    MusicSource.local => l.sourceLocal,
    MusicSource.yandex => l.sourceYandex,
    MusicSource.soundcloud || MusicSource.ytmusic => label,
  };
}
