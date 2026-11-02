import type { IncomingMessage, ServerResponse } from 'http';
import { URL } from 'url';
import { verifyTelegramHash } from './verify.js';

export default function handler(req: IncomingMessage, res: ServerResponse) {
  const host = req.headers.host || 'localhost';
  const currentUrl = new URL(req.url || '', `https://${host}`);
  const query = Object.fromEntries(currentUrl.searchParams.entries());

  const botToken = process.env.TELEGRAM_BOT_TOKEN;
  const scheme = process.env.APP_DEEP_LINK_SCHEME || 'bloom://auth';

  if (!query.hash || !botToken) {
    res.statusCode = 302;
    res.setHeader('Location', `${scheme}/telegram?error=missing_credentials`);
    res.end();
    return;
  }

  const isValid = verifyTelegramHash(query as any, botToken);
  if (!isValid) {
    res.statusCode = 302;
    res.setHeader('Location', `${scheme}/telegram?error=invalid_hash`);
    res.end();
    return;
  }

  // Build mobile app deep link
  const deepLink = new URL(`${scheme}/telegram`);
  for (const [k, v] of Object.entries(query)) {
    deepLink.searchParams.set(k, v);
  }

  // Render a transition page that automatically opens the deep link and provides a manual button
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.statusCode = 200;
  res.end(`<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Вход выполнен — Bloom</title>
  <style>
    body {
      background: #0D0E12;
      color: #F2F3F7;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      text-align: center;
      padding: 20px;
    }
    .box {
      background: #181920;
      border: 1px solid #262833;
      border-radius: 20px;
      padding: 32px 24px;
      max-width: 360px;
    }
    .btn {
      display: inline-block;
      margin-top: 20px;
      padding: 14px 28px;
      background: #3E8BF2;
      color: #fff;
      text-decoration: none;
      border-radius: 14px;
      font-weight: 600;
    }
  </style>
</head>
<body>
  <div class="box">
    <h2>✦ Вход подтверждён!</h2>
    <p style="color:#8E92A2;margin-top:8px;">Перенаправляем обратно в приложение Bloom...</p>
    <a id="link" href="${deepLink.toString()}" class="btn">Открыть Bloom</a>
  </div>
  <script>
    window.location.href = "${deepLink.toString()}";
  </script>
</body>
</html>`);
}
