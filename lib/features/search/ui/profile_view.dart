/// Профиль аккаунта по вставленной в поиск ссылке (`soundcloud.com/username`).
///
/// Порт десктопного `ProfileView` из `SearchPage.tsx`: шапка с аватаром, ниже
/// плейлисты аккаунта и его лайки — каждая секция со своим импортом. Именно
/// сюда переехал перенос аккаунта, когда из библиотеки убрали строку
/// «Импортировать из сервиса».
///
/// Живёт в выдаче поиска, а не отдельной страницей: ссылка на аккаунт — это
/// разовое действие «перетащить к себе», ради него не стоит заводить экран.
library;

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/entities/entities.dart';
import '../../../core/providers/music_provider.dart';
import '../../../core/store/cover_store.dart';
import '../../../core/store/library_store.dart';
import '../../../providers/soundcloud/sc_provider.dart' show scLikesOf;
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/cover_hero.dart';
import '../../../shared/ui/entity_tiles.dart';
import '../../../shared/ui/pressable.dart';
import '../../detail/detail_nav.dart';
import '../../library/import_url.dart' show likesTitle;
import '../../player/play_source.dart';

/// По сколько лайков добавляет «Показать ещё». У аккаунта их бывает под две
/// сотни — рисовать все сразу незачем.
const int _likesStep = 30;

class ProfileView extends ConsumerStatefulWidget {
  const ProfileView({super.key, required this.profile});

  final ProfileData profile;

  @override
  ConsumerState<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends ConsumerState<ProfileView> {
  int _likesShown = _likesStep;

  /// Идёт импорт плейлистов: они тянутся по одному, и повторный тап удвоил бы
  /// библиотеку.
  bool _importing = false;

  ProfileData get _profile => widget.profile;

  @override
  void didUpdateWidget(ProfileView old) {
    super.didUpdateWidget(old);
    // Другой аккаунт — счётчик лайков заново.
    if (old.profile.artist.id != widget.profile.artist.id) {
      _likesShown = _likesStep;
    }
  }

  void _toast(String message, [ToastKind kind = ToastKind.info]) {
    if (!mounted) return;
    showToast(context, message, kind: kind);
  }

  // ── Импорт ──────────────────────────────────────────────────────────────

  /// Лайки в «Все треки».
  void _importLikes() {
    final likes = _profile.likes;
    if (likes.isEmpty) return;
    final added = ref.read(libraryProvider.notifier).addToLibrary(likes);
    _toast(
      added > 0
          ? context.l.pvAdded(context.l.tracksCount(added))
          : context.l.commonAlreadyInLibrary,
      added > 0 ? ToastKind.success : ToastKind.warn,
    );
  }

  /// Лайки отдельным плейлистом. Лайки аккаунта становятся его источником —
  /// «Обновить треки» перетянет их заново.
  void _likesAsPlaylist() {
    final artist = _profile.artist;
    final likes = _profile.likes;
    if (likes.isEmpty) return;
    final set = scLikesOf(artist, likesTitle(artist.name));
    ref
        .read(libraryProvider.notifier)
        .createPlaylist(
          set.title,
          tracks: likes,
          cover: artist.avatar,
          source: PlSourceRef.of(set),
        );
    _toast(
      context.l.pvPlaylistCreated(context.l.tracksCount(likes.length)),
      ToastKind.success,
    );
  }

  /// Все плейлисты аккаунта. Состав приходит только по `getPlaylist`, поэтому
  /// тянем их по одному; недоступный просто пропускаем.
  Future<void> _importPlaylists() async {
    final sets = _profile.playlists;
    if (sets.isEmpty || _importing) return;
    setState(() => _importing = true);
    // Живой тост: счётчик и полоса идут по ходу обхода, итог подменяет их на
    // месте — вместо двух тостов подряд.
    final toast = ScaffoldMessenger.of(
      context,
    ).busyToast(context.l.pvImporting(sets.length));
    final l10n = context.l;

    final registry = ref.read(registryProvider);
    final lib = ref.read(libraryProvider.notifier);
    var ok = 0;
    for (var i = 0; i < sets.length; i++) {
      final set = sets[i];
      // Счётчик двигаем ДО работы: ниже есть `continue`.
      toast.update(
        l10n.pvImportProgress(i + 1, sets.length),
        progress: i / sets.length,
      );
      try {
        final content = await registry.forEntity(set.id)?.getPlaylist(set.id);
        final tracks = content?.tracks ?? const <Track>[];
        if (tracks.isEmpty) continue;
        final page = content?.playlist;
        lib.createPlaylist(
          page?.title ?? set.title,
          tracks: tracks,
          cover: page?.cover ?? set.cover,
          source: PlSourceRef.of(set).copyWith(
            title: page?.title,
            owner: page?.ownerName,
            cover: page?.cover,
          ),
        );
        ok++;
      } catch (_) {
        // Один закрытый плейлист не должен прерывать остальные.
      }
    }
    toast.finish(
      l10n.pvImported(ok, sets.length),
      kind: ok == sets.length ? ToastKind.success : ToastKind.warn,
    );
    if (!mounted) return;
    setState(() => _importing = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final artist = _profile.artist;
    final sets = _profile.playlists;
    final likes = _profile.likes;
    final shown = likes.length < _likesShown ? likes.length : _likesShown;

    return ListView(
      // Снизу — бары каркаса: они плавают над содержимым.
      padding: EdgeInsets.fromLTRB(8, 0, 8, 12 + bottomBarsInset(context)),
      children: [
        _Hero(artist: artist),
        if (sets.isNotEmpty) ...[
          _SectionHead(
            title: context.l.pvPlaylistsTitle(sets.length),
            actions: [
              BloomButton(
                label: context.l.pvImportAll,
                tone: ButtonTone.plate,
                height: 32,
                busy: _importing,
                onTap: _importPlaylists,
              ),
            ],
          ),
          _SetGrid(sets: sets),
        ],
        if (likes.isNotEmpty) ...[
          _SectionHead(
            title: context.l.pvLikesTitle(likes.length),
            actions: [
              BloomButton(
                label: context.l.commonAddToLibrary,
                tone: ButtonTone.accent,
                height: 32,
                onTap: _importLikes,
              ),
              BloomButton(
                label: context.l.pvToPlaylist,
                tone: ButtonTone.plate,
                height: 32,
                onTap: _likesAsPlaylist,
              ),
            ],
          ),
          for (var i = 0; i < shown; i++)
            TrackRow(
              track: likes[i],
              queue: likes,
              index: i,
              // Источник — сам аккаунт: пилюля плеера назовёт его и вернёт
              // на страницу артиста.
              source: ArtistSource(_profile.artist),
            ),
          if (shown < likes.length)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
              child: BloomButton(
                label: context.l.commonShowMore,
                tone: ButtonTone.plate,
                height: 44,
                onTap: () => setState(() => _likesShown += _likesStep),
              ),
            ),
        ],
        if (sets.isEmpty && likes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text(
                context.l.pvNothingPublic,
                textAlign: TextAlign.center,
                style: theme.bodyMedium?.copyWith(color: t.muted),
              ),
            ),
          ),
      ],
    );
  }
}

