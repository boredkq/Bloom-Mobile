/// Bottom sheets: one floating frame for all of them, and the look of the menus
/// about a track, list or artist — the cover as a banner, a capsule of icons,
/// flat rows.
///
/// A sheet goes through the root navigator, so it covers the tab bar and the
/// mini player too; otherwise they would stay above the dimming.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/bloom_theme.dart';
import '../../app/theme/tokens.dart';
import '../../core/l10n/l10n.dart';
import '../../core/store/cover_store.dart';
import '../../features/settings/transparency_store.dart';
import '../util/format.dart';
import 'atoms.dart';
import 'bloom_icon.dart';
import 'glass.dart';
import 'pressable.dart';

/// An item of a sheet: a row, or an icon in the capsule.
class SheetAction {
  const SheetAction({
    required this.icon,
    required this.label,
    this.subtitle,
    this.onTap,
    this.next = false,
    this.danger = false,
    this.trailing,
  });

  final BloomGlyph icon;
  final String label;

  /// Grey line under the label. The capsule shows only the icon.
  final String? subtitle;

  /// The sheet closes BEFORE the call, unless the item is [next].
  final VoidCallback? onTap;

  /// [onTap] opens another sheet: it takes this one's place, with a Back row.
  final bool next;

  /// Red: removes something.
  final bool danger;

  /// A mark on the right, like the tick of the active choice.
  final Widget? trailing;
}

/// The menu of a track, list or artist: the banner, [bar] in the capsule, [groups]
/// as flat rows below it. Empty groups drop out.
Future<void> showBloomSheet({
  required BuildContext context,
  required SheetHero header,
  List<SheetAction> bar = const [],
  required List<List<SheetAction>> groups,
}) {
  return showBloomSheetChild<void>(
    context: context,
    header: header,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (bar.isNotEmpty) _ActionBar(actions: bar),
        for (final group in groups)
          if (group.isNotEmpty) _SheetGroup(actions: group),
      ],
    ),
  );
}

/// The same sheet with any content. Returns what it was closed with
/// (`Navigator.pop`).
Future<T?> showBloomSheetChild<T>({
  required BuildContext context,
  Widget? header,
  Widget? footer,
  double maxFraction = _kSheetMaxFraction,
  bool scrolls = true,
  required Widget child,
}) {
  return showBloomModal<T>(
    context: context,
    builder: (_) => SheetShell(
      header: header,
      footer: footer,
      maxFraction: maxFraction,
      scrolls: scrolls,
      child: child,
    ),
  );
}

/// How tall a sheet may grow, as a share of the screen.
const double _kSheetMaxFraction = 0.85;

/// Corner of the floating sheet, all four.
const double kSheetRadius = 28;

/// Inset of a sheet's content from its edges; headers, plates and fields stand
/// on it.
const double kSheetEdge = 20;

/// Inset of a menu's flat rows from the sheet's edge. A row adds its own 16, so
/// icons stand at 24.
const double _kFlatEdge = 8;

/// Height of a sheet's row, with a grey line or without.
const double _kRowHeight = 56;

/// How long a sheet takes to swap its content for what continues it.
const Duration _kSheetSwap = Duration(milliseconds: 280);

/// Opens a sheet: the one way in for all of them, those with a shell of their
/// own too (queue, speed, colour picker).
///
/// With "Overlay transparency" on, the page under the sheet is also blurred and
/// the dimming lighter (0.5 → 0.28): under a dark film the blur wouldn't show.
Future<T?> showBloomModal<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  // Called from [openNextSheet]: the open sheet shows this one instead.
  if (_nextInto case final chain?) {
    _nextInto = null;
    return chain.push<T>(builder);
  }

  final navigator = Navigator.of(context, rootNavigator: true);
  final glass = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(overlayGlassProvider);
  final first = _SheetPage<T>(builder);
  final chain = _SheetChain(first);
  // The route's own type is loose: a page further along closes the whole sheet
  // with a result of its own type.
  final closed = navigator.push<Object?>(
    _BloomSheetRoute<Object?>(
      builder: (_) => _FloatingFrame(child: _SheetStack(chain: chain)),
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      modalBarrierColor: Colors.black.withValues(
        alpha: glass == null ? 0.5 : 0.28,
      ),
    ),
  );
  unawaited(closed.then(chain.close));
  return first.result.future;
}

/// Where the next [showBloomModal] goes; set only while [openNextSheet] runs.
_SheetChain? _nextInto;

/// Runs [open], which opens a sheet: the sheet of [context] stays and shows it,
/// with a Back row. If [open] decided not to open one, this sheet just closes.
void openNextSheet(BuildContext context, VoidCallback open) {
  _nextInto = context.getInheritedWidgetOfExactType<_SheetStackScope>()?.chain;
  open();
  final opened = _nextInto == null;
  _nextInto = null;
  if (!opened) Navigator.of(context).pop();
}

