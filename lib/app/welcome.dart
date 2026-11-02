/// First launch onboarding experience: authentic editorial showcase,
/// Telegram cloud sync, Yandex Music integration, and direct entry.
///
/// Designed with the Unslop philosophy: zero corporate buzzwords, high content
/// density, honest descriptions, and refined tactile typography.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/db/db.dart';
import '../core/l10n/l10n.dart';
import '../features/telegram/telegram_store.dart';
import '../providers/yandex/ym_auth.dart';
import '../shared/ui/bloom_icon.dart';
import '../shared/ui/bloom_sheet.dart';
import 'theme/bloom_theme.dart';
import 'theme/tokens.dart';

const String _seenKey = 'welcome.seen';

/// Whether this is the first launch on this data.
bool isFirstRun(BloomDb db) => db.get(_seenKey) != true;

/// Backwards compatibility alias for launch sequence.
bool takeFirstRun(BloomDb db) => isFirstRun(db);

/// Mark onboarding as completed so it does not show again.
void markWelcomeSeen(BloomDb db) {
  db.set(_seenKey, true);
}

class Welcome extends ConsumerStatefulWidget {
  const Welcome({super.key, required this.show, required this.child});

  final bool show;
  final Widget child;

  @override
  ConsumerState<Welcome> createState() => _WelcomeState();
}

class _WelcomeState extends ConsumerState<Welcome>
    with SingleTickerProviderStateMixin {
  static const _transitionMs = Duration(milliseconds: 450);

  late final AnimationController _cover = AnimationController(
    vsync: this,
    duration: _transitionMs,
    value: 1,
  );

  late bool _on = widget.show;

  @override
  void initState() {
    super.initState();
    _cover.addStatusListener((s) {
      if (s == AnimationStatus.dismissed && mounted) {
        setState(() => _on = false);
      }
    });
  }

  void _leave() {
    if (!mounted || _cover.status == AnimationStatus.reverse) return;
    try {
      markWelcomeSeen(ref.read(dbProvider));
    } catch (_) {
      // In tests or if db is unmounted
    }
    _cover.reverse();
  }

  @override
  void dispose() {
    _cover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_on)
          Positioned.fill(
            child: FadeTransition(
              opacity: CurvedAnimation(
                parent: _cover,
                curve: Curves.easeOutCubic,
              ),
              child: _OnboardingScreen(onContinue: _leave),
            ),
          ),
      ],
    );
  }
}

class _OnboardingScreen extends ConsumerStatefulWidget {
  const _OnboardingScreen({required this.onContinue});

  final VoidCallback onContinue;

