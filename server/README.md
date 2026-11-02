# Bloom Mobile — Vercel Serverless Backend

Серверная часть для мобильного плеера **Bloom** для безопасной авторизации через **Telegram** и **Яндекс Музыку**.

## Возможности

1. **Telegram Login Widget & HMAC Verification**:
   - Веб-интерфейс авторизации Telegram (`/api/telegram/widget`).
   - Криптографическая проверка HMAC-SHA256 подписи Telegram (`/api/telegram/verify`).
   - Автоматический редирект в мобильное приложение по диплинку `bloom://auth/telegram?...`.

2. **Yandex Music OAuth Bridge**:
   - Старт авторизации через Яндекс ID (`/api/yandex/login`).
   - Серверный обмен `authorization_code` на `access_token` с секретом приложения (`/api/yandex/callback`).
   - Передача токена в приложение через `bloom://auth/yandex?token=...`.

3. **Мониторинг**:
   - `/api/health` — проверка работоспособности сервиса.

---

## Быстрый деплой на Vercel

### Шаг 1: Подготовка переменных окружения

1. **Telegram Bot**:
   - Откройте [@BotFather](https://t.me/BotFather) в Telegram.
   - Создайте бота командой `/newbot` (например, `BloomMusicAuthBot`).
   - Скопируйте полученный `HTTP API Token` (это `TELEGRAM_BOT_TOKEN`).
   - Привяжите домен командой `/setdomain` у @BotFather к вашему Vercel-домену (например, `my-bloom.vercel.app`).

2. **Yandex OAuth Application** (опционально для веб-входа Яндекс):
   - Перейдите на [oauth.yandex.ru](https://oauth.yandex.ru/).
   - Создайте приложение с доступом к **Яндекс Музыке** (`music:read`, `music:write`).
   - Укажите Callback URL: `https://<ваш-домен-vercel>.vercel.app/api/yandex/callback`.
   - Скопируйте `Client ID` и `Client Secret`.

### Шаг 2: Деплой через Vercel CLI

```bash
cd server
npm install -g vercel  # если CLI еще не установлен
vercel login
vercel
```

При деплое укажите переменные окружения:
- `TELEGRAM_BOT_TOKEN`
- `TELEGRAM_BOT_NAME`
- `YANDEX_CLIENT_ID`
- `YANDEX_CLIENT_SECRET`
- `APP_DEEP_LINK_SCHEME` = `bloom://auth`

Либо задайте их в панели управления **Vercel Dashboard → Project Settings → Environment Variables**.
