/// Home, top down: the wave on a screen of its own, then a magnet, then the
/// shelves: what's picked for the listener ("for you", "similar to") ahead of
/// what is the same for everyone (releases and the chart). A shelf with nothing
/// in it yet isn't there at all. One header stands over both screens.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/tokens.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_mark.dart';
import '../../../shared/ui/cover_hero.dart';
import '../../../shared/ui/pressable.dart';
import '../../player/ui/mini_player.dart';
import '../../profile/profile_store.dart';
import '../../profile/ui/profile_avatar.dart';
import '../../wave/ui/wave_hero.dart';
import '../discover_store.dart';
import 'for_you_section.dart';
import 'home_sections.dart';
import 'magnet_scroll.dart';
import 'similar_to_section.dart';

/// The mini player is back by this share of the way to the shelves.
const double _cardBackAt = 0.35;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ScrollController _scroll = ScrollController();
  final MagnetStop _stop = MagnetStop();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    final off = _scroll.offset;
    _stop.settle(off);
    waveHoldsCard.value = (1 - off / (_stop.at * _cardBackAt)).clamp(0.0, 1.0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The panel listening to this is mid-build too.
    final top = ModalRoute.isCurrentOf(context) ?? true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      homeOnTop.value = top;
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context).height;
    final top = MediaQuery.paddingOf(context).top;
    final bottom = bottomBarsInset(context);
    final bg = context.bloom.bg;
    _stop.at = screen;
    return Stack(
      children: [
        // The wave's stage runs up under the status bar.
        CustomScrollView(
          controller: _scroll,
          physics: MagnetScrollPhysics(_stop),
          slivers: [
            SliverToBoxAdapter(child: WaveHero(scroll: _scroll)),
            // At least a screen tall: with few shelves the magnet still has
            // somewhere to land.
            SliverToBoxAdapter(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: screen),
                child: Padding(
                  padding: EdgeInsets.only(
                    top: top + kHomeHeaderHeight,
                    bottom: bottom + 16,
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ForYouSection(),
                      SimilarToSection(),
                      DiscoverSection(mode: DiscoverMode.newReleases),
                      DiscoverSection(mode: DiscoverMode.charts),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        // It stands still while the screens swap and leaves with the shelves.
        Positioned(
          top: top,
          left: 0,
          right: 0,
          height: kHomeHeaderHeight,
          child: ListenableBuilder(
            listenable: _scroll,
            builder: (context, child) {
              final off = _scroll.hasClients ? _scroll.offset : 0.0;
              return Transform.translate(
                offset: Offset(0, math.min(0, _stop.at - off)),
                child: child,
              );
            },
            child: const _TopBar(),
          ),
        ),
        // The shelves don't: a veil of the page's colour comes in as they
        // reach the status bar.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: top,
          child: IgnorePointer(
            child: ListenableBuilder(
              listenable: _scroll,
              builder: (context, _) {
                final off = _scroll.hasClients ? _scroll.offset : 0.0;
                final k = ((off - (_stop.at - top - 80)) / 80).clamp(0.0, 1.0);
                return ColoredBox(color: bg.withValues(alpha: k));
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// The header's logo and avatar, one size for both.
const double _kHeaderItem = 40;

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // A swipe starting on the logo still scrolls what's under it.
          IgnorePointer(
            child: BloomMark(size: _kHeaderItem, color: context.bloom.text),
          ),
          const Spacer(),
          const _ProfileButton(),
        ],
      ),
    );
  }
}

/// Way into the profile: the avatar itself, flying from here into the page's
/// header. The flight tag is an instance's [UniqueKey] rather than a shared
/// string: two cards with one tag in a tree throw when the transition starts.
class _ProfileButton extends ConsumerStatefulWidget {
  const _ProfileButton();

  @override
  ConsumerState<_ProfileButton> createState() => _ProfileButtonState();
}

class _ProfileButtonState extends ConsumerState<_ProfileButton> {
  late final Object _tag = UniqueKey();

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    return Pressable(
      onTap: () => context.go(kProfileLocation, extra: CoverFlight(tag: _tag)),
      child: ProfileAvatar(
        profile: profile,
        size: _kHeaderItem,
        flightTag: _tag,
      ),
    );
  }
}
