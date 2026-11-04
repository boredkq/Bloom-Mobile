/// The profile editor: nick, about, status and the banner's fill (Auto / colour
/// / gradient). On top a live copy of the page's head: the banner, the avatar
/// and the nick as they'll be once saved; a tap on the banner or the avatar
/// changes it. Then the fields, and one wide Save at the bottom.
///
/// No outlines anywhere: blocks hold by their fill.
///
/// Edits go as a DRAFT and reach the store in one piece on Save. Pictures save
/// as files at once (or the preview has nothing to show), so an abandoned draft
/// cleans up: a picked but unsaved file gets deleted.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LengthLimitingTextInputFormatter;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/cover_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/color_picker.dart';
import '../../../shared/ui/glass.dart';
import '../profile_store.dart';
import 'image_cropper.dart';
import 'profile_avatar.dart';
import 'profile_banner.dart';
import '../../../shared/ui/big_tabs.dart';
import 'profile_screen.dart'
    show ProfileBannerHero, ProfileWho, kProfileBannerStrip;

/// Arrows for [kBannerAngles].
const List<String> _angleArrows = ['↑', '↗', '→', '↘', '↓', '↙', '←', '↖'];

/// Which of the two profile pictures is changing.
enum ProfileImage { avatar, banner }

class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  late final UserProfile _saved = ref.read(profileProvider);
  late UserProfile _draft = _saved;

  late final TextEditingController _name = TextEditingController(
    text: _saved.name,
  );
  late final TextEditingController _bio = TextEditingController(
    text: _saved.bio,
  );
  late final TextEditingController _status = TextEditingController(
    text: _saved.status,
  );

  bool get _dirty =>
      _draft != _saved ||
      _name.text.trim() != _saved.name ||
      _bio.text.trim() != _saved.bio ||
      _status.text.trim() != _saved.status;

  /// The back arrow is armed: the next press drops the edit.
  bool _armed = false;
  Timer? _disarm;

  @override
  void dispose() {
    _disarm?.cancel();
    _name.dispose();
    _bio.dispose();
    _status.dispose();
    super.dispose();
  }

  void _patch(UserProfile next) => setState(() => _draft = next);

  // ── Pictures ──────────────────────────────────────────────────────────────

  /// One sheet for both pictures: an Avatar and Banner switch on top, the
  /// picked one's preview below and an upload button. [target] is the tab to
  /// open: a tap on the avatar leads to avatar, on the band to banner, and the
  /// header button to avatar.
  void _imageMenu(ProfileImage target) => showBloomSheetChild(
    context: context,
    child: _ImageSheet(
      draft: _draft,
      initial: target,
      onChanged: _patch,
      onPick: (it) => it == ProfileImage.avatar ? _pickAvatar() : _pickBanner(),
      onDrop: (it) => it == ProfileImage.avatar ? _dropAvatar() : _dropBanner(),
    ),
  );

  Future<void> _pickAvatar() async {
    final picked = await pickAndCropImage(
      context,
      shape: CropShape.circle,
      prefix: 'ava',
    );
    if (picked == null) return;
    final stale = _draft.avatar != _saved.avatar ? _draft.avatar : null;
    _patch(_draft.copyWith(avatar: picked));
    unawaited(deleteCover(stale));
  }

  Future<void> _pickBanner() async {
    // The frame's aspect comes from the real band on the profile page.
    final width = MediaQuery.sizeOf(context).width;
    final picked = await pickAndCropImage(
      context,
      shape: CropShape.rect,
      aspect: kProfileBannerStrip / width,
      output: 1440,
      prefix: 'banner',
    );
    if (picked == null) return;
    final stale = _draft.banner != _saved.banner ? _draft.banner : null;
    _patch(_draft.copyWith(banner: picked));
    unawaited(deleteCover(stale));
  }

  void _dropAvatar() {
    final stale = _draft.avatar != _saved.avatar ? _draft.avatar : null;
    _patch(_draft.copyWith(clearAvatar: true));
    unawaited(deleteCover(stale));
  }

  void _dropBanner() {
    final stale = _draft.banner != _saved.banner ? _draft.banner : null;
    _patch(_draft.copyWith(clearBanner: true));
    unawaited(deleteCover(stale));
  }

  // ── Leaving ───────────────────────────────────────────────────────────────

  void _save() {
    // An empty nick saves empty, and the default name shows.
    ref
        .read(profileProvider.notifier)
        .save(
          _draft.copyWith(
            name: _name.text.trim(),
            bio: _bio.text.trim(),
            status: _status.text.trim(),
          ),
        );
    // Former own pictures are no longer needed.
    if (_draft.avatar != _saved.avatar) unawaited(deleteCover(_saved.avatar));
    if (_draft.banner != _saved.banner) unawaited(deleteCover(_saved.banner));
    toaster.show(context.l.profileSaved, kind: ToastKind.success);
    context.go(kProfileLocation);
  }

  /// Leaving with a non-empty edit asks by a second press on the arrow itself,
  /// with no modal for this.
  void _cancel() {
    if (_dirty && !_armed) {
      setState(() => _armed = true);
      // Cools down by itself, or the armed arrow waits for a slip.
      _disarm?.cancel();
      _disarm = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _armed = false);
      });
      return;
    }
    // Picked but unsaved files are junk nothing will refer to.
    if (_draft.avatar != _saved.avatar) unawaited(deleteCover(_draft.avatar));
    if (_draft.banner != _saved.banner) unawaited(deleteCover(_draft.banner));
    context.go(kProfileLocation);
  }

  // ── Layout ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;

    return PopScope(
      // System Back is the same Cancel: the first arms the arrow, the second
      // drops the edit.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      // Own [Scaffold]: the page goes over the app's shell, and with no
      // material ancestor `TextField` crashes. It also lifts Save above the
      // keyboard.
      child: Scaffold(
        backgroundColor: t.bg,
        // No top [SafeArea]: the banner band goes under the status bar, as on
        // the profile page, and counts its own inset.
        body: Column(
          children: [
            Expanded(
              child: CustomScrollView(
                slivers: [
                  ProfileBannerHero(
                    profile: _draft,
                    onTap: () => _imageMenu(ProfileImage.banner),
                    bar: Row(
                      children: [
                        // Armed, it's a red bin: the next tap drops the edit.
                        GlassIconButton(
                          icon: _armed ? Bi.trashBinTrash : Bi.altArrowLeft,
                          color: _armed ? t.danger : null,
                          white: true,
                          onTap: _cancel,
                        ),
                        const Spacer(),
                        GlassIconButton(
                          icon: Bi.gallery,
                          white: true,
                          onTap: () => _imageMenu(ProfileImage.avatar),
                        ),
                      ],
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        children: [
                          // The page's own head, with what's typed so far.
                          ListenableBuilder(
                            listenable: Listenable.merge([_name, _status]),
                            builder: (_, _) => ProfileWho(
                              profile: _draft.copyWith(
                                name: _name.text,
                                status: _status.text,
                              ),
                              onAvatar: () => _imageMenu(ProfileImage.avatar),
                            ),
                          ),
                          const SizedBox(height: 22),
                          _Field(
                            label: context.l.profileNickname,
                            controller: _name,
                            hint: context.l.profileNicknameHint,
                            limit: kNickMax,
                          ),
                          const SizedBox(height: 16),
                          _Field(
                            label: context.l.profileAbout,
                            controller: _bio,
                            hint: context.l.profileAboutHint,
                            limit: kBioMax,
                            lines: 4,
                          ),
                          const SizedBox(height: 16),
                          _Field(
                            label: context.l.profileStatus,
                            controller: _status,
                            hint: context.l.profileStatusHint,
                            limit: kStatusMax,
                            italic: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // The button lies on its own background fill: the list scrolls
            // under it, and with no backing it would catch on text.
            ColoredBox(
              color: t.bg,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: BloomButton(
                    label: context.l.commonSave,
                    tone: ButtonTone.accent,
                    height: 56,
                    onTap: _save,
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

/// Profile pictures sheet: two preview tabs on top, a large preview of the
/// picked one below and an upload button at the bottom.
class _ImageSheet extends StatefulWidget {
  const _ImageSheet({
    required this.draft,
    required this.initial,
    required this.onChanged,
    required this.onPick,
    required this.onDrop,
  });

  final UserProfile draft;
  final ProfileImage initial;

  /// Banner colour and gradient are edited right in the sheet, and the page's
  /// draft should learn at once, not on closing.
  final ValueChanged<UserProfile> onChanged;

  final ValueChanged<ProfileImage> onPick;
  final ValueChanged<ProfileImage> onDrop;

  @override
  State<_ImageSheet> createState() => _ImageSheetState();
}

class _ImageSheetState extends State<_ImageSheet> {
  late ProfileImage _target = widget.initial;

  /// Own draft snapshot: banner colour is edited right here, and the preview
  /// should change under the finger. Each edit goes out at once: the page below
  /// already lives with it.
  late UserProfile _draft = widget.draft;

  bool get _hasOwn => switch (_target) {
    ProfileImage.avatar => _draft.avatar != null,
    ProfileImage.banner => _draft.banner != null,
  };

  void _patch(UserProfile next) {
    setState(() => _draft = next);
    widget.onChanged(next);
  }

  /// An item closes the sheet BEFORE acting: the gallery opens next and can't
  /// be called over the sheet (the same rule as [SheetAction]).
  void _run(ValueChanged<ProfileImage> action) {
    final target = _target;
    Navigator.of(context).pop();
    action(target);
  }

  Future<void> _pickColor(Color current, ValueChanged<Color> apply) async {
    final picked = await showBloomColorPicker(context, current);
    if (picked != null) apply(picked);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final banner = _target == ProfileImage.banner;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tabs are just thumbnails with no captions: the circle and band show
          // which is which.
          Row(
            children: [
              Expanded(
                child: OptionTile(
                  active: !banner,
                  height: 66,
                  onTap: () => setState(() => _target = ProfileImage.avatar),
                  builder: (_) => ProfileAvatar(profile: _draft, size: 38),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OptionTile(
                  active: banner,
                  height: 66,
                  onTap: () => setState(() => _target = ProfileImage.banner),
                  builder: (_) => ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 54,
                      height: 30,
                      child: ProfileBannerFill(profile: _draft),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Preview of the picked one, and for the banner its colour too: it's
          // not always a picture, with nowhere else to paint it.
          SheetPanel(
            children: [
              SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (banner)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(t.radius * 0.7),
                          child: AspectRatio(
                            aspectRatio: 16 / 5,
                            child: ProfileBannerFill(profile: _draft),
                          ),
                        )
                      else
                        Center(
                          child: ProfileAvatar(profile: _draft, size: 108),
                        ),
                      if (banner) ...[
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            if (_draft.bannerMode != BannerColorMode.auto)
                              ColorChip(
                                width: 46,
                                height: 36,
                                color: _draft.bannerColor,
                                onTap: () => _pickColor(
                                  _draft.bannerColor,
                                  (c) =>
                                      _patch(_draft.copyWith(bannerColor: c)),
                                ),
                              ),
                            if (_draft.bannerMode ==
                                BannerColorMode.gradient) ...[
                              const SizedBox(width: 10),
                              ColorChip(
                                width: 46,
                                height: 36,
                                color: _draft.bannerColor2,
                                onTap: () => _pickColor(
                                  _draft.bannerColor2,
                                  (c) =>
                                      _patch(_draft.copyWith(bannerColor2: c)),
                                ),
                              ),
                            ],
                            const Spacer(),
                            PillTabs(
                              labels: [
                                context.l.profileColorAuto,
                                context.l.profileColorSolid,
                                context.l.profileColorGradient,
                              ],
                              index: _draft.bannerMode.index,
                              onPick: (i) => _patch(
                                _draft.copyWith(
                                  bannerMode: BannerColorMode.values[i],
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_draft.bannerMode == BannerColorMode.auto) ...[
                          const SizedBox(height: 12),
                          Text(
                            context.l.profileAutoHint,
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(color: t.muted),
                          ),
                        ],
                        if (_draft.bannerMode == BannerColorMode.gradient) ...[
                          const SizedBox(height: 12),
                          _AngleRow(
                            value: _draft.bannerAngle,
                            onChanged: (a) =>
                                _patch(_draft.copyWith(bannerAngle: a)),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SheetButton(
            label: context.l.commonUpload,
            icon: Bi.import,
            tone: ButtonTone.accent,
            onTap: () => _run(widget.onPick),
          ),
          if (_hasOwn)
            BloomButton(
              label: banner
                  ? context.l.profileRemoveImage
                  : context.l.profileRemovePhoto,
              color: t.danger,
              onTap: () => _run(widget.onDrop),
            ),
        ],
      ),
    );
  }
}

/// Input: a caption on top, a character count inside the plate on the right.
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.hint,
    required this.limit,
    this.lines = 1,
    this.italic = false,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final int limit;
  final int lines;
  final bool italic;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final multiline = lines > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(label, style: theme.labelSmall),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) => GlassBox(
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(
                crossAxisAlignment: multiline
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: BloomField(
                      controller: controller,
                      hint: hint,
                      maxLines: lines,
                      minLines: lines,
                      formatters: [LengthLimitingTextInputFormatter(limit)],
                      style: theme.titleMedium?.copyWith(
                        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${value.text.characters.length}/$limit',
                    style: theme.bodySmall?.copyWith(color: t.muted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AngleRow extends StatelessWidget {
  const _AngleRow({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < kBannerAngles.length; i++)
          SizedBox.square(
            dimension: 36,
            child: OptionTile(
              active: kBannerAngles[i] == value,
              onTap: () => onChanged(kBannerAngles[i]),
              builder: (ink) => Text(
                _angleArrows[i],
                style: TextStyle(fontSize: 15, color: ink),
              ),
            ),
          ),
      ],
    );
  }
}
