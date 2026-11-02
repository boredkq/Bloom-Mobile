import type { IncomingMessage, ServerResponse } from 'http';

export default function handler(req: IncomingMessage, res: ServerResponse) {
  res.setHeader('Content-Type', 'text/html; charset=utf-8');

  const botName = process.env.TELEGRAM_BOT_NAME || 'BloomMusicAuthBot';
  const scheme = process.env.APP_DEEP_LINK_SCHEME || 'bloom://auth';

  const html = `<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Bloom — Вход через Telegram</title>
  <style>
    :root {
      --bg: #0D0E12;
      --card: #181920;
      --accent: #3E8BF2;
      --text: #F2F3F7;
      --muted: #8E92A2;
      --border: #262833;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      background: var(--bg);
      color: var(--text);
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 20px;
    }
    .card {
      background: var(--card);
      border: 1px solid var(--border);
      border-radius: 24px;
      padding: 36px 28px;
      width: 100%;
      max-width: 400px;
      text-align: center;
      box-shadow: 0 16px 40px rgba(0,0,0,0.5);
    }
    .logo {
      width: 64px;
      height: 64px;
      margin: 0 auto 16px;
      background: linear-gradient(135deg, #3E8BF2, #8A4EF2);
      border-radius: 18px;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 32px;
      box-shadow: 0 8px 24px rgba(62, 139, 242, 0.4);
    }
    h1 {
      font-size: 24px;
      font-weight: 700;
      margin-bottom: 8px;
      letter-spacing: -0.5px;
    }
    p {
      color: var(--muted);
      font-size: 14px;
      line-height: 1.5;
      margin-bottom: 28px;
    }
    .widget-container {
      display: flex;
      justify-content: center;
      margin-bottom: 24px;
      min-height: 48px;
    }
    .back-btn {
      display: inline-block;
      margin-top: 14px;
      color: var(--muted);
      text-decoration: none;
      font-size: 13px;
      transition: color 0.2s;
    }
    .back-btn:hover { color: var(--text); }
    .status-msg {
      margin-top: 16px;
      font-size: 14px;
      color: var(--accent);
      display: none;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="logo">✦</div>
    <h1>Вход в Bloom</h1>
    <p>Подключите профиль Telegram, чтобы синхронизировать музыку и открывать треки от друзей.</p>
    
    <div class="widget-container">
      <script 
        async 
        src="https://telegram.org/js/telegram-widget.js?22" 
        data-telegram-login="${botName}" 
        data-size="large" 
        data-radius="12" 
        data-auth-url="/api/telegram/callback" 
        data-request-access="write">
      </script>
    </div>

    <div id="status" class="status-msg">Авторизация подтверждена. Возвращаем в приложение...</div>

    <a href="${scheme}/cancel" class="back-btn">← Вернуться в Bloom</a>
  </div>
</body>
</html>`;

  res.statusCode = 200;
  res.end(html);
}
