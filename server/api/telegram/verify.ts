import type { IncomingMessage, ServerResponse } from 'http';
import * as crypto from 'crypto';

interface TelegramAuthData {
  id: string | number;
  first_name: string;
  last_name?: string;
  username?: string;
  photo_url?: string;
  auth_date: string | number;
  hash: string;
}

export function verifyTelegramHash(data: TelegramAuthData, botToken: string): boolean {
  if (!data.hash || !botToken) return false;

  const secretKey = crypto.createHash('sha256').update(botToken).digest();

  const pairs: string[] = [];
  for (const [key, value] of Object.entries(data)) {
    if (key !== 'hash' && value !== undefined && value !== null) {
      pairs.push(`${key}=${value}`);
    }
  }

  pairs.sort();
  const dataCheckString = pairs.join('\n');

  const calculatedHash = crypto
    .createHmac('sha256', secretKey)
    .update(dataCheckString)
    .digest('hex');

  return calculatedHash.toLowerCase() === String(data.hash).toLowerCase();
}

export default async function handler(req: IncomingMessage, res: ServerResponse) {
  res.setHeader('Content-Type', 'application/json');

  if (req.method === 'OPTIONS') {
    res.statusCode = 200;
    res.end();
    return;
  }

  if (req.method !== 'POST') {
    res.statusCode = 405;
    res.end(JSON.stringify({ error: 'Method not allowed. Use POST.' }));
    return;
  }

  const botToken = process.env.TELEGRAM_BOT_TOKEN;
  if (!botToken) {
    res.statusCode = 500;
    res.end(
      JSON.stringify({
        error: 'TELEGRAM_BOT_TOKEN is not configured on Vercel environment variables.',
      })
    );
    return;
  }

  try {
    let body = '';
    for await (const chunk of req) {
      body += chunk;
    }

    const data: TelegramAuthData = JSON.parse(body);
    const isValid = verifyTelegramHash(data, botToken);

    if (!isValid) {
      res.statusCode = 401;
      res.end(JSON.stringify({ success: false, error: 'Invalid Telegram authentication signature (hash mismatch).' }));
      return;
    }

    // Check expiration (24 hours)
    const now = Math.floor(Date.now() / 1000);
    const authDate = Number(data.auth_date);
    if (now - authDate > 86400) {
      res.statusCode = 401;
      res.end(JSON.stringify({ success: false, error: 'Telegram authentication data has expired.' }));
      return;
    }

    res.statusCode = 200;
    res.end(
      JSON.stringify({
        success: true,
        user: {
          id: data.id,
          firstName: data.first_name,
          lastName: data.last_name || null,
          username: data.username || null,
          photoUrl: data.photo_url || null,
          authDate: data.auth_date,
        },
      })
    );
  } catch (err: any) {
    res.statusCode = 400;
    res.end(JSON.stringify({ success: false, error: err?.message || 'Invalid request body' }));
  }
}
