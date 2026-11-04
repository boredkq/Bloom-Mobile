/// Navigation: one [StatefulShellRoute] branch per tab, each with its own
/// stack, so a tab keeps its state across switches.
///
/// The branch container is my own ([BranchCrossfade]): the stock
/// `indexedStack` swaps tabs in one frame.
///
/// Nested pages live inside their branch, so the tab bar and the mini player
/// stay in place.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/store/settings_store.dart';
import '../features/customization/ui/app_background.dart';
import '../features/customization/ui/customization_screen.dart';
import '../features/home/ui/home_screen.dart';
import '../features/library/ui/library_screen.dart';
import '../features/library/ui/tracklist_screen.dart';
import '../features/profile/ui/profile_edit_screen.dart';
import '../features/pc/ui/pc_screen.dart';
import '../features/profile/ui/profile_screen.dart';
import '../features/settings/ui/appearance_screen.dart';
import '../features/settings/ui/audio_screen.dart';
import '../features/settings/ui/lastfm_screen.dart';
import '../features/settings/ui/logs_screen.dart';
import '../features/settings/ui/mini_player_screen.dart';
import '../features/settings/ui/player_screen.dart';
import '../features/settings/ui/settings_screen.dart';
import '../features/settings/ui/soundcloud_screen.dart';
import '../features/settings/ui/storage_screen.dart';
import '../features/settings/ui/system_screen.dart';
import '../features/settings/ui/swipes_screen.dart';
import '../features/settings/ui/version_screen.dart';
import '../features/settings/ui/yandex_screen.dart';
import '../features/settings/ui/ytmusic_screen.dart';
import '../shared/ui/cover_hero.dart';
import '../shared/ui/glass.dart';
import 'shell.dart';
import 'theme/tokens.dart';

final GlobalKey<NavigatorState> _rootKey = GlobalKey<NavigatorState>();

/// Tab navigators.
///
/// Pages opened from outside a tab's tree need them: the full player lives in
/// the root navigator, and an artist page pushed there would cover the tab bar
/// and the mini player.
final Map<NavTab, GlobalKey<NavigatorState>> _branchKeys = {
  for (final tab in kBranchTabs) tab: GlobalKey<NavigatorState>(),
};

/// The navigator of the open tab. `null` until the shell is built.
NavigatorState? currentBranchNavigator() {
  final path = bloomRouter.state.uri.path;
  final tab = kBranchTabs.firstWhere(
    (tab) => path.startsWith('/${tab.name}'),
    orElse: () => NavTab.home,
  );
  return _branchKeys[tab]!.currentState;
}

/// The profile page: it lives inside home, opened from the header avatar.
const String kProfileLocation = '/home/profile';

/// Route page background. Branch screens have no fill of their own, the shell's
/// [Scaffold] gives it. During a transition both pages show, and a fill-less
/// top page lets the library show through a playlist, so each page paints
/// itself.
///
/// With a background picture on there's no fill, or it would be covered.
/// Show-through doesn't matter then: the same picture lies under both pages.
class _Page extends ConsumerWidget {
  const _Page(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ColoredBox(
    color: ref.watch(backgroundOnProvider)
        ? Colors.transparent
        : context.bloom.bg,
    // One glass group per page: its plates don't overlap, so one backdrop
    // snapshot serves them all. The shell's bars lie above the page and have
    // their own.
    child: GlassGroup(child: child),
  );
}

/// A fade in place instead of the shared slide: the avatar flies from the home
/// button into the profile header, and sliding the page would fight it (see
/// `detailPageTransition`).
CustomTransitionPage<void> _profilePage(GoRouterState state) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      transitionsBuilder: detailPageTransition,
      transitionDuration: kDetailTransition,
      reverseTransitionDuration: kDetailTransition,
      child: _Page(
        ProfileScreen(
          flight: state.extra is CoverFlight
              ? state.extra! as CoverFlight
              : null,
        ),
      ),
    );

/// The profile editor goes above the shell: no tab bar or mini player under
/// Save.
GoRoute get _profileEditRoute => GoRoute(
  path: 'edit',
  parentNavigatorKey: _rootKey,
  builder: (_, _) => const _Page(ProfileEditScreen()),
);

