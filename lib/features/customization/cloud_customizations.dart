/// Cloud Customizations & Themes from Vercel backend.
/// Allows users to browse and apply community themes, Levyra presets,
/// and aesthetic color palettes.
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../app/theme/bloom_theme.dart';
import '../../app/theme/fonts.dart';
import '../../app/theme/tokens.dart';
import '../../core/store/settings_store.dart';
import '../../features/player/player_style_store.dart';
import '../../features/telegram/telegram_store.dart' show defaultVercelUrl;
import '../../shared/ui/bloom_icon.dart';
import '../../shared/ui/bloom_sheet.dart';

class CloudPreset {
  final String id;
  final String name;
  final String category;
  final String description;
  final String author;
  final String source;
  final Color accent;
  final Color accent2;
  final Color bg;
  final PlayerStyle playerStyle;
  final String fontFamily;
  final String? wallpaperUrl;

  const CloudPreset({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.author,
    required this.source,
    required this.accent,
    required this.accent2,
    required this.bg,
    required this.playerStyle,
    required this.fontFamily,
    this.wallpaperUrl,
  });

  factory CloudPreset.fromJson(Map<String, dynamic> json) {
    Color parseHex(String? hex, Color fallback) {
      if (hex == null || hex.isEmpty) return fallback;
      final clean = hex.replaceAll('#', '');
      final val = int.tryParse(clean.length == 6 ? 'FF$clean' : clean, radix: 16);
      return val != null ? Color(val) : fallback;
    }

    PlayerStyle parseStyle(String? s) {
      for (final val in PlayerStyle.values) {
        if (val.name == s) return val;
      }
      return PlayerStyle.standard;
    }

    return CloudPreset(
      id: json['id'] as String? ?? 'preset',
      name: json['name'] as String? ?? 'Кастомная тема',
      category: json['category'] as String? ?? 'levyra',
      description: json['description'] as String? ?? '',
      author: json['author'] as String? ?? 'Open Source',
      source: json['source'] as String? ?? 'vercel',
      accent: parseHex(json['accent'] as String?, const Color(0xFF00E5FF)),
      accent2: parseHex(json['accent2'] as String?, const Color(0xFF7C4DFF)),
      bg: parseHex(json['bg'] as String?, const Color(0xFF0A0A0A)),
      playerStyle: parseStyle(json['playerStyle'] as String?),
      fontFamily: json['fontFamily'] as String? ?? kDefaultFont,
      wallpaperUrl: json['wallpaperUrl'] as String?,
    );
  }
}

const List<CloudPreset> kFallbackPresets = [
  CloudPreset(
    id: 'levyra-cosmic',
    name: 'Levyra Cosmic Glass',
    category: 'levyra',
    description: 'Глубокий космический неоновый градиент с бирюзовым и фиолетовым свечением',
    author: 'Levyra Design System',
    source: 'levyra.dev',
    accent: Color(0xFF00E5FF),
    accent2: Color(0xFF7C4DFF),
    bg: Color(0xFF05070C),
    playerStyle: PlayerStyle.levyraCosmic,
    fontFamily: 'Inter',
  ),
  CloudPreset(
    id: 'levyra-cyber',
    name: 'Levyra Cyberpunk Neon',
    category: 'cyberpunk',
    description: 'Электрический циан и глубокий синий неон с кибернетической декой плеера',
    author: 'Levyra Audio Team',
    source: 'github.com/theclaymethod/unslop',
    accent: Color(0xFF00F0FF),
    accent2: Color(0xFF0066FF),
    bg: Color(0xFF0A0E17),
    playerStyle: PlayerStyle.levyraCyber,
    fontFamily: 'JetBrains Mono',
  ),
  CloudPreset(
    id: 'levyra-aurora',
    name: 'Levyra Aurora Borealis',
    category: 'nordic',
    description: 'Изумрудное северное сияние с арктическими переливами и гладким свечением',
    author: 'Nordic Sound Collective',
    source: 'nordic-themes.org',
    accent: Color(0xFF00FF87),
    accent2: Color(0xFF60EFFF),
    bg: Color(0xFF040F0F),
    playerStyle: PlayerStyle.levyraAurora,
    fontFamily: 'Inter',
  ),
  CloudPreset(
    id: 'levyra-ember',
    name: 'Levyra Ember Sunset',
    category: 'retro',
    description: 'Теплое аналоговое свечение заката, винила и ламповых усилителей',
    author: 'Analog Craft',
    source: 'unsplash.com',
    accent: Color(0xFFFF416C),
    accent2: Color(0xFFFF4B2B),
    bg: Color(0xFF120807),
    playerStyle: PlayerStyle.levyraEmber,
    fontFamily: 'Inter',
  ),
  CloudPreset(
    id: 'tokyo-night',
    name: 'Tokyo Night Storm',
    category: 'cyberpunk',
    description: 'Культовая темная палитра ночного Токио со штормовым синим акцентом',
    author: 'Tokyo Night Open Source',
    source: 'github.com/folke/tokyo-night',
    accent: Color(0xFF7AA2F7),
    accent2: Color(0xFFBB9AF7),
    bg: Color(0xFF1A1B26),
    playerStyle: PlayerStyle.aura,
    fontFamily: 'JetBrains Mono',
  ),
  CloudPreset(
    id: 'catppuccin-mocha',
    name: 'Catppuccin Mocha',
    category: 'minimal',
    description: 'Мягкая пастельная палитра фламинго и сирени для комфортного звука',
    author: 'Catppuccin Org',
    source: 'catppuccin.com',
    accent: Color(0xFFF5C2E7),
    accent2: Color(0xFF89B4FA),
    bg: Color(0xFF1E1E2E),
    playerStyle: PlayerStyle.ivory,
    fontFamily: 'Inter',
  ),
  CloudPreset(
    id: 'synthwave-84',
    name: 'Synthwave 1984',
    category: 'retro',
    description: 'Ретро-футуризм 80-х, пурпурный неон и дека кассетного магнитофона',
    author: 'Robb Owen',
    source: 'synthwave.dev',
    accent: Color(0xFFF72585),
    accent2: Color(0xFF7209B7),
    bg: Color(0xFF160826),
    playerStyle: PlayerStyle.levyraCassette,
    fontFamily: 'Minecraft Rus',
  ),
  CloudPreset(
    id: 'oled-monolith',
    name: 'OLED Pure Monolith',
    category: 'minimal',
    description: 'Абсолютно черный цвет 0% энергопотребления, микро-рамки и минимализм',
    author: 'Minimal Mono Lab',
    source: 'theclaymethod/unslop',
    accent: Color(0xFFFFFFFF),
    accent2: Color(0xFF94A3B8),
    bg: Color(0xFF000000),
    playerStyle: PlayerStyle.levyraOled,
    fontFamily: 'Inter',
  ),
];

