/// Parts of customization sheets for library and preset pictures: the preview
/// on top and Delete pinned to the bottom.
library;

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/cover_store.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';

/// Sheet header: a full-width picture, with edges like the blocks below. There
/// may be several pictures (a preset has one per taken context): they flip by
/// finger, with dots below showing how many.
class CustSheetPreview extends StatefulWidget {
  const CustSheetPreview({super.key, required this.srcs});

  /// Preview height.
  static const double height = 180;

  final List<String> srcs;

  @override
  State<CustSheetPreview> createState() => _CustSheetPreviewState();
}

class _CustSheetPreviewState extends State<CustSheetPreview> {
  final _pages = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final srcs = widget.srcs;
    return Padding(
      padding: const EdgeInsets.fromLTRB(kSheetEdge, 4, kSheetEdge, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(t.radius),
        child: SizedBox(
          height: CustSheetPreview.height,
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(color: t.pill),
            child: switch (srcs.length) {
              // A preset with all pictures deleted shows a box icon.
              0 => Center(
                child: BloomIcon(Bi.boxMinimalistic, size: 30, color: t.muted),
              ),
              1 => _FitImage(src: srcs.first),
              _ => Stack(
                fit: StackFit.expand,
                children: [
                  PageView.builder(
                    controller: _pages,
                    itemCount: srcs.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (_, i) => _FitImage(src: srcs[i]),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 10,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < srcs.length; i++) ...[
                          if (i > 0) const SizedBox(width: 6),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(
                                alpha: i == _index ? 0.9 : 0.35,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            },
          ),
        ),
      ),
    );
  }
}

/// Preview picture: fitted whole rather than cropped, so a vertical screenshot
/// and wide wallpaper both show fully. The same picture, stretched and blurred,
/// fills the empty margins.
class _FitImage extends StatelessWidget {
  const _FitImage({required this.src});

  /// Blur of the margin backing.
  static const double blur = 24;

  /// Dim of the backing: a blurred copy shouldn't compete with the photo.
  static const double dim = 0.35;

  final String src;

  @override
  Widget build(BuildContext context) {
    final image = coverImage(src);
    if (image == null) return const SizedBox.expand();
    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(
            sigmaX: blur,
            sigmaY: blur,
            tileMode: TileMode.decal,
          ),
          child: Image(
            image: image,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.expand(),
          ),
        ),
        ColoredBox(color: Colors.black.withValues(alpha: dim)),
        Image(
          image: image,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => Center(
            child: Text(
              context.l.custImageGone,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ],
    );
  }
}

/// Delete, pinned to the sheet's bottom.
class CustSheetDelete extends StatelessWidget {
  const CustSheetDelete({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(kSheetEdge),
    child: SheetButton(label: context.l.commonDelete, onTap: onTap),
  );
}