final GoRouter bloomRouter = GoRouter(
  navigatorKey: _rootKey,
  initialLocation: '/home',
  routes: [
    StatefulShellRoute(
      builder: (context, state, shell) =>
          BloomShell(shell: shell, location: state.uri.path),
      navigatorContainerBuilder: (context, shell, children) =>
          BranchCrossfade(index: shell.currentIndex, children: children),
      branches: [
        StatefulShellBranch(
          navigatorKey: _branchKeys[NavTab.home],
          routes: [
            GoRoute(
              path: '/home',
              builder: (_, _) => const _Page(HomeScreen()),
              routes: [
                GoRoute(
                  path: 'profile',
                  pageBuilder: (_, state) => _profilePage(state),
                  routes: [_profileEditRoute],
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _branchKeys[NavTab.library],
          routes: [
            GoRoute(
              path: '/library',
              builder: (_, _) => const _Page(LibraryScreen()),
              routes: [
                GoRoute(
                  path: 'list/:id',
                  // A fade in place instead of the shared slide: the tile's
                  // cover flies into the list header, and sliding the page
                  // would fight it (see `detailPageTransition`).
                  //
                  // `extra` is that flight's tag. Only a tile sends it; from a
                  // link or after a restart it's empty and the header just
                  // fades in.
                  pageBuilder: (_, state) => CustomTransitionPage<void>(
                    key: state.pageKey,
                    transitionsBuilder: detailPageTransition,
                    transitionDuration: kDetailTransition,
                    reverseTransitionDuration: kDetailTransition,
                    child: _Page(
                      TracklistScreen(
                        listId: state.pathParameters['id']!,
                        flight: state.extra is CoverFlight
                            ? state.extra! as CoverFlight
                            : null,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _branchKeys[NavTab.settings],
          routes: [
            GoRoute(
              path: '/settings',
              builder: (_, _) => const _Page(SettingsScreen()),
              routes: [
                GoRoute(
                  path: 'appearance',
                  builder: (_, _) => const _Page(AppearanceScreen()),
                ),
                GoRoute(
                  path: 'soundcloud',
                  builder: (_, _) => const _Page(SoundCloudSettingsScreen()),
                ),
                GoRoute(
                  path: 'yandex',
                  builder: (_, _) => const _Page(YandexSettingsScreen()),
                ),
                GoRoute(
                  path: 'ytmusic',
                  builder: (_, _) => const _Page(YtmusicSettingsScreen()),
                ),
                GoRoute(
                  path: 'lastfm',
                  builder: (_, _) => const _Page(LastfmSettingsScreen()),
                ),
                GoRoute(
                  path: 'pc',
                  builder: (_, _) => const _Page(PcSettingsScreen()),
                  routes: [
                    // Full-screen camera, above the shell's bars.
                    GoRoute(
                      path: 'scan',
                      parentNavigatorKey: _rootKey,
                      builder: (_, _) => const PcScanScreen(),
                    ),
                  ],
                ),
                GoRoute(
                  path: 'system',
                  builder: (_, _) => const _Page(SystemSettingsScreen()),
                  routes: [
                    GoRoute(
                      path: 'logs',
                      builder: (_, _) => const _Page(LogsScreen()),
                    ),
                  ],
                ),
                GoRoute(
                  path: 'audio',
                  builder: (_, _) => const _Page(AudioSettingsScreen()),
                ),
                GoRoute(
                  path: 'storage',
                  builder: (_, _) => const _Page(StorageSettingsScreen()),
                ),
                GoRoute(
                  path: 'swipes',
                  builder: (_, _) => const _Page(SwipesScreen()),
                ),
                GoRoute(
                  path: 'player',
                  builder: (_, _) => const _Page(PlayerSettingsScreen()),
                ),
                GoRoute(
                  path: 'miniplayer',
                  builder: (_, _) => const _Page(MiniPlayerSettingsScreen()),
                ),
                GoRoute(
                  path: 'version',
                  builder: (_, _) => const _Page(VersionScreen()),
                ),
                GoRoute(
                  path: 'customization',
                  builder: (_, _) => const _Page(CustomizationScreen()),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);