final cloudPresetsProvider = FutureProvider<List<CloudPreset>>((ref) async {
  try {
    final cleanUrl = defaultVercelUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$cleanUrl/api/customizations');
    final res = await http.get(uri).timeout(const Duration(seconds: 8));
    if (res.statusCode == 200) {
      final json = jsonDecode(res.body);
      if (json is Map && json['presets'] is List) {
        final list = (json['presets'] as List)
            .whereType<Map<String, dynamic>>()
            .map(CloudPreset.fromJson)
            .toList();
        if (list.isNotEmpty) return list;
      }
    }
  } catch (_) {
    // Network or server timeout: return fallback presets
  }
  return kFallbackPresets;
});

void applyCloudPreset(WidgetRef ref, CloudPreset preset) {
  final settings = ref.read(settingsProvider.notifier);

  // 1. Create or apply theme colors
  Color blockColor = Color.lerp(preset.bg, Colors.white, 0.08) ?? preset.bg;
  final themePreset = settings.createCustomTheme(
    name: preset.name,
    bg: preset.bg,
    blockColor: blockColor,
    accent: preset.accent,
  );
  settings.setTheme(themePreset.id);

  // 2. Set player style
  ref.read(playerStyleProvider.notifier).setStyle(preset.playerStyle);

  // 3. Set UI font
  try {
    ref.read(uiFontProvider.notifier).setFont(preset.fontFamily);
  } catch (_) {}
}

Future<void> showCloudCustomizationsSheet(BuildContext context) {
  return showBloomSheetChild<void>(
    context: context,
    child: const _CloudCustomizationsView(),
  );
}

class _CloudCustomizationsView extends ConsumerWidget {
  const _CloudCustomizationsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final presetsAsync = ref.watch(cloudPresetsProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: t.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: BloomIcon(Bi.magicStick, size: 20, color: t.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Облачные кастомизации Vercel',
                      style: bloomText(
                        size: 17,
                        weight: 700,
                        color: t.text,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Text(
                      'Темы, палитры и стили дек из открытых источников',
                      style: TextStyle(fontSize: 12, color: t.text2),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          presetsAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (_, _) => _PresetList(presets: kFallbackPresets),
            data: (presets) => _PresetList(presets: presets),
          ),
        ],
      ),
    );
  }
}

class _PresetList extends ConsumerWidget {
  const _PresetList({required this.presets});

  final List<CloudPreset> presets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.65,
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: presets.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final p = presets[index];
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: t.ovlBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: t.ovlLine),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Swatch circles
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: p.accent,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24, width: 1.2),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: p.accent2,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24, width: 1.2),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: p.bg,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24, width: 1.2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.name,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: t.text,
                            ),
                          ),
                          Text(
                            '${p.author} · ${p.playerStyle.name}',
                            style: TextStyle(fontSize: 11, color: t.text2),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: p.accent,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        elevation: 0,
                      ),
                      onPressed: () {
                        applyCloudPreset(ref, p);
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Применена тема «${p.name}»!'),
                          ),
                        );
                      },
                      child: const Text(
                        'Применить',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                if (p.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    p.description,
                    style: TextStyle(
                      fontSize: 12,
                      color: t.text2,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