/// Шапка аккаунта: размытый аватар фоном, он же кружком слева, справа — имя,
/// статистика, описание и действия.
class _Hero extends ConsumerStatefulWidget {
  const _Hero({required this.artist});

  final Artist artist;

  static const double _avatar = 84;

  @override
  ConsumerState<_Hero> createState() => _HeroState();
}

class _HeroState extends ConsumerState<_Hero> {
  static const double _avatar = _Hero._avatar;

  /// Метка перелёта аватарки на страницу артиста. Обе кнопки, ведущие туда же
  /// («Треки» и сама аватарка), отдают её: `Hero` с этой меткой в дереве один,
  /// и лететь всё равно будет аватарка.
  final _tag = UniqueKey();

  @override
  Widget build(BuildContext context) {
    final artist = widget.artist;
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final avatar = artist.avatar;
    final flight = avatar == null || avatar.isEmpty
        ? null
        : CoverFlight(tag: _tag, image: avatar);
    final following = ref.watch(libraryProvider).isFollowing(artist.id);
    final sub = artist.fullName ?? '';

    return ClipRRect(
      borderRadius: BorderRadius.circular(t.radius),
      child: Stack(
        children: [
          Positioned.fill(child: _Backdrop(url: artist.avatar)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Pressable(
                      onTap: () => openArtist(
                        context,
                        artist.id,
                        initial: artist,
                        flight: flight,
                      ),
                      scale: 0.97,
                      child: Cover(
                        url: artist.avatar,
                        size: _avatar,
                        circle: true,
                        flight: flight,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            artist.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.headlineSmall?.copyWith(fontSize: 22),
                          ),
                          if (sub.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              sub,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.bodyMedium,
                            ),
                          ],
                          if (artist.description case final d?
                              when d.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              d,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: BloomButton(
                        label: context.l.commonTracks,
                        icon: Bi.playBold,
                        tone: ButtonTone.accent,
                        height: 46,
                        onTap: () => openArtist(
                          context,
                          artist.id,
                          initial: artist,
                          flight: flight,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GlassIconButton(
                      icon: following ? Bi.check : Bi.user,
                      size: 46,
                      background: following ? t.accent : null,
                      color: following ? t.accentText : null,
                      onTap: () {
                        final on = ref
                            .read(libraryProvider.notifier)
                            .toggleFollow(artist);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              on
                                  ? context.l.followedToast(artist.name)
                                  : context.l.unfollowedToast,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Фон шапки — сильно размытый аватар под тёмной плёнкой; без картинки просто
/// поверхность темы.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final image = coverImage(url);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (image == null)
          ColoredBox(color: t.coverEmpty)
        else
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 34, sigmaY: 34),
            child: Image(image: image, fit: BoxFit.cover),
          ),
        // Плёнка: на светлом аватаре имя и подпись иначе не читаются.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.30),
                Colors.black.withValues(alpha: 0.62),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Заголовок секции профиля: название слева, кнопки импорта справа.
class _SectionHead extends StatelessWidget {
  const _SectionHead({required this.title, required this.actions});

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 20, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          for (final a in actions) ...[const SizedBox(width: 8), a],
        ],
      ),
    );
  }
}

/// Плейлисты аккаунта — та же сетка в две колонки, что у выдачи поиска, но
/// внутри общей прокрутки профиля.
class _SetGrid extends StatelessWidget {
  const _SetGrid({required this.sets});

  final List<Playlist> sets;

  static const double _pad = 8;
  static const double _gap = 16;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final cell = (width - 16 - _pad * 2 - _gap) / 2;

    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: _pad),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: _gap,
        mainAxisSpacing: 20,
        mainAxisExtent: cell + setCaption(sets),
      ),
      itemCount: sets.length,
      itemBuilder: (context, i) => SetCard(set: sets[i], size: null),
    );
  }
}
