/// A track's artists: their names and the pages behind them.
library;

import '../../core/entities/entities.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/yandex/models.dart' show kYmUnknownArtist;

/// The track's artists with their pages, where known. One rule for every place
/// that opens an artist or shows their avatars.
List<ArtistLink> artistLinks(Track t) {
  // Tags edited by hand: the ids may be someone else's now.
  final own = !t.edited && t.source != MusicSource.local;
  // The platform's own list, while the line still says what it does.
  if (own &&
      t.artists.isNotEmpty &&
      t.artists.map((a) => a.name).join(', ') == t.artist) {
    return t.artists;
  }
  final id = own ? t.artistId : null;
  final names = parseArtists(t.artist);
  // A SoundCloud line is one account, whatever its name has in it
  // ("Simon & Garfunkel").
  if (t.source == MusicSource.soundcloud && id != null && names.isNotEmpty) {
    return [(name: t.artist.trim(), id: id)];
  }
  return [for (final n in names) (name: n, id: names.length == 1 ? id : null)];
}

/// The first of them, or an empty name.
ArtistLink firstArtistLink(Track t) =>
    artistLinks(t).firstOrNull ?? (name: '', id: null);

/// The avatar the track brings along: only its one artist's, never a guess.
String? ownArtistAvatar(Track t) {
  final own = t.artistAvatar;
  if (own == null || own.isEmpty || t.edited) return null;
  return artistLinks(t).length == 1 ? own : null;
}

/// "Unknown artist" in every language and the platforms' own stand-in: not a
/// name. Every language, as the line is written into the track at import.
final Set<String> _unknown = {
  for (final locale in AppLocalizations.supportedLocales)
    lookupAppLocalizations(locale).commonUnknownArtist,
  kYmUnknownArtist,
};

/// `,` `&` `×` and feat./ft./vs. Not "and", "x", "и": they are part of too many
/// names ("Florence and the Machine", "Mr. X").
///
/// Symbols split anywhere, words only between spaces: else "Andrew" and
/// "Sandvs" would fall apart mid-name.
final RegExp _sep = RegExp(
  r'\s*[,&×]\s*|\s+(?:feat\.?|ft\.?|vs\.?)\s+',
  caseSensitive: false,
);

/// "Artist A, Artist B feat. Artist C" → `[Artist A, Artist B, Artist C]`.
///
/// A line with no separators comes back whole, so its length tells one artist
/// from several. No name, or the unknown stand-in: empty.
List<String> parseArtists(String? s) {
  final str = s?.trim() ?? '';
  if (str.isEmpty || _unknown.contains(str)) return const [];
  final parts = [
    for (final p in str.split(_sep))
      if (p.trim().isNotEmpty) p.trim(),
  ];
  // A name of nothing but separators ("&") is the artist, however odd.
  return parts.isEmpty ? [str] : parts;
}
