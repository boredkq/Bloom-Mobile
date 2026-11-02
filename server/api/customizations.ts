import type { VercelRequest, VercelResponse } from '@vercel/node';

export interface CloudThemePreset {
  id: string;
  name: string;
  category: 'levyra' | 'cyberpunk' | 'nordic' | 'minimal' | 'retro';
  description: string;
  author: string;
  source: string;
  accent: string;
  accent2: string;
  bg: string;
  playerStyle: string;
  fontFamily: string;
  wallpaperUrl?: string;
}

const PRESETS: CloudThemePreset[] = [
  {
    id: 'levyra-cosmic',
    name: 'Levyra Cosmic Glass',
    category: 'levyra',
    description: 'Глубокий космический неоновый градиент с бирюзовым и фиолетовым свечением',
    author: 'Levyra Design System',
    source: 'levyra.dev',
    accent: '#00E5FF',
    accent2: '#7C4DFF',
    bg: '#05070C',
    playerStyle: 'levyraCosmic',
    fontFamily: 'Inter',
    wallpaperUrl: 'https://images.unsplash.com/photo-1506703719100-a0f3a48c0f86?w=1200&q=80',
  },
  {
    id: 'levyra-cyber',
    name: 'Levyra Cyberpunk Neon',
    category: 'cyberpunk',
    description: 'Электрический циан и глубокий синий неон с кибернетической декой плеера',
    author: 'Levyra Audio Team',
    source: 'github.com/theclaymethod/unslop',
    accent: '#00F0FF',
    accent2: '#0066FF',
    bg: '#0A0E17',
    playerStyle: 'levyraCyber',
    fontFamily: 'JetBrains Mono',
    wallpaperUrl: 'https://images.unsplash.com/photo-1542751371-adc38448a05e?w=1200&q=80',
  },
  {
    id: 'levyra-aurora',
    name: 'Levyra Aurora Borealis',
    category: 'nordic',
    description: 'Изумрудное северное сияние с арктическими переливами и гладким свечением',
    author: 'Nordic Sound Collective',
    source: 'nordic-themes.org',
    accent: '#00FF87',
    accent2: '#60EFFF',
    bg: '#040F0F',
    playerStyle: 'levyraAurora',
    fontFamily: 'Inter',
    wallpaperUrl: 'https://images.unsplash.com/photo-1531366936337-7c912a4589a7?w=1200&q=80',
  },
  {
    id: 'levyra-ember',
    name: 'Levyra Ember Sunset',
    category: 'retro',
    description: 'Теплое аналоговое свечение заката, винила и ламповых усилителей',
    author: 'Analog Craft',
    source: 'unsplash.com',
    accent: '#FF416C',
    accent2: '#FF4B2B',
    bg: '#120807',
    playerStyle: 'levyraEmber',
    fontFamily: 'Inter',
    wallpaperUrl: 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=1200&q=80',
  },
  {
    id: 'tokyo-night',
    name: 'Tokyo Night Storm',
    category: 'cyberpunk',
    description: 'Культовая темная палитра ночного Токио со штормовым синим и лавандовым акцентом',
    author: 'Tokyo Night Open Source',
    source: 'github.com/folke/tokyo-night',
    accent: '#7AA2F7',
    accent2: '#BB9AF7',
    bg: '#1A1B26',
    playerStyle: 'aura',
    fontFamily: 'JetBrains Mono',
    wallpaperUrl: 'https://images.unsplash.com/photo-1503899036084-c55cdd92da26?w=1200&q=80',
  },
  {
    id: 'catppuccin-mocha',
    name: 'Catppuccin Mocha',
    category: 'minimal',
    description: 'Мягкая пастельная палитра фламинго и сирени для комфортного прослушивания',
    author: 'Catppuccin Org',
    source: 'catppuccin.com',
    accent: '#F5C2E7',
    accent2: '#89B4FA',
    bg: '#1E1E2E',
    playerStyle: 'ivory',
    fontFamily: 'Inter',
  },
  {
    id: 'nord-frost',
    name: 'Nord Arctic Frost',
    category: 'nordic',
    description: 'Сдержанная ледяная гамма скандинавской зимы со строгими линиями',
    author: 'Arctic Ice Studio',
    source: 'nordtheme.com',
    accent: '#88C0D0',
    accent2: '#81A1C1',
    bg: '#2E3440',
    playerStyle: 'ivory',
    fontFamily: 'Inter',
  },
  {
    id: 'synthwave-84',
    name: 'Synthwave 1984',
    category: 'retro',
    description: 'Ретро-футуризм 80-х, пурпурный неон и дека кассетного магнитофона',
    author: 'Robb Owen',
    source: 'synthwave.dev',
    accent: '#F72585',
    accent2: '#7209B7',
    bg: '#160826',
    playerStyle: 'levyraCassette',
    fontFamily: 'Minecraft Rus',
    wallpaperUrl: 'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?w=1200&q=80',
  },
  {
    id: 'oled-monolith',
    name: 'OLED Pure Monolith',
    category: 'minimal',
    description: 'Абсолютно черный цвет 0% энергопотребления, микро-рамки и швейцарский минимализм',
    author: 'Minimal Mono Lab',
    source: 'theclaymethod/unslop',
    accent: '#FFFFFF',
    accent2: '#94A3B8',
    bg: '#000000',
    playerStyle: 'levyraOled',
    fontFamily: 'Inter',
  },
];

export default function handler(req: VercelRequest, res: VercelResponse) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  const category = req.query.category as string | undefined;
  const filtered = category
    ? PRESETS.filter((p) => p.category.toLowerCase() === category.toLowerCase())
    : PRESETS;

  return res.status(200).json({
    ok: true,
    total: filtered.length,
    presets: filtered,
  });
}
