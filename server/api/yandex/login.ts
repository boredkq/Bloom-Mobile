import type { IncomingMessage, ServerResponse } from 'http';
import { URL } from 'url';

export default function handler(req: IncomingMessage, res: ServerResponse) {
  const host = req.headers.host || 'localhost';
  const protocol = host.includes('localhost') ? 'http' : 'https';

  const clientId = process.env.YANDEX_CLIENT_ID;
  if (!clientId) {
    res.statusCode = 500;
    res.setHeader('Content-Type', 'application/json');
    res.end(
      JSON.stringify({
        error: 'YANDEX_CLIENT_ID is not configured in environment variables.',
      })
    );
    return;
  }

  const callbackUrl = `${protocol}://${host}/api/yandex/callback`;
  const yandexAuthUrl = new URL('https://oauth.yandex.ru/authorize');
  yandexAuthUrl.searchParams.set('response_type', 'code');
  yandexAuthUrl.searchParams.set('client_id', clientId);
  yandexAuthUrl.searchParams.set('redirect_uri', callbackUrl);
  yandexAuthUrl.searchParams.set('force_confirm', 'yes');

  res.statusCode = 302;
  res.setHeader('Location', yandexAuthUrl.toString());
  res.end();
}
