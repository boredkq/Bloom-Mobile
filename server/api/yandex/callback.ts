import type { IncomingMessage, ServerResponse } from 'http';
import { URL } from 'url';

export default async function handler(req: IncomingMessage, res: ServerResponse) {
  const host = req.headers.host || 'localhost';
  const protocol = host.includes('localhost') ? 'http' : 'https';
  const currentUrl = new URL(req.url || '', `${protocol}://${host}`);

  const code = currentUrl.searchParams.get('code');
  const error = currentUrl.searchParams.get('error');

  const clientId = process.env.YANDEX_CLIENT_ID;
  const clientSecret = process.env.YANDEX_CLIENT_SECRET;
  const scheme = process.env.APP_DEEP_LINK_SCHEME || 'bloom://auth';

  if (error || !code) {
    res.statusCode = 302;
    res.setHeader('Location', `${scheme}/yandex?error=${encodeURIComponent(error || 'missing_code')}`);
    res.end();
    return;
  }

  if (!clientId || !clientSecret) {
    res.statusCode = 500;
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify({ error: 'Yandex OAuth credentials not configured on server.' }));
    return;
  }

  try {
    const callbackUrl = `${protocol}://${host}/api/yandex/callback`;
    const bodyParams = new URLSearchParams({
      grant_type: 'authorization_code',
      code,
      client_id: clientId,
      client_secret: clientSecret,
      redirect_uri: callbackUrl,
    });

    const tokenResponse = await fetch('https://oauth.yandex.ru/token', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: bodyParams.toString(),
    });

    const data = await tokenResponse.json() as any;

    if (!tokenResponse.ok || !data.access_token) {
      const errDetail = data.error_description || data.error || 'token_exchange_failed';
      res.statusCode = 302;
      res.setHeader('Location', `${scheme}/yandex?error=${encodeURIComponent(errDetail)}`);
      res.end();
      return;
    }

    const token = data.access_token;
    const deepLink = `${scheme}/yandex?token=${encodeURIComponent(token)}`;

    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.statusCode = 200;
    res.end(`<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Яндекс Музыка подключена — Bloom</title>
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
      background: #FC3F1D;
      color: #fff;
      text-decoration: none;
      border-radius: 14px;
      font-weight: 600;
    }
  </style>
</head>
<body>
  <div class="box">
    <h2>🟡 Яндекс Музыка подключена!</h2>
    <p style="color:#8E92A2;margin-top:8px;">Возвращаем вас в Bloom...</p>
    <a id="link" href="${deepLink}" class="btn">Открыть Bloom</a>
  </div>
  <script>
    window.location.href = "${deepLink}";
  </script>
</body>
</html>`);
  } catch (err: any) {
    res.statusCode = 500;
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify({ error: err?.message || 'Internal server error' }));
  }
}