  @override
  ConsumerState<_OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<_OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  static const List<_FeatureSlide> _slides = [
    _FeatureSlide(
      eyebrow: 'ФОНОТЕКА',
      title: 'Вся музыка в одном месте',
      description:
          'Локальные треки, Яндекс Музыка, SoundCloud и YouTube. Никакой навязчивой рекламы и искусственных ограничений.',
      kind: _SlideVisualKind.sources,
    ),
    _FeatureSlide(
      eyebrow: 'ТРИ ХАРАКТЕРА',
      title: 'Деки под любое настроение',
      description:
          'Apple Music Aura с динамическим свечением под обложку, тактильный крутящийся винил с тонармом или лаконичный Ivory.',
      kind: _SlideVisualKind.decks,
    ),
    _FeatureSlide(
      eyebrow: 'ТЕКСТ И ЗВУК',
      title: 'Слова в такт и быстрый поиск',
      description:
          'Построчный текст песен с синхронизацией и романизацией, а также мгновенное определение играющей рядом музыки.',
      kind: _SlideVisualKind.lyrics,
    ),
    _FeatureSlide(
      eyebrow: 'ОБЛАКО И БЭКАП',
      title: 'Синхронизация профиля',
      description:
          'Избранное, плейлисты, уровень слушателя и история прослушиваний автоматически сохраняются через Telegram и Vercel.',
      kind: _SlideVisualKind.cloud,
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final tgState = ref.watch(telegramAuthProvider);
    final ymState = ref.watch(ymAuthProvider);

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar: Clean Brand & Skip
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 20, 0),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: t.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: t.accent.withValues(alpha: 0.25),
                        width: 1.0,
                      ),
                    ),
                    padding: const EdgeInsets.all(7),
                    child: Image.asset(
                      'assets/brand/bloom_mark.png',
                      errorBuilder: (_, _, _) =>
                          BloomIcon(Bi.soundwave, color: t.accent, size: 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Bloom',
                    style: bloomText(
                      size: 20,
                      weight: 700,
                      color: t.text,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: widget.onContinue,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Text(
                        'Пропустить',
                        style: TextStyle(
                          color: t.text2,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Middle Carousel: Feature Slides
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (context, index) {
                  final slide = _slides[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Visual Centerpiece
                        _SlideVisual(kind: slide.kind),
                        const SizedBox(height: 32),
                        // Eyebrow Tag
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3.5,
                          ),
                          decoration: BoxDecoration(
                            color: t.ovlBg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: t.ovlLine),
                          ),
                          child: Text(
                            slide.eyebrow,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                              color: t.accent,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Slide Title
                        Text(
                          slide.title,
                          textAlign: TextAlign.center,
                          style: bloomText(
                            size: 24,
                            weight: 700,
                            color: t.text,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 10),
                        // Slide Subtitle
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 320),
                          child: Text(
                            slide.description,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: t.text2,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Page Dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_slides.length, (i) {
                final active = i == _currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  margin: const EdgeInsets.symmetric(horizontal: 3.5),
                  width: active ? 20 : 6,
                  height: 5,
                  decoration: BoxDecoration(
                    color: active ? t.accent : t.muted.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),

            const SizedBox(height: 24),

            // Auth Connectors & Primary Start Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Telegram Connect Button
                  _AuthButton(
                    onTap: () => _openTelegramAuth(context, ref),
                    icon: Bi.send,
                    brandColor: const Color(0xFF2AABEE),
                    title: tgState.authed
                        ? 'Telegram: ${tgState.user?.displayName ?? "Подключен"}'
                        : 'Подключить Telegram',
                    subtitle: tgState.authed
                        ? (tgState.user?.handle != null
                              ? '@${tgState.user!.handle} · Синхронизация активна'
                              : 'Облачная копия активна')
                        : 'Синхронизация фонотеки, плейлистов и уровня',
                    isConnected: tgState.authed,
                  ),

                  const SizedBox(height: 10),

                  // Yandex Music Connect Button
                  _AuthButton(
                    onTap: () => _openYandexAuth(context, ref),
                    icon: Bi.musicNote,
                    brandColor: const Color(0xFFFC3F1D),
                    title: ymState.authed
                        ? 'Яндекс Музыка подключена'
                        : 'Подключить Яндекс Музыку',
                    subtitle: ymState.authed
                        ? (ymState.hasPlus == true
                              ? 'Подписка Плюс активна · Моя волна доступна'
                              : 'Каталог подключен')
                        : 'Быстрый вход по коду ya.ru/device или токену',
                    isConnected: ymState.authed,
                  ),

                  const SizedBox(height: 14),

                  // Primary Action
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: t.accent,
                        foregroundColor: t.accentText,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      onPressed: widget.onContinue,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            context.l.welcomeContinue,
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.1,
                            ),
                          ),
                          const SizedBox(width: 8),
                          BloomIcon(
                            Bi.altArrowRight,
                            size: 16,
                            color: t.accentText,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Telegram Auth Dialog / Sheet ──────────────────────────────────────────
  void _openTelegramAuth(BuildContext context, WidgetRef ref) {
    final tg = ref.read(telegramAuthProvider);
    if (tg.authed) {
      showBloomSheetChild<void>(
        context: context,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2AABEE).withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: BloomIcon(
                        Bi.send,
                        color: Color(0xFF2AABEE),
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tg.user?.displayName ?? 'Telegram подключен',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: context.bloom.text,
                          ),
                        ),
                        if (tg.user?.handle != null)
                          Text(
                            '@${tg.user!.handle}',
                            style: TextStyle(
                              fontSize: 13,
                              color: context.bloom.text2,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.bloom.text,
                  side: BorderSide(
                    color: context.bloom.accent.withValues(alpha: 0.4),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: BloomIcon(
                  Bi.refresh,
                  size: 16,
                  color: context.bloom.accent,
                ),
                label: const Text('Синхронизировать сейчас'),
                onPressed: () async {
                  final ok = await ref
                      .read(telegramAuthProvider.notifier)
                      .pushBackup();
                  if (context.mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ok
                              ? 'Фонотека и плейлисты сохранены в Vercel!'
                              : 'Ошибка связи с Vercel',
                        ),
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.bloom.danger,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  elevation: 0,
                ),
                onPressed: () {
                  ref.read(telegramAuthProvider.notifier).logout();
                  Navigator.of(context).pop();
                },
                child: const Text('Отключить аккаунт'),
              ),
            ],
          ),
        ),
      );
      return;
    }

    final vercelController = TextEditingController(text: defaultVercelUrl);

    showBloomSheetChild<void>(
      context: context,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2AABEE).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const BloomIcon(
                    Bi.send,
                    size: 20,
                    color: Color(0xFF2AABEE),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Вход через Telegram',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: context.bloom.text,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Для входа через официальный Telegram Login Widget укажите адрес развернутого бэкенда Vercel:',
              style: TextStyle(
                fontSize: 13,
                color: context.bloom.text2,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: vercelController,
              decoration: InputDecoration(
                hintText: defaultVercelUrl,
                filled: true,
                fillColor: context.bloom.ovlBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.bloom.ovlLine),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2AABEE),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 13),
                elevation: 0,
              ),
              onPressed: () {
                final url = vercelController.text.trim();
                if (url.isNotEmpty) {
                  ref.read(telegramAuthProvider.notifier).startWebLogin(url);
                  Navigator.of(context).pop();
                }
              },
              child: const Text(
                'Открыть Telegram Login Widget',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => _manualTelegramDataDialog(context, ref),
              child: Text(
                'Ввести имя и username вручную',
                style: TextStyle(fontSize: 12.5, color: context.bloom.text2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _manualTelegramDataDialog(BuildContext context, WidgetRef ref) {
    Navigator.of(context).pop();
    final nameCtrl = TextEditingController();
    final userCtrl = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.bloom.blockColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Данные Telegram профиля'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Отображаемое имя'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: userCtrl,
              decoration: const InputDecoration(
                labelText: '@username (без символа @)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isNotEmpty) {
                ref.read(telegramAuthProvider.notifier).loginWithData({
                  'id': DateTime.now().millisecondsSinceEpoch ~/ 1000,
                  'first_name': name,
                  'username': userCtrl.text.trim().replaceAll('@', ''),
                  'auth_date': DateTime.now().millisecondsSinceEpoch ~/ 1000,
                });
                Navigator.of(ctx).pop();
              }
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  // ── Yandex Music Auth Sheet ───────────────────────────────────────────────
  void _openYandexAuth(BuildContext context, WidgetRef ref) {
    final ym = ref.read(ymAuthProvider);
    if (ym.authed) {
      showBloomSheetChild<void>(
        context: context,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFC3F1D).withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: BloomIcon(
                        Bi.musicNote,
                        color: Color(0xFFFC3F1D),
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Яндекс Музыка',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: context.bloom.text,
                          ),
                        ),
                        Text(
                          ym.hasPlus == true
                              ? 'Подписка Плюс активна ✓'
                              : 'Аккаунт подключен',
                          style: TextStyle(
                            fontSize: 13,
                            color: ym.hasPlus == true
                                ? const Color(0xFF00C853)
                                : context.bloom.text2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.bloom.danger,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  elevation: 0,
                ),
                onPressed: () {
                  ref.read(ymAuthProvider.notifier).logout();
                  Navigator.of(context).pop();
                },
                child: const Text('Отключить Яндекс Музыку'),
              ),
            ],
          ),
        ),
      );
      return;
    }

    final tokenController = TextEditingController();

    showBloomSheetChild<void>(
      context: context,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFC3F1D).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const BloomIcon(
                    Bi.musicNote,
                    size: 20,
                    color: Color(0xFFFC3F1D),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Вход в Яндекс Музыку',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: context.bloom.text,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFC3F1D),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 13),
                elevation: 0,
              ),
              onPressed: () {
                ref.read(ymAuthProvider.notifier).startAuth();
                Navigator.of(context).pop();
              },
              child: const Text(
                'Быстрый вход по коду (ya.ru/device)',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: Divider(color: context.bloom.ovlLine)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    'ИЛИ ПО ТОКЕНУ',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: context.bloom.text2,
                    ),
                  ),
                ),
                Expanded(child: Divider(color: context.bloom.ovlLine)),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tokenController,
              decoration: InputDecoration(
                hintText: 'Вставьте токен y0_...',
                filled: true,
                fillColor: context.bloom.ovlBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.bloom.ovlLine),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: context.bloom.ovlLine),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () async {
                final token = tokenController.text.trim();
                if (token.isNotEmpty) {
                  await ref.read(ymAuthProvider.notifier).loginWithToken(token);
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                }
              },
              child: Text(
                'Сохранить токен',
                style: TextStyle(color: context.bloom.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthButton extends StatelessWidget {
  const _AuthButton({
    required this.onTap,
    required this.icon,
    required this.brandColor,
    required this.title,
    required this.subtitle,
    required this.isConnected,
  });

  final VoidCallback onTap;
  final BloomGlyph icon;
  final Color brandColor;
  final String title;
  final String subtitle;
  final bool isConnected;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;

    return Material(
      color: isConnected ? brandColor.withValues(alpha: 0.10) : t.ovlBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isConnected ? brandColor.withValues(alpha: 0.45) : t.ovlLine,
          width: isConnected ? 1.3 : 1.0,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isConnected
                      ? brandColor
                      : brandColor.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: BloomIcon(
                    isConnected ? Bi.check : icon,
                    size: 18,
                    color: isConnected ? Colors.white : brandColor,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: t.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isConnected ? brandColor : t.text2,
                      ),
                    ),
                  ],
                ),
              ),
              BloomIcon(
                Bi.altArrowRight,
                size: 14,
                color: t.text2.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _SlideVisualKind { sources, decks, lyrics, cloud }

class _FeatureSlide {
  final String eyebrow;
  final String title;
  final String description;
  final _SlideVisualKind kind;

  const _FeatureSlide({
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.kind,
  });
}

class _SlideVisual extends StatelessWidget {
  const _SlideVisual({required this.kind});

  final _SlideVisualKind kind;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;

    switch (kind) {
      case _SlideVisualKind.sources:
        return _SourcesVisual(t: t);
      case _SlideVisualKind.decks:
        return _DecksVisual(t: t);
      case _SlideVisualKind.lyrics:
        return _LyricsVisual(t: t);
      case _SlideVisualKind.cloud:
        return _CloudVisual(t: t);
    }
  }
}

/// Slide 0: Unified catalog pill cluster
class _SourcesVisual extends StatelessWidget {
  const _SourcesVisual({required this.t});
  final BloomThemeColors t;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: t.ovlBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.ovlLine),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _SourceChip(
                label: 'Яндекс Музыка',
                dotColor: const Color(0xFFFC3F1D),
                t: t,
              ),
              const SizedBox(width: 8),
              _SourceChip(
                label: 'SoundCloud',
                dotColor: const Color(0xFFFF5500),
                t: t,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _SourceChip(
                label: 'Локальные FLAC/MP3',
                dotColor: t.accent,
                t: t,
              ),
              const SizedBox(width: 8),
              _SourceChip(
                label: 'YouTube',
                dotColor: const Color(0xFFFF0000),
                t: t,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({
    required this.label,
    required this.dotColor,
    required this.t,
  });

  final String label;
  final Color dotColor;
  final BloomThemeColors t;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: t.blockColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.ovlLine),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: t.text,
            ),
          ),
        ],
      ),
    );
  }
}

