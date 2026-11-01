/// Home, top down: the wave on the whole first screen, then what's picked
/// for the listener ("for you", "similar to") ahead of what is the same for
/// everyone (releases and the chart). A shelf with nothing in it yet isn't
/// there at all.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/tokens.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_mark.dart';
import '../../../shared/ui/cover_hero.dart';
import '../../../shared/ui/pressable.dart';
import '../../profile/profile_store.dart';
import '../../profile/ui/profile_avatar.dart';
import '../../wave/ui/wave_hero.dart';
import '../discover_store.dart';
import 'for_you_section.dart';
import 'home_sections.dart';
import 'similar_to_section.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final bg = context.bloom.bg;
    return Stack(
      children: [
        // The wave's stage runs up under the status bar.
        ListView(
          controller: _scroll,
          padding: EdgeInsets.only(bottom: bottomBarsInset(context) + 16),
          children: [
            WaveHero(header: const _TopBar(), scroll: _scroll),
            const ForYouSection(),
            const SimilarToSection(),
            const DiscoverSection(mode: DiscoverMode.newReleases),
            const DiscoverSection(mode: DiscoverMode.charts),
          ],
        ),
        // The shelves below don't: a veil of the page's colour comes in as
        // they reach the status bar.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: top,
          child: IgnorePointer(
            child: ListenableBuilder(
              listenable: _scroll,
              builder: (context, _) {
                final hero =
                    MediaQuery.sizeOf(context).height -
                    bottomBarsInset(context);
                final off = _scroll.hasClients ? _scroll.offset : 0.0;
                final k = ((off - (hero - top - 80)) / 80).clamp(0.0, 1.0);
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
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          BloomMark(size: _kHeaderItem, color: context.bloom.text),
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