/// One screen of a sheet.
class _SheetPage<T> {
  _SheetPage(this.builder);

  final WidgetBuilder builder;
  final Completer<T?> result = Completer<T?>();
  final Key key = UniqueKey();

  void finish(Object? value) {
    if (result.isCompleted) return;
    result.complete(value is T ? value : null);
  }
}

/// The screens of one sheet: the last is on show, the rest wait to come back.
class _SheetChain extends ChangeNotifier {
  _SheetChain(_SheetPage<dynamic> first) : pages = [first];

  final List<_SheetPage<dynamic>> pages;
  bool _closed = false;

  Future<T?> push<T>(WidgetBuilder builder) {
    final page = _SheetPage<T>(builder);
    pages.add(page);
    notifyListeners();
    return page.result.future;
  }

  void back() {
    if (_closed || pages.length < 2) return;
    pages.removeLast().finish(null);
    notifyListeners();
  }

  /// The sheet closed whole: what was picked belongs to the page on show. The
  /// pages stay as they are, the sheet still has to slide away.
  void close(Object? value) {
    _closed = true;
    pages.last.finish(value);
    for (final page in pages) {
      page.finish(null);
    }
  }
}

/// A page's place in its chain.
class _SheetStackScope extends InheritedWidget {
  const _SheetStackScope({
    required this.chain,
    required this.depth,
    required this.ownSurface,
    required super.child,
  });

  final _SheetChain chain;

  /// 0 for the first page, which has nothing to go back to.
  final int depth;

  /// False: one surface stands behind all the pages, so a page paints none.
  final bool ownSurface;

  static _SheetStackScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SheetStackScope>();

  @override
  bool updateShouldNotify(_SheetStackScope old) =>
      old.depth != depth || old.ownSurface != ownSurface;
}

/// Shows a chain's last page. The swap: the old content slides and fades out,
/// the new one in, the sheet's height following.
class _SheetStack extends StatefulWidget {
  const _SheetStack({required this.chain});

  final _SheetChain chain;

  @override
  State<_SheetStack> createState() => _SheetStackState();
}

class _SheetStackState extends State<_SheetStack>
    with SingleTickerProviderStateMixin {
  /// How far the content travels, as a share of the sheet's width.
  static const double _travel = 0.2;

  late final AnimationController _swap = AnimationController(
    vsync: this,
    duration: _kSheetSwap,
    value: 1,
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _swap,
    curve: Curves.easeOutCubic,
  );

  late _SheetPage<dynamic> _top = widget.chain.pages.last;
  late List<_SheetPage<dynamic>> _shown = [...widget.chain.pages];
  _SheetPage<dynamic>? _leaving;
  bool _forward = true;

  @override
  void initState() {
    super.initState();
    widget.chain.addListener(_chainChanged);
    _swap.addStatusListener((status) {
      if (status != AnimationStatus.completed || !mounted) return;
      setState(() {
        _leaving = null;
        _shown = [...widget.chain.pages];
      });
    });
  }

  @override
  void dispose() {
    widget.chain.removeListener(_chainChanged);
    _curve.dispose();
    _swap.dispose();
    super.dispose();
  }

  void _chainChanged() {
    final pages = widget.chain.pages;
    final before = _top;
    setState(() {
      _top = pages.last;
      _forward = pages.contains(before);
      _leaving = before;
      _shown = [...pages, if (!_forward) before];
    });
    _swap.forward(from: 0);
  }

  Widget _slot(_SheetPage<dynamic> page, bool ownSurface) {
    final onShow = page == _top;
    final visible = onShow || page == _leaving;
    return _SheetSlot(
      key: page.key,
      sizes: onShow,
      child: Offstage(
        offstage: !visible,
        child: TickerMode(
          enabled: visible,
          child: AnimatedBuilder(
            animation: _curve,
            builder: (_, child) {
              final way = (_forward ? 1 : -1) * _travel;
              final v = _curve.value;
              final (shift, opacity) = switch ((onShow, _leaving == null)) {
                (_, true) => (0.0, 1.0),
                (true, false) => (way * (1 - v), v),
                (false, false) => (-way * v, 1 - v),
              };
              return FractionalTranslation(
                translation: Offset(shift, 0),
                child: Opacity(opacity: opacity, child: child),
              );
            },
            child: _SheetStackScope(
              chain: widget.chain,
              // A leaving page isn't in the chain any more but keeps its row.
              depth: _shown.indexOf(page),
              ownSurface: ownSurface,
              child: _SheetPageFocus(
                active: onShow,
                child: Builder(builder: page.builder),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final moving = _leaving != null;
    final nested = widget.chain.pages.length > 1;
    final shared = nested || moving;
    return PopScope(
      canPop: !nested,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.chain.back();
      },
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          if (shared)
            const Positioned.fill(
              child: SheetSurface(child: SizedBox.expand()),
            ),
          AnimatedBuilder(
            animation: _curve,
            builder: (_, child) =>
                _SheetHeight(progress: _curve.value, child: child),
            child: Stack(
              fit: StackFit.passthrough,
              alignment: Alignment.topCenter,
              children: [for (final page in _shown) _slot(page, !shared)],
            ),
          ),
        ],
      ),
    );
  }
}

/// Takes a sheet's height from the old page's to the new one's during a swap.
/// At rest it's just the page's height: content that changes inside a page is
/// not to be animated.
class _SheetHeight extends SingleChildRenderObjectWidget {
  const _SheetHeight({required this.progress, super.child});

  final double progress;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSheetHeight(progress);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSheetHeight renderObject,
  ) {
    renderObject.progress = progress;
  }
}

class _RenderSheetHeight extends RenderProxyBox {
  _RenderSheetHeight(this._progress);

  double _progress;
  double? _from;
  final LayerHandle<ClipRectLayer> _clip = LayerHandle<ClipRectLayer>();

  set progress(double value) {
    if (value == _progress) return;
    // A swap starts, or starts over: from the height there is right now.
    if (value < _progress && hasSize) _from = size.height;
    _progress = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    child!.layout(constraints, parentUsesSize: true);
    final page = child!.size;
    final from = _from;
    size = _progress >= 1 || from == null
        ? page
        : constraints.constrain(
            Size(page.width, from + (page.height - from) * _progress),
          );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child!.size.height <= size.height) {
      _clip.layer = null;
      return super.paint(context, offset);
    }
    _clip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      super.paint,
      oldLayer: _clip.layer,
    );
  }

  @override
  void dispose() {
    _clip.layer = null;
    super.dispose();
  }
}

