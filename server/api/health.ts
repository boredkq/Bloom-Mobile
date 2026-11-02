import type { IncomingMessage, ServerResponse } from 'http';

export default function handler(req: IncomingMessage, res: ServerResponse) {
  res.setHeader('Content-Type', 'application/json');
  res.statusCode = 200;
  res.end(
    JSON.stringify({
      status: 'ok',
      service: 'Bloom Mobile Serverless Backend',
      version: '1.0.0',
      timestamp: new Date().toISOString(),
      features: ['telegram_auth', 'yandex_oauth', 'deep_linking'],
    })
  );
}
