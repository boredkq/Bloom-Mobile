/// What search holds between openings: the query, the results and the tab. The
/// layer on screen comes and goes ([SearchLayer]), and this stays until the app
/// closes, so search opens again where it was left.
///
/// It knows nothing of platforms: it asks [ProviderRegistry.searchAll] and keeps
/// neutral entities. Tabs split results ALREADY received, with no network trip:
/// a provider gives all sections in one run.
///
/// Links get pasted here too: a string that looks like a link goes to
/// `resolveUrlAny` instead of search, and a track, playlist or album becomes
/// one result card; an artist's or a listener's link opens their page at once.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/entities/entities.dart';
import '../../core/l10n/l10n.dart';
import '../../core/providers/music_provider.dart';
import '../../core/providers/registry.dart';

/// Whether a string looks like a link. Domains get caught with no protocol too,
/// since that's how they get pasted. The exact parsing is the platform's; this
/// only picks the branch.
bool looksLikeUrl(String query) =>
    RegExp(r'^https?://', caseSensitive: false).hasMatch(query) ||
    RegExp(
      r'(^|\.)(soundcloud\.com|snd\.sc|music\.yandex\.[a-z]+|music\.youtube\.com|youtu\.be)/',
      caseSensitive: false,
    ).hasMatch(query);

/// A resolved link as results of one card.
SearchResults _resolvedToResults(ResolvedUrl resolved) => switch (resolved) {
  ResolvedTrack(:final track) => SearchResults(tracks: [track]),
  ResolvedArtist(:final artist) => SearchResults(artists: [artist]),
  ResolvedSet(:final playlist) =>
    playlist.isAlbum
        ? SearchResults(albums: [playlist])
        : SearchResults(playlists: [playlist]),
};

enum SearchTab {
  all,
  tracks,
  artists,
  albums,
  playlists;

  String label(AppLocalizations l) => switch (this) {
    SearchTab.all => l.searchTabAll,
    SearchTab.tracks => l.commonTracks,
    SearchTab.artists => l.commonArtists,
    SearchTab.albums => l.commonAlbums,
    SearchTab.playlists => l.commonPlaylists,
  };

  /// How many of this kind the results hold; "all" counts as one.
  int countIn(SearchResults r) => switch (this) {
    SearchTab.all => 1,
    SearchTab.tracks => r.tracks.length,
    SearchTab.artists => r.artists.length,
    SearchTab.albums => r.albums.length,
    SearchTab.playlists => r.playlists.length,
  };
}

class SearchSession extends ChangeNotifier {
  SearchSession(this._ref);

  final Ref _ref;

  final TextEditingController controller = TextEditingController();

  SearchTab _tab = SearchTab.all;
  SearchResults _results = SearchResults.empty;
  bool _loading = false;
  String? _error;

  /// Whether there's been a run, telling not searched yet from found nothing:
  /// the registry turns provider errors into empty results, and with no flag a
  /// failed search looks like an untouched screen.
  bool _searched = false;

  /// Query number: an answer to a stale search mustn't override a fresh one.
  int _generation = 0;

  /// Query the RESULTS stand for, not the field's text: that's being edited for
  /// the next search, and the queue comes from what's on screen.
  String _lastQuery = '';

  SearchResults get results => _results;
  bool get loading => _loading;
  String? get error => _error;
  bool get searched => _searched;
  String get lastQuery => _lastQuery;

  /// Whether there's anything to put on the screen. Until then only the field
  /// shows, over the page.
  bool get showing => _loading || _searched || _error != null;

  /// A kind without results is a dim tab; while a search loads they all stay
  /// lit.
  bool has(SearchTab tab) => _loading || tab.countIn(_results) > 0;

  /// A tab the new results left empty falls back to "all".
  SearchTab get activeTab => has(_tab) ? _tab : SearchTab.all;

  void pick(SearchTab tab) {
    _tab = tab;
    notifyListeners();
  }

  /// Runs what the field holds. Gives back the artist a pasted link leads to:
  /// their page is the caller's to open.
  Future<Artist?> run() async {
    final query = controller.text.trim();
    if (query.isEmpty) return null;
    final gen = ++_generation;
    _lastQuery = query;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      // A link resolves first. If unparsed (a platform not connected, a typo)
      // it silently falls to ordinary search: the string was typed in a search
      // field, and results beat an empty error screen.
      if (looksLikeUrl(query)) {
        final found = await _ref.read(registryProvider).resolveUrlAny(query);
        if (gen != _generation) return null;
        if (found != null) {
          _finish(_resolvedToResults(found.resolved));
          return switch (found.resolved) {
            ResolvedArtist(:final artist) => artist,
            _ => null,
          };
        }
      }

      final results = await _ref
          .read(registryProvider)
          .searchAll(query, providerId: _ref.read(activeProviderIdProvider));
      if (gen == _generation) _finish(results);
    } catch (e) {
      if (gen == _generation) {
        _error = e.toString();
        _loading = false;
        notifyListeners();
      }
    }
    return null;
  }

  void _finish(SearchResults results) {
    _results = results;
    _loading = false;
    _searched = true;
    notifyListeners();
  }

  /// Drops the results. A search still running is left unanswered: its results
  /// would come back to an empty field.
  void clear() {
    _generation++;
    _results = SearchResults.empty;
    _loading = false;
    _error = null;
    _searched = false;
    notifyListeners();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}

final searchSessionProvider = Provider<SearchSession>((ref) {
  final session = SearchSession(ref);
  ref.onDispose(session.dispose);
  return session;
});
