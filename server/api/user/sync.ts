import type { VercelRequest, VercelResponse } from '@vercel/node';

interface UserBackup {
  userId: string;
  updatedAt: number;
  profile?: Record<string, any>;
  favorites?: any[];
  playlists?: any[];
  level?: Record<string, any>;
  stats?: Record<string, any>;
  follows?: any[];
  dislikes?: any[];
  settings?: Record<string, any>;
}

// In-memory fallback for instances without Redis/KV configuration
const memoryStorage = new Map<string, UserBackup>();

async function saveToStorage(backup: UserBackup): Promise<void> {
  const key = `bloom:user:${backup.userId}`;
  memoryStorage.set(backup.userId, backup);

  // Optional: If Vercel KV / Upstash Redis is configured
  const kvUrl = process.env.KV_REST_API_URL || process.env.UPSTASH_REDIS_REST_URL;
  const kvToken = process.env.KV_REST_API_TOKEN || process.env.UPSTASH_REDIS_REST_TOKEN;

  if (kvUrl && kvToken) {
    try {
      await fetch(`${kvUrl}/set/${encodeURIComponent(key)}`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${kvToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(backup),
      });
    } catch (e) {
      console.warn('Failed to persist to KV:', e);
    }
  }
}

async function getFromStorage(userId: string): Promise<UserBackup | null> {
  const key = `bloom:user:${userId}`;

  // Check KV / Upstash Redis first if configured
  const kvUrl = process.env.KV_REST_API_URL || process.env.UPSTASH_REDIS_REST_URL;
  const kvToken = process.env.KV_REST_API_TOKEN || process.env.UPSTASH_REDIS_REST_TOKEN;

  if (kvUrl && kvToken) {
    try {
      const res = await fetch(`${kvUrl}/get/${encodeURIComponent(key)}`, {
        headers: {
          Authorization: `Bearer ${kvToken}`,
        },
      });
      if (res.ok) {
        const json = (await res.json()) as { result?: string | UserBackup };
        if (json.result) {
          const parsed = typeof json.result === 'string' ? JSON.parse(json.result) : json.result;
          return parsed as UserBackup;
        }
      }
    } catch (e) {
      console.warn('Failed to fetch from KV:', e);
    }
  }

  return memoryStorage.get(userId) || null;
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  // CORS setup
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-User-Id');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  const userId =
    (req.headers['x-user-id'] as string) ||
    (req.query.userId as string) ||
    (req.query.telegramId as string) ||
    (req.body && (req.body.userId || req.body.telegramId));

  if (!userId) {
    return res.status(400).json({
      ok: false,
      error: 'userId or telegramId parameter is required',
    });
  }

  if (req.method === 'POST') {
    try {
      const body = typeof req.body === 'string' ? JSON.parse(req.body) : req.body;
      const backup: UserBackup = {
        userId: String(userId),
        updatedAt: Date.now(),
        profile: body.profile || {},
        favorites: Array.isArray(body.favorites) ? body.favorites : [],
        playlists: Array.isArray(body.playlists) ? body.playlists : [],
        level: body.level || {},
        stats: body.stats || {},
        follows: Array.isArray(body.follows) ? body.follows : [],
        dislikes: Array.isArray(body.dislikes) ? body.dislikes : [],
        settings: body.settings || {},
      };

      await saveToStorage(backup);

      return res.status(200).json({
        ok: true,
        message: 'Data successfully synchronized to cloud',
        updatedAt: backup.updatedAt,
        counts: {
          favorites: backup.favorites?.length ?? 0,
          playlists: backup.playlists?.length ?? 0,
          follows: backup.follows?.length ?? 0,
        },
      });
    } catch (err: any) {
      return res.status(500).json({
        ok: false,
        error: err.message || 'Failed to save user data',
      });
    }
  }

  if (req.method === 'GET') {
    try {
      const backup = await getFromStorage(String(userId));
      if (!backup) {
        return res.status(404).json({
          ok: false,
          error: 'No cloud backup found for this user',
        });
      }

      return res.status(200).json({
        ok: true,
        data: backup,
      });
    } catch (err: any) {
      return res.status(500).json({
        ok: false,
        error: err.message || 'Failed to load user data',
      });
    }
  }

  return res.status(405).json({ error: 'Method not allowed' });
}