/// A page's own focus. Without it a field's autofocus finds focus taken by the
/// page underneath, and typing goes there. The page on show takes focus; coming
/// back, its field gets it again.
class _SheetPageFocus extends StatefulWidget {
  const _SheetPageFocus({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_SheetPageFocus> createState() => _SheetPageFocusState();
}

class _SheetPageFocusState extends State<_SheetPageFocus> {
  final FocusScopeNode _node = FocusScopeNode(debugLabel: 'sheet page');

  void _takeFocus() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && widget.active) _node.requestFocus();
  });

  @override
  void initState() {
    super.initState();
    _takeFocus();
  }

  @override
  void didUpdateWidget(_SheetPageFocus old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _takeFocus();
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FocusScope(node: _node, child: widget.child);
}

/// A page in the stack. Only the page on show gives the stack its height; the
/// others are laid out too and keep their state, at no height of their own.
class _SheetSlot extends SingleChildRenderObjectWidget {
  const _SheetSlot({super.key, required this.sizes, required super.child});

  final bool sizes;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSheetSlot(sizes);

  @override
  void updateRenderObject(BuildContext context, _RenderSheetSlot renderObject) {
    renderObject.sizes = sizes;
  }
}

class _RenderSheetSlot extends RenderProxyBox {
  _RenderSheetSlot(this._sizes);

  bool _sizes;

  set sizes(bool value) {
    if (value == _sizes) return;
    _sizes = value;
    markNeedsLayout();
  }

  // The sheet's width comes loose. Every page takes all of it, or one at no size
  // would stand in the middle of the stack.
  BoxConstraints _full(BoxConstraints c) => c.tighten(width: c.maxWidth);

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final full = _full(constraints);
    return _sizes ? child!.getDryLayout(full) : full.smallest;
  }

  @override
  void performLayout() {
    final full = _full(constraints);
    child!.layout(full, parentUsesSize: _sizes);
    size = _sizes ? child!.size : full.smallest;
  }
}

/// A sheet whose dimming can be glass. The sheet route doesn't pass a barrier
/// filter on, so I replace the barrier itself; a `Consumer`, because the blur
/// slider lives in a sheet and its own dimming must follow the finger.
///
/// A tap outside closes the whole sheet. The stock barrier asks to pop politely,
/// and a sheet with somewhere to go back to would only go back.
class _BloomSheetRoute<T> extends ModalBottomSheetRoute<T> {
  _BloomSheetRoute({
    required super.builder,
    required super.isScrollControlled,
    super.capturedThemes,
    super.backgroundColor,
    super.modalBarrierColor,
  });

