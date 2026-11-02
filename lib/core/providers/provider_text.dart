/// The words a provider writes itself when a platform leaves a name blank. The
/// app supplies them in the current language, so providers stay plain Dart and
/// the smoke tools run without Flutter.
library;

class ProviderText {
  const ProviderText({
    this.untitled = 'Untitled',
    this.unknownArtist = 'Unknown',
    this.album = 'Album',
    this.playlist = 'Playlist',
    this.artist = 'Artist',
    this.likesOf = _likesOf,
  });

  final String untitled;
  final String unknownArtist;
  final String album;
  final String playlist;
  final String artist;
  final String Function(String account) likesOf;
}

String _likesOf(String account) => 'Likes · $account';

/// Set by the app; returns `null` while no language is known yet.
ProviderText? Function()? providerTextSource;

ProviderText get providerText =>
    providerTextSource?.call() ?? const ProviderText();
