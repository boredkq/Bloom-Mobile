/// A platform's artist by name alone, where no exact id is available: history
/// keeps only the name (stats top), and on a multi-artist track only the
/// uploader has an id.
library;

import '../entities/entities.dart';
import 'music_provider.dart';

/// Finds an artist by name; `null` if the platform returned nothing. An exact
/// name beats the first hit: on SoundCloud, "Onda" easily brings someone's fan
/// account first.
Future<Artist?> findArtistByName(MusicProvider provider, String name) async {
  final key = name.trim().toLowerCase();
  if (key.isEmpty) return null;
  final found = await provider.searchArtists(name, limit: 3);
  for (final a in found) {
    if (a.name.toLowerCase() == key) return a;
  }
  return found.isEmpty ? null : found.first;
}

/// Who I've looked up this run: "platform|name" to the artist (null: looked,
/// not found).
final Map<String, Artist?> _memo = {};

/// [findArtistByName], but one artist is looked up once per run. The same names
/// get asked a lot: the artists sheet reopens and the player fetches avatars on
/// every track change.
///
/// Network failures don't land here: the exception goes up and a later try can
/// succeed. Only a clear platform answer is remembered, including "no such
/// artist".
Future<Artist?> findArtistCached(MusicProvider provider, String name) async {
  final key = '${provider.id}|${name.trim().toLowerCase()}';
  if (_memo.containsKey(key)) return _memo[key];
  final artist = await findArtistByName(provider, name);
  _memo[key] = artist;
  return artist;
}