  @override
  Widget buildModalBarrier() {
    final barrier = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => navigator?.pop(),
      child: IgnorePointer(child: super.buildModalBarrier()),
    );
    return Consumer(
      builder: (context, ref, _) {
        final filter = ref.watch(overlayGlassProvider)?.filter;
        if (filter == null) return barrier;
        return BackdropFilter(filter: filter, child: barrier);
      },
    );
  }
}

/// Holds a sheet off the screen's left, right and bottom edges, every corner
/// round. Below it the sheet sees its own width, and a screen without the
/// keyboard: both are dealt with here.
class _FloatingFrame extends StatelessWidget {
  const _FloatingFrame({required this.child});

  final Widget child;

  /// Above this the bottom inset is a row of system buttons, and the sheet
  /// stands over them. A gesture strip is lower: it lies over the sheet, whose
  /// content steps clear of it.
  static const double _gestureStrip = 40;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final gap = (media.size.width * 0.032).clamp(10.0, 20.0);
    final keyboard = media.viewInsets.bottom;
    final inset = media.padding.bottom;
    final overButtons = inset > _gestureStrip;
    final inner = overButtons ? 0.0 : math.max(0.0, inset - gap);

    return MediaQuery(
      data: media.copyWith(
        size: Size(media.size.width - gap * 2, media.size.height - keyboard),
        viewInsets: media.viewInsets.copyWith(bottom: 0),
        padding: media.padding.copyWith(bottom: inner),
        viewPadding: media.viewPadding.copyWith(bottom: inner),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          gap,
          0,
          gap,
          keyboard + (overButtons ? inset : gap),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(kSheetRadius),
          child: child,
        ),
      ),
    );
  }
}

/// A sheet's surface: the theme's plain background, or with overlay glass on a
/// translucent one over a blur of what's underneath.
class SheetSurface extends ConsumerWidget {
  const SheetSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final glass = ref.watch(overlayGlassProvider);
    // Declared here so sheets with a shell of their own get it for free.
    final skinned = _SheetSkinScope(glass: glass != null, child: child);
    if (glass == null) return ColoredBox(color: t.bg, child: skinned);

    final surface = ColoredBox(
      color: t.bg.withValues(alpha: t.bg.a * glass.opacity),
      child: skinned,
    );
    return glass.filter == null
        ? surface
        : BackdropFilter(filter: glass.filter!, child: surface);
  }
}

/// What a sheet's blocks stand on.
class _SheetSkinScope extends InheritedWidget {
  const _SheetSkinScope({required this.glass, required super.child});

  final bool glass;

  static _SheetSkinScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SheetSkinScope>();

  @override
  bool updateShouldNotify(_SheetSkinScope old) => old.glass != glass;
}

/// Fill of a plate inside a sheet: a thin film on glass, or it would be the one
/// solid spot of a clear sheet; otherwise the same pill as plates of a page.
Color sheetPanelColor(BuildContext context) =>
    _SheetSkinScope.of(context)?.glass ?? false
    ? context.bloom.text.withValues(alpha: 0.06)
    : context.bloom.pill;

/// A line inside a sheet's plate.
Color sheetLineColor(BuildContext context) =>
    _SheetSkinScope.of(context)?.glass ?? false
    ? context.bloom.text.withValues(alpha: 0.08)
    : context.bloom.ovlLine;

/// A sheet's body: surface, handle, a header and footer that stay put, and what
/// scrolls between them. Sheets with state of their own build on it directly.
class SheetShell extends ConsumerWidget {
  const SheetShell({
    super.key,
    this.header,
    this.footer,
    this.maxFraction = _kSheetMaxFraction,
    this.scrolls = true,
    required this.child,
  });

  final Widget? header;

  /// Pinned to the bottom, doesn't scroll with the items.
  final Widget? footer;

  /// The share of the screen the sheet doesn't grow past.
  final double maxFraction;

