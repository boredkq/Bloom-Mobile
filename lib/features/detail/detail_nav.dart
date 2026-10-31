/// Opening the artist's and the album's / playlist's pages.
///
/// They fade in place ([detailPageRoute]): the card's cover flies into the
/// header, and a slide of the whole page would fight it.
///
/// A plain push, not a `go_router` route: the pages nest (artist → album →
/// artist…), and a named route would be needed in every branch. From a tab
/// the nearest navigator is the branch's, so the bars stay put; from the
/// player it's the root, and I find the branch myself ([_target]).
library;

import 'package:flutter/material.dart';

import '../../app/router.dart';
import '../../core/entities/entities.dart';
import '../../core/providers/music_provider.dart';
import '../../shared/ui/cover_hero.dart';
import '../player/ui/player_sheet.dart';
import 'ui/artist_screen.dart';
import 'ui/set_screen.dart';

/// The navigator a page goes into. Usually the tab's. From the full player the
/// nearest one is the root, and a page there would cover the bars: so the
/// player closes, with the sheets over it, and the page goes to the current
/// tab. Only when there's something over the shell and the tab is built;
/// otherwise the root is the only one (a test). The player is a layer, not a
/// route, so `canPop` alone wouldn't see it.
NavigatorState _target(BuildContext context) {
  final navigator = Navigator.of(context);
  final root = Navigator.of(context, rootNavigator: true);
  if (navigator != root) return navigator;
  final player = playerSheetOpen.value;
  if (!player && !navigator.canPop()) return navigator;
  final branch = currentBranchNavigator();
  if (branch == null) return navigator;
  navigator.popUntil((r) => r.isFirst);
  collapsePlayerSheet();
  return branch;
}

/// An artist's page. [initial] shows in the header before the network
/// answers; [flight] is the card's avatar flying into it.
Future<void> openArtist(
  BuildContext context,
  String artistId, {
  Artist? initial,
  CoverFlight? flight,
}) =>
    openArtistIn(_target(context), artistId, initial: initial, flight: flight);

/// A platform's album or playlist (the library's own open by their route).
Future<void> openSet(
  BuildContext context,
  Playlist set, {
  CoverFlight? flight,
}) => openSetIn(_target(context), set, flight: flight);

/// The same into a given navigator: the player's source pill has no tab of
/// its own.
Future<void> openArtistIn(
  NavigatorState navigator,
  String artistId, {
  Artist? initial,
  CoverFlight? flight,
}) => navigator.push(
  detailPageRoute<void>(
    (_) => ArtistScreen(artistId: artistId, initial: initial, flight: flight),
  ),
);

/// All of an artist's tracks, with what their page had loaded.
Future<void> openArtistTracks(BuildContext context, ArtistPageData data) =>
    _target(context).push(
      detailPageRoute<void>(
        (_) => ArtistScreen(
          artistId: data.artist.id,
          initial: data.artist,
          seed: data,
        ),
      ),
    );

Future<void> openSetIn(
  NavigatorState navigator,
  Playlist set, {
  CoverFlight? flight,
}) => navigator.push(
  detailPageRoute<void>((_) => SetScreen(set: set, flight: flight)),
);
