/// First launch onboarding experience: interactive feature showcase,
/// Telegram authentication, Yandex Music connect, and smooth entry to the app.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/db/db.dart';
import '../core/l10n/l10n.dart';
import '../features/telegram/telegram_store.dart';
import '../providers/yandex/ym_auth.dart';
import '../shared/ui/atoms.dart';
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
  static const _transitionMs = Duration(milliseconds: 500);

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
                curve: Curves.easeInOutQuad,
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
      tag: 'БЕЗ КОМПРОМИССОВ',
      title: 'Музыка без границ',
      subtitle:
          'Слушайте миллионы треков, открывайте чарты и наслаждайтесь любимым звуком в премиальном качестве.',
      icon: Bi.soundwave,
    ),
    _FeatureSlide(
      tag: 'AURA · VINYL · IVORY',
      title: 'Плееры нового поколения',
      subtitle:
          'Живое свечение Apple Music Aura, крутящийся виниловый диск и строгий редакционный минимализм Ivory.',
      icon: Bi.magicStick,
    ),
    _FeatureSlide(
      tag: 'ВОДОПАД LRC & SHAZAM',
      title: 'Слова песен и поиск звука',
      subtitle:
          'Синхронизированный водопадный текст с романизацией и встроенное распознавание музыки через микрофон.',
      icon: Bi.microphone,
    ),
    _FeatureSlide(
      tag: 'ВАША ФОНОТЕКА',
      title: 'Telegram & Яндекс Музыка',
      subtitle:
          'Подключите ваши аккаунты прямо сейчас или начните слушать без регистрации — выбор всегда за вами.',
      icon: Bi.heart,
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
            // Top Bar: Logo & App Name
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: t.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: t.accent.withValues(alpha: 0.3),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: t.accent.withValues(alpha: 0.25),
                          blurRadius: 16,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(7),
                    child: Image.asset(
                      'assets/brand/bloom_mark.png',
                      errorBuilder: (_, __, ___) =>
                          BloomIcon(Bi.soundwave, color: t.accent),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Bloom',
                    style: bloomText(
                      size: 22,
                      weight: 700,
                      color: t.text,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const Spacer(),
                  // Skip button
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
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Middle Carousel
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (context, index) {
                  final slide = _slides[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Large Feature Icon with Aura Glow
                        Container(
                          width: 86,
                          height: 86,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: t.accent.withValues(alpha: 0.12),
                            border: Border.all(
                              color: t.accent.withValues(alpha: 0.4),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: t.accent.withValues(alpha: 0.35),
                                blurRadius: 32,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: Center(
                            child: BloomIcon(
                              slide.icon,
                              size: 40,
                              color: t.accent,
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        // Badge Tag
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: t.ovlBg,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: t.ovlLine),
                          ),
                          child: Text(
                            slide.tag,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.4,
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
                            size: 26,
                            weight: 700,
                            color: t.text,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        // Slide Subtitle
                        Text(
                          slide.subtitle,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14.5,
                            color: t.text2,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Dots Indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_slides.length, (i) {
                final active = i == _currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 22 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: active ? t.accent : t.muted.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),

            const SizedBox(height: 20),

            // Auth Connectors & Action Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Telegram Connect Button
                  _AuthButton(
                    onTap: () => _openTelegramAuth(context, ref),
                    icon: Bi.send,
                    accentColor: const Color(0xFF2AABEE),
                    title: tgState.authed
                        ? 'Telegram: ${tgState.user?.displayName ?? "Подключен"}'
                        : 'Войти через Telegram',
                    subtitle: tgState.authed
                        ? (tgState.user?.handle ?? 'Аккаунт синхронизирован')
                        : 'Вход через виджет Vercel или бота',
                    isConnected: tgState.authed,
                  ),

                  const SizedBox(height: 10),

                  // Yandex Music Connect Button
                  _AuthButton(
                    onTap: () => _openYandexAuth(context, ref),
                    icon: Bi.musicNote,
                    accentColor: const Color(0xFFFC3F1D),
                    title: ymState.authed
                        ? 'Яндекс Музыка'
                        : 'Войти в Яндекс Музыку',
                    subtitle: ymState.authed
                        ? (ymState.hasPlus == true
                              ? 'Подписка Плюс активна ✓'
                              : 'Подключено ✓')
                        : 'Вход по коду устройства или токену',
                    isConnected: ymState.authed,
                  ),

                  const SizedBox(height: 14),

                  // Main Continue Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: t.accent,
                        foregroundColor: t.accentText,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
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
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
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
                  const SizedBox(height: 14),
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
      // Show details & logout option
      showBloomSheetChild<void>(
        context: context,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Telegram подключен',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                '${tg.user?.displayName} (${tg.user?.handle ?? ""})',
                style: TextStyle(color: context.bloom.text2),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.bloom.danger,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(46),
                ),
                onPressed: () {
                  ref.read(telegramAuthProvider.notifier).logout();
                  Navigator.of(context).pop();
                },
                child: const Text('Выйти из Telegram'),
              ),
            ],
          ),
        ),
      );
      return;
    }

    // Modal with Telegram Login Options
    final vercelController = TextEditingController(
      text: 'https://bloom-auth.vercel.app',
    );

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
                    color: const Color(0xFF2AABEE).withValues(alpha: 0.2),
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
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Для входа через официальный Telegram Login Widget укажите адрес развернутого Vercel-бэкенда:',
              style: TextStyle(fontSize: 13, color: context.bloom.text2),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: vercelController,
              decoration: InputDecoration(
                hintText: 'https://your-bloom.vercel.app',
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
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2AABEE),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 13),
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
                'Ввести данные пользователя вручную',
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
        title: const Text('Ввод профиля Telegram'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Имя пользователя'),
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
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Яндекс Музыка подключена',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                ym.hasPlus == true ? 'Плюс активен' : 'Аккаунт активен',
                style: TextStyle(color: context.bloom.text2),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.bloom.danger,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(46),
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
                    color: const Color(0xFFFC3F1D).withValues(alpha: 0.2),
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
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Option 1: Device flow (ya.ru/device)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFC3F1D),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 13),
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
            const SizedBox(height: 18),
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
            const SizedBox(height: 14),
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
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () async {
                final token = tokenController.text.trim();
                if (token.isNotEmpty) {
                  final ok = await ref
                      .read(ymAuthProvider.notifier)
                      .loginWithToken(token);
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
    required this.accentColor,
    required this.title,
    required this.subtitle,
    required this.isConnected,
  });

  final VoidCallback onTap;
  final BloomGlyph icon;
  final Color accentColor;
  final String title;
  final String subtitle;
  final bool isConnected;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;

    return Material(
      color: isConnected
          ? accentColor.withValues(alpha: 0.12)
          : t.ovlBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isConnected
              ? accentColor.withValues(alpha: 0.5)
              : t.ovlLine,
          width: isConnected ? 1.4 : 1.0,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isConnected
                      ? accentColor
                      : accentColor.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: BloomIcon(
                    isConnected ? Bi.check : icon,
                    size: 18,
                    color: isConnected ? Colors.white : accentColor,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
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
                        fontSize: 12,
                        color: isConnected ? accentColor : t.text2,
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

class _FeatureSlide {
  final String tag;
  final String title;
  final String subtitle;
  final BloomGlyph icon;

  const _FeatureSlide({
    required this.tag,
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}