/// Slide 1: Three deck style badges
class _DecksVisual extends StatelessWidget {
  const _DecksVisual({required this.t});
  final BloomThemeColors t;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: t.ovlBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.ovlLine),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _DeckBadge(
            title: 'Aura',
            subtitle: 'Glow',
            icon: Bi.magicStick,
            t: t,
            active: true,
          ),
          _DeckBadge(
            title: 'Vinyl',
            subtitle: 'Analog',
            icon: Bi.album,
            t: t,
            active: false,
          ),
          _DeckBadge(
            title: 'Ivory',
            subtitle: 'Editorial',
            icon: Bi.soundwave,
            t: t,
            active: false,
          ),
        ],
      ),
    );
  }
}

class _DeckBadge extends StatelessWidget {
  const _DeckBadge({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.t,
    required this.active,
  });

  final String title;
  final String subtitle;
  final BloomGlyph icon;
  final BloomThemeColors t;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 66,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: active ? t.accent.withValues(alpha: 0.15) : t.blockColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active ? t.accent.withValues(alpha: 0.4) : t.ovlLine,
        ),
      ),
      child: Column(
        children: [
          BloomIcon(icon, size: 20, color: active ? t.accent : t.text2),
          const SizedBox(height: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: active ? t.text : t.text2,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 9.5,
              color: t.text2.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

/// Slide 2: Karaoke text preview
class _LyricsVisual extends StatelessWidget {
  const _LyricsVisual({required this.t});
  final BloomThemeColors t;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.ovlBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.ovlLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hold on to the light',
            style: TextStyle(
              fontSize: 12,
              color: t.text2.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: t.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Where the sound blooms deep',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: t.accent,
                    ),
                  ),
                ),
                BloomIcon(Bi.lyrics, size: 14, color: t.accent),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'And the rhythm takes control',
            style: TextStyle(
              fontSize: 12,
              color: t.text2.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// Slide 3: Cloud profile preview
class _CloudVisual extends StatelessWidget {
  const _CloudVisual({required this.t});
  final BloomThemeColors t;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 230,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: t.ovlBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.ovlLine),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF2AABEE).withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: BloomIcon(Bi.send, size: 20, color: Color(0xFF2AABEE)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Слушатель · Lvl 1',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: t.text,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF00C853),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Vercel Cloud Sync',
                      style: TextStyle(fontSize: 11, color: t.text2),
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