  /// False: the child is a list that scrolls itself and builds lazily. It takes
  /// the full height, unless it shrink-wraps.
  final bool scrolls;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final media = MediaQuery.of(context);
    final hero = header is SheetHero;
    final stack = _SheetStackScope.of(context);
    final back = (stack?.depth ?? 0) > 0 ? stack!.chain.back : null;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: media.size.height * maxFraction),
      child: _SheetSkinScope(
        glass: ref.watch(overlayGlassProvider) != null,
        // A group of its own: the sheet lies over the page and its snapshot of
        // what's underneath must be its own too.
        child: GlassGroup(
          child: Stack(
            children: [
              if (stack?.ownSurface ?? true)
                const Positioned.fill(
                  child: SheetSurface(child: SizedBox.expand()),
                ),
              SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // The handle and header stay put: only the items scroll.
                    if (!hero) const SheetHandle(),
                    ?header,
                    Flexible(
                      child: scrolls
                          ? SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [child, const SizedBox(height: 10)],
                              ),
                            )
                          : child,
                    ),
                    ?footer,
                    // Below the list, not in it: a long one must not hide it.
                    if (back != null)
                      Padding(
                        padding: EdgeInsets.only(
                          top: scrolls ? 0 : 8,
                          bottom: 16,
                        ),
                        child: SheetPanel(
                          gap: 0,
                          children: [
                            SheetRow(
                              icon: Bi.arrowLeft,
                              label: context.l.commonBack,
                              onTap: back,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The sheet's handle: on the banner in [color], else in the theme's text.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Container(
        width: 38,
        height: 4,
        decoration: BoxDecoration(
          color: color ?? context.bloom.text.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

/// A sheet's title: a line under it, what acts on the whole sheet on its right.
class SheetTitle extends StatelessWidget {
  const SheetTitle(
    this.title, {
    super.key,
    this.subtitle,
    this.line,
    this.leading,
    this.trailing,
    this.right = kSheetEdge,
    this.bottom = 10,
  });

  final String title;
  final String? subtitle;

  /// Instead of [subtitle]: a line with more than text in it.
  final Widget? line;

  /// On the left of the text: what the sheet is about.
  final Widget? leading;
  final Widget? trailing;

  /// Round buttons stand closer to the edge than text does.
  final double right;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final sub = subtitle;
    return Padding(
      padding: EdgeInsets.fromLTRB(kSheetEdge, 6, right, bottom),
      child: Row(
        children: [
          if (leading case final mark?) ...[mark, const SizedBox(width: 14)],
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.titleLarge,
                ),
                if (line != null || sub != null) ...[
                  const SizedBox(height: 2),
                  line ?? Text(sub!, style: theme.bodyMedium),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// A big choice of a sheet, a block of its own: in a solid list the chosen one
/// can't be lit. A picture, a name, a note under it, a mark on the right.
class SheetOptionTile extends StatelessWidget {
  const SheetOptionTile({
    super.key,
    this.icon,
    this.leading,
    required this.label,
    required this.active,
    required this.onTap,
    this.sub,
    this.check = false,
    this.enabled = true,
  });

  final BloomGlyph? icon;

  /// Instead of [icon]: a flag, a logo, a drawn preview.
  final Widget? leading;
  final String label;

  /// A note under the name; `null` for one line.
  final String? sub;

  /// The chosen choice, or a switched-on item.
  final bool active;

  /// An item of a set: a checkbox instead of a tick and no lighting, since
  /// several can be on.
  final bool check;

  /// Unavailable: greyed whole and not pressable. Not hidden: the sheet shows
  /// what can be turned on, and the note says what's missing.
  final bool enabled;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final note = sub;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: SheetPanel(
        // Close together: these are large, a full gap would tear the list apart.
        gap: 3,
        children: [
          Pressable(
            onTap: enabled ? onTap : null,
            scale: 0.98,
            child: Ink(
              color: active && !check ? t.accent.withValues(alpha: 0.12) : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 15, 18, 15),
                child: Row(
                  children: [
                    // One width for all, flags are the widest: names stand in a
                    // straight column.
                    if (leading != null || icon != null) ...[
                      SizedBox(
                        width: 32,
                        child: Center(
                          child:
                              leading ??
                              BloomIcon(
                                icon,
                                size: 22,
                                color: active ? t.accent : t.iconFg,
                              ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.titleMedium,
                          ),
                          if (note != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              note,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (check)
                      BloomCheck(on: active)
                    else if (active)
                      const SheetTick(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The one button at a sheet's bottom: a plate by default, its height everywhere.
class SheetButton extends StatelessWidget {
  const SheetButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.tone = ButtonTone.plate,
  });

  final String label;
  final VoidCallback? onTap;
  final BloomGlyph? icon;
  final ButtonTone tone;

  @override
  Widget build(BuildContext context) => BloomButton(
    label: label,
    icon: icon,
    tone: tone,
    overlay: true,
    height: 48,
    onTap: onTap,
  );
}

/// A sheet's row with a switch: the whole row toggles.
class SheetSwitchRow extends StatelessWidget {
  const SheetSwitchRow({
    super.key,
    this.icon,
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.danger = false,
    this.padding = const EdgeInsets.all(kSheetEdge),
  });

  final BloomGlyph? icon;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// What depends on a switch that's off greys out and stays in place.
  final bool enabled;

  /// Turning it on removes something: the switch is red, and the row while on.
  final bool danger;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final color = danger && value ? t.danger : t.text;
    final glyph = icon;
    final sub = subtitle;
    final row = GestureDetector(
      onTap: () => onChanged(!value),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            if (glyph != null) ...[
              BloomIcon(glyph, size: 22, color: color),
              const SizedBox(width: 16),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.titleMedium?.copyWith(color: color)),
                  if (sub != null) ...[
                    const SizedBox(height: 3),
                    Text(sub, style: theme.bodySmall),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 14),
            BloomSwitch(
              value: value,
              onChanged: onChanged,
              color: danger ? t.danger : null,
            ),
          ],
        ),
      ),
    );
    return enabled
        ? row
        : IgnorePointer(child: Opacity(opacity: 0.4, child: row));
  }
}

/// Radius of a [SheetSlider]'s thumb. The track is inset by it at both ends, so
/// marks drawn along the track count from it.
const double kSheetSliderThumb = 7;

/// The bar of a sheet that picks a value by ear.
class SheetSlider extends StatelessWidget {
  const SheetSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.label,
    required this.onChanged,
  });

  final double value;
  final double min;
  final double max;
  final int divisions;
  final String label;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => SliderTheme(
    data: SliderTheme.of(context).copyWith(
      trackHeight: 5,
      thumbShape: const RoundSliderThumbShape(
        enabledThumbRadius: kSheetSliderThumb,
      ),
      // Divisions are many, and their own marks would ripple.
      tickMarkShape: SliderTickMarkShape.noTickMark,
    ),
    child: Slider(
      value: value,
      min: min,
      max: max,
      divisions: divisions,
      label: label,
      onChanged: onChanged,
    ),
  );
}

/// A block of a sheet's rows, on a plate.
class SheetPanel extends StatelessWidget {
  const SheetPanel({super.key, required this.children, this.gap = 6});

  final List<Widget> children;

  /// Air above and below; less in lists where each row is a block of its own.
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(kSheetEdge, gap, kSheetEdge, gap),
      child: Material(
        color: sheetPanelColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(context.bloom.radius),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

/// A line across a sheet, between what isn't on a plate.
class SheetLine extends StatelessWidget {
  const SheetLine({super.key});

  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, thickness: 1, color: sheetLineColor(context));
}

/// A divider inside a [SheetPanel], starting where the text does: a line under
/// the icons would cut their column in half.
///
/// [indent] is where the block's text starts: 54 for an icon (16 + 22 + 16).
Widget sheetDivider({double indent = 54}) => Builder(
  builder: (context) => Divider(
    height: 1,
    thickness: 1,
    indent: indent,
    color: sheetLineColor(context),
  ),
);

/// Items on a plate, for a sheet with no banner: a tap closes it and acts.
class SheetActionsPanel extends StatelessWidget {
  const SheetActionsPanel({super.key, required this.actions});

  final List<SheetAction> actions;

  @override
  Widget build(BuildContext context) {
    return SheetPanel(
      children: [
        for (final (i, action) in actions.indexed) ...[
          if (i > 0) sheetDivider(indent: 60),
          _SheetTile(action: action),
        ],
      ],
    );
  }
}

/// A menu's items as flat rows.
class _SheetGroup extends StatelessWidget {
  const _SheetGroup({required this.actions});

  final List<SheetAction> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _kFlatEdge, vertical: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [for (final action in actions) _SheetTile(action: action)],
      ),
    );
  }
}

class _SheetTile extends StatelessWidget {
  const _SheetTile({required this.action});

  final SheetAction action;

  @override
  Widget build(BuildContext context) {
    return SheetRow(
      icon: action.icon,
      label: action.label,
      subtitle: action.subtitle,
      danger: action.danger,
      trailing: action.trailing,
      onTap: _handler(context, action),
    );
  }
}

/// What tapping an item does: closes the sheet and acts, or, for what continues
/// it, keeps the sheet. Null stays null: the item is greyed out.
VoidCallback? _handler(BuildContext context, SheetAction action) {
  final onTap = action.onTap;
  if (onTap == null) return null;
  if (action.next) return () => openNextSheet(context, onTap);
  return () {
    Navigator.of(context).pop();
    onTap();
  };
}

/// A sheet's row: icon, label, grey line under it, a mark on the right.
class SheetRow extends StatelessWidget {
  const SheetRow({
    super.key,
    this.icon,
    this.leading,
    required this.label,
    this.labelMark,
    this.subtitle,
    this.color,
    this.danger = false,
    this.trailing,
    this.gap = 22,
    this.onTap,
  });

  final BloomGlyph? icon;

  /// Instead of [icon]: a platform's logo, a cover.
  final Widget? leading;
  final String label;

  /// Right after the label, like a playlist's pin.
  final Widget? labelMark;
  final String? subtitle;

  /// The row's own colour instead of the text's.
  final Color? color;
  final bool danger;
  final Widget? trailing;

  /// Between [icon] and the text; a cover stands closer.
  final double gap;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final ink =
        color ??
        (danger
            ? t.danger
            : onTap != null
            ? t.text
            : t.muted);
    final title = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.titleMedium?.copyWith(
        color: ink,
        fontWeight: FontWeight.w500,
      ),
    );

    return Pressable(
      onTap: onTap,
      scale: 0.98,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _kRowHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              leading ?? BloomIcon(icon!, size: 22, color: ink),
              SizedBox(width: gap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (labelMark case final mark?)
                      Row(
                        children: [
                          Flexible(child: title),
                          const SizedBox(width: 6),
                          mark,
                        ],
                      )
                    else
                      title,
                    if (subtitle case final subtitle?)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.bodySmall,
                      ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// A small caption over a block of a sheet, what acts on the block on its right.
class SheetCaption extends StatelessWidget {
  const SheetCaption(
    this.text, {
    super.key,
    this.trailing,
    this.color,
    this.padding = const EdgeInsets.fromLTRB(kSheetEdge, 10, kSheetEdge, 4),
  });

  final String text;
  final Widget? trailing;

  /// `text2` when not set.
  final Color? color;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color ?? context.bloom.text2,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// On the right of a [SheetRow]: where a tap leads on.
class SheetChevron extends StatelessWidget {
  const SheetChevron({super.key});

  @override
  Widget build(BuildContext context) =>
      BloomIcon(Bi.altArrowRight, size: 20, color: context.bloom.muted);
}

/// On the right of a [SheetRow]: the one that's picked.
class SheetTick extends StatelessWidget {
  const SheetTick({super.key});

  @override
  Widget build(BuildContext context) =>
      BloomIcon(Bi.check, size: 18, color: context.bloom.accent);
}

/// The capsule of main actions under the banner: icons only, evenly spaced.
class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.actions});

  final List<SheetAction> actions;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
        height: _kRowHeight,
        decoration: BoxDecoration(
          color: sheetPanelColor(context),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final action in actions)
              Expanded(
                child: Semantics(
                  button: true,
                  label: action.label,
                  child: Pressable(
                    onTap: _handler(context, action),
                    child: Center(
                      child: BloomIcon(
                        action.icon,
                        size: 24,
                        color: action.onTap == null ? t.muted : t.text,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A date for a sheet's header: "Created 2 Sept 2026". The label goes muted and
/// the date brighter, so the eye catches the date.
class SheetMeta {
  const SheetMeta({required this.label, required this.date});

  final String label;
  final String date;
}

/// No timestamp, no line: a dash in its place would say nothing.
SheetMeta? sheetDateMeta(BuildContext context, String label, int? ms) {
  if (ms == null || ms <= 0) return null;
  return SheetMeta(
    label: label,
    date: stampDate(ms, Localizations.localeOf(context).languageCode),
  );
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.meta});

  final SheetMeta meta;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final base = Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 13);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '${meta.label} ',
            style: TextStyle(color: t.muted),
          ),
          TextSpan(
            text: meta.date,
            style: TextStyle(color: t.text, fontWeight: FontWeight.w500),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: base,
    );
  }
}

/// The header of a sheet about a track, list or artist: the cover as a banner
/// across the sheet, melting into its surface, with the title over the melt.
/// Holds the handle too.
class SheetHero extends StatelessWidget {
  const SheetHero({
    super.key,
    required this.cover,
    required this.title,
    this.subtitle = '',
    this.subtitleWidget,
    this.meta,
  });

  /// Share of the sheet's width the banner takes, and the least it may be:
  /// under that the title climbs into the handle.
  static const double band = 0.24;
  static const double bandMin = 112;

  final String? cover;
  final String title;
  final String subtitle;

  /// Instead of [subtitle]: a line that's alive, like a list's offline count.
  final Widget? subtitleWidget;
  final SheetMeta? meta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final image = coverImage(cover);
    final width = MediaQuery.sizeOf(context).width;

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: image == null ? 0 : math.max(bandMin, width * band),
      ),
      child: Stack(
        alignment: Alignment.bottomLeft,
        children: [
          if (image != null)
            Positioned.fill(
              // A mask, not a gradient to the sheet's colour: the surface may
              // be glass, and the picture must melt into whatever is there.
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (rect) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFFFFFFF),
                    Color(0xD9FFFFFF),
                    Color(0x33FFFFFF),
                    Color(0x00FFFFFF),
                  ],
                  stops: [0, 0.35, 0.7, 1],
                ).createShader(rect),
                child: Image(image: image, fit: BoxFit.cover),
              ),
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(
              child: SheetHandle(
                color: image == null
                    ? null
                    : Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 26, 16, 2),
            // Full width: the text is what sizes the stack, and the banner with it.
            child: SizedBox(
              width: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.titleLarge?.copyWith(fontSize: 20),
                  ),
                  if (subtitleWidget != null || subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    subtitleWidget ??
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.bodyMedium?.copyWith(fontSize: 14),
                        ),
                  ],
                  if (meta case final meta?) ...[
                    const SizedBox(height: 2),
                    _MetaLine(meta: meta),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A sheet's field with a tick on the right. The tick comes with the text:
/// until then the button has nothing to do.
class SheetField extends StatelessWidget {
  const SheetField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.onSubmit,
    this.autofocus = false,
    this.busy = false,
    this.autocorrect = true,
    this.maxLength,
    this.keyboardType,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(kSheetEdge, 4, kSheetEdge, 6),
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;
  final bool autofocus;

  /// Long work under way (import by link): a spinner on the button, no taps.
  final bool busy;
  final bool autocorrect;
  final int? maxLength;
  final TextInputType? keyboardType;

  /// An icon inside the field on the right: the platform a link was recognised
  /// as.
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final filled = controller.text.trim().isNotEmpty;
    final radius = BorderRadius.circular(t.radius);

    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: sheetPanelColor(context),
                borderRadius: radius,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: BloomField(
                      controller: controller,
                      hint: hint,
                      autofocus: autofocus,
                      enabled: !busy,
                      autocorrect: autocorrect,
                      maxLength: maxLength,
                      keyboardType: keyboardType,
                      action: TextInputAction.done,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      onChanged: onChanged,
                      onSubmitted: (_) => onSubmit(),
                    ),
                  ),
                  if (trailing case final widget?) ...[
                    const SizedBox(width: 8),
                    widget,
                  ],
                ],
              ),
            ),
          ),
          // The row's width moves with the button, or the field would jerk on
          // the first character.
          AnimatedSize(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            child: filled
                ? Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: _ConfirmButton(
                      busy: busy,
                      radius: radius,
                      onTap: onSubmit,
                    ),
                  )
                : const SizedBox(height: 54),
          ),
        ],
      ),
    );
  }
}

class _ConfirmButton extends StatelessWidget {
  const _ConfirmButton({
    required this.busy,
    required this.radius,
    required this.onTap,
  });

  final bool busy;

  /// The field's corner, so the pair doesn't argue.
  final BorderRadius radius;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Pressable(
      onTap: busy ? null : onTap,
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(color: t.accent, borderRadius: radius),
        child: busy
            ? Center(child: BloomSpinner(size: 20, color: t.accentText))
            : BloomIcon(Bi.check, size: 24, color: t.accentText),
      ),
    );
  }
}

/// A count on an outlined pill, by a sheet's title.
class SheetCountPill extends StatelessWidget {
  const SheetCountPill(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: sheetLineColor(context)),
    ),
    child: Text(
      text,
      style: bloomText(size: 12, weight: 700, color: context.bloom.text2),
    ),
  );
}

