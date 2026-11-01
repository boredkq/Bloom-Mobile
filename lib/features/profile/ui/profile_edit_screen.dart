/// The profile editor: nick, about, status and the banner's fill (Auto /
/// colour / gradient). On top a live copy of the page's head — the banner, the
/// avatar and the nick as they'll be once saved; a tap on the banner or the
/// avatar changes it. Then the fields, and one wide Save at the bottom.
///
/// Обводок нигде нет: ни кольца у аватара, ни рамок у полей и плашек — блоки
/// держатся своей заливкой. Десктопная настройка «Обводка» вместе с ней и
/// пропала.
///
/// Правка идёт ЧЕРНОВИКОМ и уходит в стор одним куском по «Сохранить» — как в
/// десктопном `draft`. Картинки при этом сохраняются файлами сразу (иначе
/// нечего показывать в превью), поэтому брошенный черновик за собой прибирает:
/// выбранный, но не сохранённый файл удаляется.
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
import 'profile_screen.dart'
    show ProfileBannerHero, ProfileWho, kProfileBannerStrip;

/// Стрелки к [kBannerAngles] — те же, что в десктопной модалке.
const List<String> _angleArrows = ['↑', '↗', '→', '↘', '↓', '↙', '←', '↖'];

/// Какую из двух картинок профиля меняем.
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

  /// Стрелка «назад» взведена: следующее нажатие бросит правку.
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

  // ── Картинки ──────────────────────────────────────────────────────────────

  /// Одна шторка на обе картинки: наверху переключатель «Аватар / Обложка»,
  /// под ним превью выбранной и кнопка загрузки — как в макете, где обложка
  /// ставится тем же меню, что и аватар.
  ///
  /// [target] — с какой вкладки открыть: тап по аватару приводит на аватар,
  /// тап по полосе — на обложку, кнопка в шапке открывает на аватаре.
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
    // Аспект рамки берём у настоящей полосы на странице профиля — как на
    // десктопе, где кроппер спрашивает размеры у самой карточки.
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

  // ── Выход ─────────────────────────────────────────────────────────────────

  void _save() {
    // Пустой ник сохраняется пустым, как на ПК: показывается «Пользователь».
    ref
        .read(profileProvider.notifier)
        .save(
          _draft.copyWith(
            name: _name.text.trim(),
            bio: _bio.text.trim(),
            status: _status.text.trim(),
          ),
        );
    // Прежние свои картинки больше никому не нужны.
    if (_draft.avatar != _saved.avatar) unawaited(deleteCover(_saved.avatar));
    if (_draft.banner != _saved.banner) unawaited(deleteCover(_saved.banner));
    showToast(context, context.l.profileSaved, kind: ToastKind.success);
    context.go(kProfileLocation);
  }

  /// Уход с непустой правкой спрашивает вторым нажатием на саму стрелку — как
  /// удаление своей темы в «Оформлении»: модалки на такое тут нет.
  void _cancel() {
    if (_dirty && !_armed) {
      setState(() => _armed = true);
      // Само остывает — иначе взведённая стрелка так и ждёт промаха.
      _disarm?.cancel();
      _disarm = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _armed = false);
      });
      return;
    }
    // Выбранные, но не сохранённые файлы — мусор, на который никто не сошлётся.
    if (_draft.avatar != _saved.avatar) unawaited(deleteCover(_draft.avatar));
    if (_draft.banner != _saved.banner) unawaited(deleteCover(_draft.banner));
    context.go(kProfileLocation);
  }

  // ── Раскладка ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;

    return PopScope(
      // Системное «назад» — та же «Отмена»: первое взводит стрелку, второе
      // бросает правку.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      // Свой [Scaffold]: страница идёт поверх каркаса приложения, а без
      // material-предка `TextField` просто падает. Он же поднимает кнопку
      // «Сохранить» над клавиатурой.
      child: Scaffold(
        backgroundColor: t.bg,
        // Сверху [SafeArea] нет: полоса обложки уходит под системную строку,
        // как на самой странице профиля, и свой отступ считает сама.
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
                          onTap: _cancel,
                        ),
                        const Spacer(),
                        GlassIconButton(
                          icon: Bi.gallery,
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
            // Кнопка лежит на своей заливке фона: список под ней прокручивается
            // и без подложки цеплялся бы за текст.
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

/// Шторка картинок профиля: две вкладки-превью сверху, крупное превью
/// выбранной под ними и кнопка загрузки внизу.
///
/// «По ссылке» из макета не переношу — на десктопе картинки профиля берутся
/// только файлом, своего загрузчика по URL у Bloom нет.
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

  /// Цвет и градиент обложки правятся прямо в шторке — черновик страницы
  /// должен узнавать об этом сразу, а не по закрытию.
  final ValueChanged<UserProfile> onChanged;

  final ValueChanged<ProfileImage> onPick;
  final ValueChanged<ProfileImage> onDrop;

  @override
  State<_ImageSheet> createState() => _ImageSheetState();
}

class _ImageSheetState extends State<_ImageSheet> {
  late ProfileImage _target = widget.initial;

  /// Свой снимок черновика: цвет обложки правится прямо тут, и превью должно
  /// меняться под пальцем. Наружу каждая правка уходит сразу — страница под
  /// шторкой уже живёт с ней.
  late UserProfile _draft = widget.draft;

  bool get _hasOwn => switch (_target) {
    ProfileImage.avatar => _draft.avatar != null,
    ProfileImage.banner => _draft.banner != null,
  };

  void _patch(UserProfile next) {
    setState(() => _draft = next);
    widget.onChanged(next);
  }

  /// Пункт закрывает шторку ДО действия: дальше открывается галерея, а поверх
  /// шторки её звать нельзя (то же правило, что у [SheetAction]).
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
          // Вкладки — только миниатюры, без подписей: по кружку и полоске и
          // так видно, где аватар, а где обложка.
          Row(
            children: [
              Expanded(
                child: _ImageTab(
                  active: !banner,
                  onTap: () => setState(() => _target = ProfileImage.avatar),
                  child: ProfileAvatar(profile: _draft, size: 38),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ImageTab(
                  active: banner,
                  onTap: () => setState(() => _target = ProfileImage.banner),
                  child: ClipRRect(
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
          // Превью выбранного, а для обложки ещё и её цвет: она бывает не
          // картинкой, и красить её больше негде.
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
                              _Swatch(
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
                              _Swatch(
                                color: _draft.bannerColor2,
                                onTap: () => _pickColor(
                                  _draft.bannerColor2,
                                  (c) =>
                                      _patch(_draft.copyWith(bannerColor2: c)),
                                ),
                              ),
                            ],
                            const Spacer(),
                            _Segmented<BannerColorMode>(
                              value: _draft.bannerMode,
                              items: {
                                BannerColorMode.auto: (l) => l.profileColorAuto,
                                BannerColorMode.solid: (l) =>
                                    l.profileColorSolid,
                                BannerColorMode.gradient: (l) =>
                                    l.profileColorGradient,
                              },
                              onChanged: (m) =>
                                  _patch(_draft.copyWith(bannerMode: m)),
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
          BloomButton(
            label: context.l.commonUpload,
            icon: Bi.import,
            tone: ButtonTone.accent,
            height: 52,
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

/// Вкладка шторки: одна миниатюра. Выбранная не обводится, а светлеет —
/// плёнкой поверх той же тёмной панели.
class _ImageTab extends StatelessWidget {
  const _ImageTab({
    required this.active,
    required this.onTap,
    required this.child,
  });

  final bool active;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Material(
      color: active
          ? Colors.white.withValues(alpha: 0.14)
          : sheetPanelColor(context),
      borderRadius: BorderRadius.circular(t.radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: SizedBox(height: 38, child: Center(child: child)),
        ),
      ),
    );
  }
}

/// Поле ввода: подпись сверху, счётчик символов внутри плашки справа.
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

/// Сегментированный переключатель — десктопный `.pedit-mode-toggle`.
class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final Map<T, String Function(AppLocalizations l)> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in items.entries)
            GestureDetector(
              onTap: () => onChanged(entry.key),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: entry.key == value ? t.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  entry.value(context.l),
                  style: theme.bodySmall?.copyWith(
                    color: entry.key == value ? t.accentText : t.text2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Восемь углов градиента стрелками.
class _AngleRow extends StatelessWidget {
  const _AngleRow({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < kBannerAngles.length; i++)
          GestureDetector(
            onTap: () => onChanged(kBannerAngles[i]),
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: kBannerAngles[i] == value ? t.accent : t.bg,
                borderRadius: BorderRadius.circular(t.radius * 0.6),
              ),
              child: Text(
                _angleArrows[i],
                style: TextStyle(
                  fontSize: 15,
                  color: kBannerAngles[i] == value ? t.accentText : t.text2,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Кликабельный сватч цвета. Единственная линия, что тут осталась, — самая
/// тихая: без неё тёмный цвет на тёмной плашке просто не виден.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.onTap});

  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(t.radius * 0.5),
          border: Border.all(color: t.ovlLine),
        ),
      ),
    );
  }
}
