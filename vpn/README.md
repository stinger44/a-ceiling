# VPN — 4-слойная система обхода блокировок

Самодостаточная VPN-система с автоматическим переключением между уровнями защиты.
Работает даже при белых списках мобильных операторов РФ.

## Архитектура

```
Layer 0 (основной)
  Устройство ──VLESS Reality──► VPS Финляндия ──► Интернет
  DPI видит: HTTPS к www.microsoft.com

Layer 1 (IP заблокирован)
  Устройство ──HTTPS/WSS──► Cloudflare CDN ──► VPS ──► Интернет
  Работает: домашний Wi-Fi. НЕ работает: мобильный с белыми списками.

Layer 2 (белые списки мобильных операторов)
  Устройство ──VLESS Reality──► VM Yandex Cloud (РФ) ──► VPS ──► Интернет
  IP Yandex Cloud всегда в белом списке.

Layer 3 (аварийный, пока не нужен)
  Устройство ──WebRTC DataChannel──► VPS ──► Интернет
  Яндекс ВСЕГДА в белом списке.
```

## Требования

- VPS за рубежом (Финляндия, Швеция, Нидерланды). Рекомендуем Aeza — от 2€/мес.
- Домен в любой зоне (`.ru` подходит)
- Cloudflare аккаунт (бесплатно)
- Yandex Cloud аккаунт (для Layer 2)

## Быстрый старт

### 1. Подготовка конфигурации

```bash
cp .env.example .env
# Заполни .env своими данными
```

### 2. Установка на VPS (Layer 0 + Layer 1)

```bash
# Подключись к VPS по SSH
ssh root@YOUR_VPS_IP

# Скопируй install.sh на сервер и запусти
bash install.sh
```

Скрипт установит 3X-UI, включит BBR и выведет все ключи.
Сохрани вывод — там будут credentials для панели и Reality-ключи.

### 3. Настройка 3X-UI (через веб-панель)

Открой `http://YOUR_VPS_IP:54321` в браузере.

Создай три inbound-а (кнопка «Добавить инбаунд»):

**Inbound 1 — Layer 0, основной:**
- Протокол: `vless`
- Порт: `443`
- Клиент: UUID из `vpn-credentials.txt`, Flow: `xtls-rprx-vision`
- Network: `tcp`, Security: `Reality`
- SNI: `www.microsoft.com`
- Private Key и Short ID — из `vpn-credentials.txt`

**Inbound 2 — Layer 0, резерв:**
- Порт: `8443`, SNI: `dl.google.com`
- Остальное как в Inbound 1

**Inbound 3 — Layer 1, Cloudflare WebSocket:**
- Порт: `2053`
- Network: `ws`, Path: `/vpn-ws`
- Security: `none` (TLS терминируется на Cloudflare)

### 4. Настройка Cloudflare (Layer 1)

1. Добавь домен на Cloudflare
2. DNS A-запись: `vpn.yourdomain.ru` → `YOUR_VPS_IP`, Proxy: **оранжевое облако (ON)**
3. SSL/TLS режим: **Full**
4. В панели Cloudflare: Network → WebSockets → **ON**

### 5. Деплой relay в Yandex Cloud (Layer 2)

```bash
# Установи Yandex Cloud CLI, если ещё нет
curl -sSL https://storage.yandexcloud.net/yandexcloud-yc/install.sh | bash
yc init

# Деплой relay VM
bash relay/deploy-relay-yc.sh
```

### 6. Импорт профиля в Hiddify

Открой `routing/hiddify-profile.json` и замени плейсхолдеры своими данными:

```bash
# На Windows (PowerShell):
(Get-Content routing\hiddify-profile.json) `
  -replace '\$\{VPS_IP\}', 'YOUR_VPS_IP' `
  -replace '\$\{VLESS_UUID\}', 'YOUR_UUID' `
  -replace '\$\{REALITY_PUBLIC_KEY\}', 'YOUR_PUBLIC_KEY' `
  -replace '\$\{REALITY_SHORT_ID\}', 'YOUR_SHORT_ID' `
  -replace '\$\{RELAY_IP\}', 'YOUR_RELAY_IP' `
  -replace '\$\{RELAY_PUBLIC_KEY\}', 'YOUR_RELAY_PUBLIC_KEY' `
  -replace '\$\{RELAY_SHORT_ID\}', 'YOUR_RELAY_SHORT_ID' `
  -replace '\$\{DOMAIN\}', 'YOUR_DOMAIN' |
  Set-Content routing\hiddify-profile-filled.json
```

Импортируй `hiddify-profile-filled.json` в Hiddify через «Добавить профиль».

### 7. Проверка всех слоёв

```bash
bash scripts/check-layers.sh
```

## Split Routing — что идёт напрямую

Следующие ресурсы всегда идут без VPN (российский IP):
- `*.ru`, `*.рф`, `*.su` домены
- Яндекс, VK, Mail.ru
- Госуслуги
- Крупные российские банки
- Российские IP-подсети (RIPE NCC)

## Бюджет

| Ресурс | Стоимость |
|---|---|
| VPS Финляндия (Aeza) | ~265 ₽/мес |
| Домен .ru | ~100 ₽/год |
| Cloudflare | Бесплатно |
| Yandex Cloud relay | ~400-500 ₽/мес |
| Hiddify (Windows/Android) | Бесплатно |
| Shadowrocket (iOS) | $2.99 разово |

## Структура файлов

```
vpn/
├── .env.example          # Шаблон переменных окружения
├── server/
│   ├── install.sh        # Установка на VPS
│   ├── xray-config.json  # Эталонный конфиг Xray
│   └── sysctl-bbr.conf   # BBR оптимизация
├── relay/
│   ├── deploy-relay-yc.sh    # Деплой VM в Yandex Cloud
│   ├── setup-relay.sh        # Установка Xray на relay
│   └── relay-xray-config.json
├── webrtc/
│   ├── tunnel-server.js  # Node.js сервер (на VPS)
│   ├── tunnel-client.html # Браузерный клиент
│   └── package.json
├── routing/
│   ├── hiddify-profile.json
│   └── shadowrocket-profile.conf
└── scripts/
    ├── check-layers.sh      # Диагностика
    ├── generate-keys.sh     # Генерация UUID/ключей
    └── update-ru-cidr.sh    # Обновление российских подсетей
```

## FAQ

**Q: Что делать если заблокировали IP VPS?**
A: Hiddify автоматически переключится на Cloudflare (Layer 1) или Yandex Cloud relay (Layer 2). Можно также пересоздать VPS — это занимает 5 минут.

**Q: Как часто нужно обновлять список российских подсетей?**
A: Раз в месяц достаточно. Запусти `bash scripts/update-ru-cidr.sh`.

**Q: WebRTC туннель — когда разворачивать?**
A: Только если Layer 0, 1 и 2 одновременно перестанут работать. Инструкция в `webrtc/README.md`.