/// Choice tile of a sheet grid: accent when picked, the sheet's plate
/// otherwise. [builder] lays out the content in the given ink.
class OptionTile extends StatelessWidget {
  const OptionTile({
    super.key,
    required this.active,
    required this.onTap,
    required this.builder,
    this.height,
    this.padding = EdgeInsets.zero,
    this.alignment = Alignment.center,
    this.scale = 0.94,
  });

  /// A tile that says one thing. A wide one presses less, by [scale].
  OptionTile.label(
    String text, {
    Key? key,
    required bool active,
    required VoidCallback onTap,
    double height = 46,
    double size = 15,
    double scale = 0.94,
  }) : this(
         key: key,
         active: active,
         onTap: onTap,
         height: height,
         scale: scale,
         builder: (ink) => Text(
           text,
           maxLines: 1,
           overflow: TextOverflow.ellipsis,
           style: bloomText(size: size, weight: 700, color: ink),
         ),
       );

  final bool active;
  final VoidCallback onTap;
  final Widget Function(Color ink) builder;
  final double? height;
  final EdgeInsets padding;
  final Alignment alignment;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Pressable(
      onTap: onTap,
      scale: scale,
      child: Container(
        height: height,
        padding: padding,
        alignment: alignment,
        decoration: BoxDecoration(
          color: active ? t.accent : sheetPanelColor(context),
          borderRadius: BorderRadius.circular(t.radius * 0.8),
        ),
        child: builder(active ? t.accentText : t.text),
      ),
    );
  }
}
