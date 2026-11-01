/// The very first launch: a word of welcome over the app, then the app.
/// It melts away by itself or on a tap, and never comes back on this data.
library;

import 'package:flutter/material.dart';

import '../core/db/db.dart';
import '../core/l10n/l10n.dart';
import 'theme/bloom_theme.dart';
import 'theme/tokens.dart';

const String _seenKey = 'welcome.seen';

/// Whether this is the first launch on this data. I mark it seen right away:
/// a launch that dies mid-welcome doesn't get it again.
bool takeFirstRun(BloomDb db) {
  if (db.get(_seenKey) == true) return false;
  db.set(_seenKey, true);
  return true;
}

class Welcome extends StatefulWidget {
  const Welcome({super.key, required this.show, required this.child});

  final bool show;
  final Widget child;

  @override
  State<Welcome> createState() => _WelcomeState();
}

class _WelcomeState extends State<Welcome> with TickerProviderStateMixin {
  static const _ms = Duration(milliseconds: 600);
  static const _hold = Duration(milliseconds: 1600);

  late final AnimationController _word = AnimationController(
    vsync: this,
    duration: _ms,
  );
  late final AnimationController _cover = AnimationController(
    vsync: this,
    duration: _ms,
    value: 1,
  );
  late bool _on = widget.show;

  @override
  void initState() {
    super.initState();
    if (!_on) return;
    _word.forward().then((_) {
      if (mounted) Future.delayed(_hold, _leave);
    });
    _cover.addStatusListener((s) {
      if (s == AnimationStatus.dismissed && mounted) {
        setState(() => _on = false);
      }
    });
  }

  void _leave() {
    if (!mounted || _cover.status == AnimationStatus.reverse) return;
    _word.stop();
    _cover.reverse();
  }

  @override
  void dispose() {
    _word.dispose();
    _cover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The app stays the first child throughout, so dropping the cover
    // doesn't rebuild it.
    return Stack(children: [widget.child, if (_on) _coverOver(context)]);
  }

  Widget _coverOver(BuildContext context) {
    final t = context.bloom;
    final fade = CurvedAnimation(parent: _cover, curve: Curves.easeInOutQuad);
    final show = CurvedAnimation(parent: _word, curve: Curves.easeOutQuad);
    final rise = CurvedAnimation(parent: _word, curve: Curves.easeOutCubic);
    return Positioned.fill(
      child: FadeTransition(
        opacity: fade,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _leave,
          // Material gives the word the app's font; this sits above the
          // navigator's pages.
          child: Material(
            color: t.bg,
            child: Center(
              child: AnimatedBuilder(
                animation: _word,
                builder: (context, child) => Opacity(
                  opacity: show.value,
                  child: Transform.translate(
                    offset: Offset(0, 8 * (1 - rise.value)),
                    child: child,
                  ),
                ),
                child: Text(
                  context.l.welcomeTitle,
                  textAlign: TextAlign.center,
                  style: bloomText(
                    size: 40,
                    weight: 700,
                    color: t.text,
                    letterSpacing: -0.6,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
