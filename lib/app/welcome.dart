/// First launch onboarding experience: authentic editorial showcase,
/// in-tree Telegram cloud sync, Yandex Music integration, and direct entry.
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

enum _OnboardingModal { none, telegram, yandex }

class _OnboardingScreen extends ConsumerStatefulWidget {
  const _OnboardingScreen({required this.onContinue});

  final VoidCallback onContinue;

  @override
  ConsumerState<_OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<_OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  _OnboardingModal _activeModal = _OnboardingModal.none;

  // Controllers for manual inputs
  final TextEditingController _tgNameCtrl = TextEditingController();
  final TextEditingController _tgUserCtrl = TextEditingController();
  final TextEditingController _ymTokenCtrl = TextEditingController();

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
    _tgNameCtrl.dispose();
    _tgUserCtrl.dispose();
    _ymTokenCtrl.dispose();
    super.dispose();
  }

  void _closeModal() {
    setState(() => _activeModal = _OnboardingModal.none);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final tgState = ref.watch(telegramAuthProvider);
    final ymState = ref.watch(ymAuthProvider);

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
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
                          errorBuilder: (_, _, _) => BloomIcon(
                            Bi.soundwave,
                            color: t.accent,
                            size: 20,
                          ),
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
                        color: active
                            ? t.accent
                            : t.muted.withValues(alpha: 0.35),
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
                        onTap: () {
                          setState(
                            () => _activeModal = _OnboardingModal.telegram,
                          );
                        },
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
                        onTap: () {
                          setState(
                            () => _activeModal = _OnboardingModal.yandex,
                          );
                        },
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

            // In-tree Modal Sheet Overlay
            if (_activeModal != _OnboardingModal.none)
              _buildInTreeModal(context, t, tgState, ymState),
          ],
        ),
      ),
    );
  }

  Widget _buildInTreeModal(
    BuildContext context,
    BloomTokens t,
    TelegramAuthState tgState,
    YmAuthState ymState,
  ) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: _closeModal,
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: Colors.black.withValues(alpha: 0.65),
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {}, // Prevent click propagation inside card
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: t.blockColor,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: t.ovlLine, width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 36,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: _activeModal == _OnboardingModal.telegram
                  ? _buildTelegramModal(t, tgState)
                  : _buildYandexModal(t, ymState),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTelegramModal(BloomTokens t, TelegramAuthState tgState) {
    if (tgState.authed) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF2AABEE).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: BloomIcon(Bi.send, color: Color(0xFF2AABEE), size: 22),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tgState.user?.displayName ?? 'Telegram подключен',
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700,
                        color: t.text,
                      ),
                    ),
                    if (tgState.user?.handle != null)
                      Text(
                        '@${tgState.user!.handle}',
                        style: TextStyle(fontSize: 13, color: t.text2),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const BloomIcon(Bi.close, size: 20),
                onPressed: _closeModal,
              ),
            ],
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: t.text,
              side: BorderSide(color: t.accent.withValues(alpha: 0.45)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
            icon: BloomIcon(Bi.refresh, size: 18, color: t.accent),
            label: const Text('Синхронизировать сейчас'),
            onPressed: () async {
              final ok = await ref
                  .read(telegramAuthProvider.notifier)
                  .pushBackup();
              if (mounted) {
                _closeModal();
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
              backgroundColor: t.danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
              elevation: 0,
            ),
            onPressed: () {
              ref.read(telegramAuthProvider.notifier).logout();
              _closeModal();
            },
            child: const Text('Отключить Telegram'),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: const Color(0xFF2AABEE).withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const BloomIcon(
                Bi.send,
                size: 22,
                color: Color(0xFF2AABEE),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Вход через Telegram',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: t.text,
                ),
              ),
            ),
            IconButton(
              icon: const BloomIcon(Bi.close, size: 20),
              onPressed: _closeModal,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Быстрый вход через официальный Telegram Login Widget:',
          style: TextStyle(fontSize: 13, color: t.text2, height: 1.35),
        ),
        const SizedBox(height: 14),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2AABEE),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(vertical: 13),
            elevation: 0,
          ),
          onPressed: () {
            ref
                .read(telegramAuthProvider.notifier)
                .startWebLogin(defaultVercelUrl);
            _closeModal();
          },
          child: const Text(
            'Войти через Telegram Login Widget',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: Divider(color: t.ovlLine)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                'ИЛИ ВВЕДИТЕ ДАННЫЕ ВРУЧНУЮ',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: t.text2,
                ),
              ),
            ),
            Expanded(child: Divider(color: t.ovlLine)),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _tgNameCtrl,
          decoration: InputDecoration(
            hintText: 'Ваше имя',
            filled: true,
            fillColor: t.ovlBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: t.ovlLine),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 11,
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _tgUserCtrl,
          decoration: InputDecoration(
            hintText: '@username (без символа @)',
            filled: true,
            fillColor: t.ovlBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: t.ovlLine),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 11,
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: t.text,
            side: BorderSide(color: t.ovlLine),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 11),
          ),
          onPressed: () {
            final name = _tgNameCtrl.text.trim();
            if (name.isNotEmpty) {
              ref.read(telegramAuthProvider.notifier).loginWithData({
                'id': DateTime.now().millisecondsSinceEpoch ~/ 1000,
                'first_name': name,
                'username': _tgUserCtrl.text.trim().replaceAll('@', ''),
                'auth_date': DateTime.now().millisecondsSinceEpoch ~/ 1000,
              });
              _closeModal();
            }
          },
          child: const Text('Сохранить профиль'),
        ),
      ],
    );
  }

  Widget _buildYandexModal(BloomTokens t, YmAuthState ymState) {
    if (ymState.authed) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFFC3F1D).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: BloomIcon(
                    Bi.musicNote,
                    color: Color(0xFFFC3F1D),
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Яндекс Музыка',
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700,
                        color: t.text,
                      ),
                    ),
                    Text(
                      ymState.hasPlus == true
                          ? 'Подписка Плюс активна ✓'
                          : 'Аккаунт подключен',
                      style: TextStyle(
                        fontSize: 13,
                        color: ymState.hasPlus == true
                            ? const Color(0xFF00C853)
                            : t.text2,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const BloomIcon(Bi.close, size: 20),
                onPressed: _closeModal,
              ),
            ],
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: t.danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
              elevation: 0,
            ),
            onPressed: () {
              ref.read(ymAuthProvider.notifier).logout();
              _closeModal();
            },
            child: const Text('Отключить Яндекс Музыку'),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: const Color(0xFFFC3F1D).withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const BloomIcon(
                Bi.musicNote,
                size: 22,
                color: Color(0xFFFC3F1D),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Вход в Яндекс Музыку',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: t.text,
                ),
              ),
            ),
            IconButton(
              icon: const BloomIcon(Bi.close, size: 20),
              onPressed: _closeModal,
            ),
          ],
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFC3F1D),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(vertical: 13),
            elevation: 0,
          ),
          onPressed: () {
            ref.read(ymAuthProvider.notifier).startAuth();
            _closeModal();
          },
          child: const Text(
            'Быстрый вход по коду (ya.ru/device)',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: Divider(color: t.ovlLine)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                'ИЛИ ПО ТОКЕНУ',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: t.text2,
                ),
              ),
            ),
            Expanded(child: Divider(color: t.ovlLine)),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _ymTokenCtrl,
          decoration: InputDecoration(
            hintText: 'Вставьте токен y0_...',
            filled: true,
            fillColor: t.ovlBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: t.ovlLine),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 11,
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: t.text,
            side: BorderSide(color: t.ovlLine),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 11),
          ),
          onPressed: () async {
            final token = _ymTokenCtrl.text.trim();
            if (token.isNotEmpty) {
              await ref.read(ymAuthProvider.notifier).loginWithToken(token);
              _closeModal();
            }
          },
          child: const Text('Сохранить токен'),
        ),
      ],
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

/// Slide 0: Unified catalog pill cluster with comfortable wrapping
class _SourcesVisual extends StatelessWidget {
  const _SourcesVisual({required this.t});
  final BloomTokens t;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 320),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: t.ovlBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.ovlLine),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          _SourceChip(
            label: 'Яндекс Музыка',
            dotColor: const Color(0xFFFC3F1D),
            t: t,
          ),
          _SourceChip(
            label: 'SoundCloud',
            dotColor: const Color(0xFFFF5500),
            t: t,
          ),
          _SourceChip(label: 'Локальные файлы', dotColor: t.accent, t: t),
          _SourceChip(
            label: 'YouTube Music',
            dotColor: const Color(0xFFFF0033),
            t: t,
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
  final BloomTokens t;

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
  final BloomTokens t;

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
            title: 'Levyra',
            subtitle: 'Cyber',
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
  final BloomTokens t;
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
  final BloomTokens t;

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
  final BloomTokens t;

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
