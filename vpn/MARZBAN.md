# Marzban — панель управления VPN-сервером

Marzban — это веб-панель для управления прокси-пользователями на базе Xray-core.
Поддерживает VLESS, VMess, Trojan, Shadowsocks. Работает с Hiddify, Shadowrocket и любым XRAY-клиентом.

> 💻 **Все локальные команды выполняются в Windows PowerShell.**
> После подключения к VPS по SSH — команды вводятся там же, в том же окне PowerShell (уже на Linux).

## Архитектура

```
Клиент (Hiddify / Shadowrocket)
    │
    ▼
Marzban Panel (VPS) — управление пользователями, ссылками, лимитами
    │
    ├── Inbound: VLESS + Reality (Layer 0, основной, порт 4500)
    ├── Inbound: VLESS + WS + TLS через Cloudflare (Layer 1)
    └── Inbound: Trojan + TCP (запасной)
    │
    ▼
 Xray-core на VPS ──► Интернет
```

## Требования

- VPS за рубежом с Ubuntu 22.04 / Debian 12 (минимум 1 CPU, 512 MB RAM)
- Домен (`.ru` подходит), добавленный в Cloudflare
- Docker и Docker Compose (устанавливаются автоматически)
- Cloudflare аккаунт (бесплатно)
- Windows 10/11 с OpenSSH (встроен по умолчанию, проверь: `Get-WindowsCapability -Online -Name OpenSSH*`)

## Быстрый старт

### 0. Проверка OpenSSH в PowerShell

```powershell
# [PowerShell] — Убедись, что SSH клиент установлен
Get-WindowsCapability -Online -Name OpenSSH.Client*

# Если статус "NotPresent" — установи:
Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
```

### 1. Подключение к VPS и установка Marzban

```powershell
# [PowerShell] — Подключись к VPS по SSH
ssh root@193.233.137.187
```

После подключения ты окажешься внутри терминала VPS (Linux).
Все следующие команды в этом разделе вводятся **там же, в том же окне**.

```bash
# [VPS] — Официальный установщик Marzban
sudo bash -c "$(curl -sL https://github.com/Gozargah/Marzban-scripts/raw/master/marzban.sh)" @ install
```

После установки панель запустится на `http://127.0.0.1:8000` (локально, без SSL).
Логи и конфиги хранятся в `/opt/marzban/`.

> ⚠️ **Панель пока недоступна извне** — без SSL Marzban слушает только localhost.
> Для первичного доступа используй SSH-туннель (см. ниже), а затем настрой SSL.

### 2. Создание администратора

```bash
# [VPS] — Создать sudo-администратора панели
marzban cli admin create --sudo
```

Введи логин и пароль — они используются для входа в веб-панель.

### 3. Первый вход через SSH-туннель

Пока SSL не настроен, Marzban доступен только через localhost. Открой **новое окно PowerShell** и создай туннель:

```powershell
# [PowerShell — новое окно] — SSH-туннель для доступа к панели
ssh -L 8000:localhost:8000 root@193.233.137.187
```

Теперь открой `http://127.0.0.1:8000/dashboard/` в браузере и войди под созданным аккаунтом.

> 💡 Туннель нужен только до настройки SSL. После шага 6 панель будет доступна напрямую.

### 4. Настройка Xray (inbound-ы)

Открой `Настройки → Конфигурация Xray` (или `/opt/marzban/xray_config.json`).

Добавь inbound-ы вручную или используй готовый шаблон ниже.

**Inbound 1 — VLESS Reality (основной, Layer 0):**

> ⚠️ Порт 443 заблокирован на уровне провайдера. Используется порт **4500** для VPN-трафика (UDP/TCP, обычно разрешён как IPsec/IKEv2 — не вызывает подозрений у DPI). Панель управления работает на порту **8443**.

```json
{
  "tag": "vless-reality",
  "port": 4500,
  "protocol": "vless",
  "settings": {
    "clients": [],
    "decryption": "none"
  },
  "streamSettings": {
    "network": "tcp",
    "security": "reality",
    "realitySettings": {
      "dest": "www.microsoft.com:443",
      "serverNames": ["www.microsoft.com"],
      "privateKey": "YOUR_PRIVATE_KEY",
      "shortIds": ["YOUR_SHORT_ID"]
    }
  },
  "sniffing": { "enabled": true, "destOverride": ["http", "tls"] }
}
```

**Inbound 2 — VLESS WebSocket для Cloudflare (Layer 1):**

```json
{
  "tag": "vless-ws-cloudflare",
  "port": 2053,
  "protocol": "vless",
  "settings": {
    "clients": [],
    "decryption": "none"
  },
  "streamSettings": {
    "network": "ws",
    "security": "none",
    "wsSettings": { "path": "/vpn-ws" }
  }
}
```

Генерация ключей для Reality:

```bash
# [VPS] — Сгенерировать пару ключей x25519
docker exec marzban-marzban-1 xray x25519
```

Сохрани `privateKey` и `publicKey` из вывода — они вставляются в конфиг выше.

### 5. Настройка DNS (привязка домена к VPS)

Домен `alphaceiling23.ru` нужно направить на IP-адрес VPS. Для этого используем Cloudflare как DNS-провайдер (бесплатно, + нужен для Layer 1).

#### 5.1. Добавить домен в Cloudflare

1. Зайди на [dash.cloudflare.com](https://dash.cloudflare.com) → **Add a site** → введи `alphaceiling23.ru`
2. Выбери план **Free** → нажми **Continue**
3. Cloudflare покажет два NS-сервера (например, `anna.ns.cloudflare.com` и `bob.ns.cloudflare.com`). **Скопируй их.**

#### 5.2. Сменить NS-серверы у регистратора домена

Зайди в панель управления доменом (там, где покупал `alphaceiling23.ru`) и замени текущие NS-серверы на те, что дал Cloudflare:

```
NS 1: (значение из Cloudflare, например anna.ns.cloudflare.com)
NS 2: (значение из Cloudflare, например bob.ns.cloudflare.com)
```

> ⏳ Смена NS может занять от **10 минут до 48 часов**. Обычно — 15–30 минут.
> Cloudflare покажет статус домена как **Active**, когда NS подхватятся.

#### 5.3. Создать DNS-записи в Cloudflare

В Cloudflare → DNS → Records → **Add record**:

| Тип | Имя | Содержимое | Proxy |
|-----|------|-----------|-------|
| A | `panel` | `193.233.137.187` | ❌ DNS only (серое облако) |
| A | `vpn` | `193.233.137.187` | ✅ Proxied (оранжевое облако) |

> ⚠️ Для `panel` — **обязательно серое облако (DNS only)**! Иначе Certbot не сможет получить сертификат, а прямое подключение к панели не будет работать.
> Для `vpn` — оранжевое облако, трафик пойдёт через Cloudflare CDN (Layer 1).

Проверь, что DNS работает:

```powershell
# [PowerShell] — Проверить, что домен указывает на VPS
nslookup panel.alphaceiling23.ru
# Должен показать 193.233.137.187
```

### 6. Настройка TLS-сертификата (HTTPS для панели)

> ⚠️ Порт 443 заблокирован. Панель поднимается на порту **8443**, VPN-трафик идёт через порт **4500**.
> Certbot использует порт 80 для валидации, затем панель запускается на 8443 с TLS.
> Сертификаты нужно скопировать в `/var/lib/marzban/certs/` — иначе Docker-контейнер их не увидит.

```bash
# [VPS] — Открой порт 80 временно (для получения сертификата)
ufw allow 80/tcp

# [VPS] — Установи Certbot
apt install certbot -y

# [VPS] — Останови Marzban чтобы освободить порты
marzban stop

# [VPS] — Получи сертификат
certbot certonly --standalone --http-01-port 80 -d panel.alphaceiling23.ru
```

> 💡 Если certbot выдаёт ошибку — убедись что:
> 1. DNS уже обновился (`nslookup panel.alphaceiling23.ru` показывает `193.233.137.187`)
> 2. Порт 80 открыт (`ufw status`)
> 3. Ничего не занимает порт 80 (`ss -tlnp | grep :80`)

После успешного получения сертификата — **закрой порт 80** (он больше не нужен):

```bash
# [VPS] — Закрыть порт 80
ufw delete allow 80/tcp
```

Настрой `.env` — открой файл:

```bash
# [VPS] — Открыть файл настроек
nano /opt/marzban/.env
```

Скопируй сертификаты в папку, доступную Docker-контейнеру:

```bash
# [VPS] — Скопировать сертификаты в том Marzban
mkdir -p /var/lib/marzban/certs/
cp /etc/letsencrypt/live/panel.alphaceiling23.ru/fullchain.pem /var/lib/marzban/certs/
cp /etc/letsencrypt/live/panel.alphaceiling23.ru/privkey.pem /var/lib/marzban/certs/
```

Добавь или измени эти строки в `.env` (⚠️ **именно эти переменные**, не `SSL_CERT_FILE`):

```bash
UVICORN_SSL_CERTFILE=/var/lib/marzban/certs/fullchain.pem
UVICORN_SSL_KEYFILE=/var/lib/marzban/certs/privkey.pem
UVICORN_PORT=8443
UVICORN_HOST=0.0.0.0
```

Или одной командой (если `.env` ещё пустой или ты уверен что этих строк там нет):

```bash
# [VPS] — Дописать переменные в .env
cat >> /opt/marzban/.env << 'EOF'
UVICORN_SSL_CERTFILE=/var/lib/marzban/certs/fullchain.pem
UVICORN_SSL_KEYFILE=/var/lib/marzban/certs/privkey.pem
UVICORN_PORT=8443
UVICORN_HOST=0.0.0.0
EOF
```

> ⚠️ Порт **4500** занят VPN-трафиком (VLESS Reality), поэтому панель использует **8443**.

Открой порты на файрволле VPS:

```bash
# [VPS] — Открыть порты (панель + VPN)
ufw allow 4500/tcp
ufw allow 4500/udp
ufw allow 8443/tcp
ufw allow 2053/tcp
ufw reload
```

Запусти Marzban:

```bash
# [VPS] — Запустить Marzban с новыми настройками
marzban restart
```

Проверь логи — должно быть `Uvicorn running on https://0.0.0.0:8443`:

```bash
# [VPS] — Проверить что панель поднялась с SSL
marzban logs
```

✅ Панель теперь доступна по адресу: **`https://panel.alphaceiling23.ru:8443/dashboard/`**

### 7. Настройка Cloudflare для Layer 1 (CDN-фронтинг)

DNS-запись `vpn.alphaceiling23.ru` уже создана в шаге 5.3 с оранжевым облаком. Осталось настроить:

1. В Cloudflare → **SSL/TLS** → режим: **Full**
2. В Cloudflare → **Network** → WebSockets → **ON**
3. В Cloudflare → **SSL/TLS** → Edge Certificates → Minimum TLS Version: **TLS 1.2**

Трафик будет идти: `Клиент → Cloudflare → VPS:2053 → Xray`

### 8. Создание пользователя

В веб-панели: вкладка **Пользователи → Добавить пользователя**.

- Имя: любое
- Лимит трафика: по желанию (0 = безлимит)
- Дата истечения: по желанию
- Inbound-ы: выбери оба (vless-reality, vless-ws-cloudflare)

Панель автоматически сгенерирует ссылки для подключения.

### 9. Подключение клиента (Hiddify)

На странице пользователя нажми **«Копировать ссылку подписки»**.

В Hiddify: **Добавить профиль → Вставить URL подписки**.

Hiddify автоматически импортирует все inbound-ы и настроит переключение между слоями.

### 10. Проверка работы

```powershell
# [PowerShell] — Статус контейнеров через SSH (не выходя из Windows)
ssh root@193.233.137.187 "marzban status"

# [PowerShell] — Логи в реальном времени
ssh root@193.233.137.187 "marzban logs"

# [PowerShell] — Проверка подключения через SOCKS5 (нужен curl.exe)
# Установи curl: winget install curl.se.curl
curl.exe -x socks5h://193.233.137.187:10808 https://api.ipify.org
```

Или зайди по SSH и проверь изнутри:

```bash
# [VPS] — Проверка через curl внутри VPS
curl https://api.ipify.org
```

## Управление пользователями через CLI

```powershell
# [PowerShell] — Все команды управления через SSH одной строкой

# Список пользователей
ssh root@193.233.137.187 "marzban cli user list"

# Создать пользователя
ssh root@193.233.137.187 "marzban cli user create --username alice --traffic-limit 50 --expire 30"

# Сбросить трафик пользователя
ssh root@193.233.137.187 "marzban cli user reset-usage --username alice"

# Удалить пользователя
ssh root@193.233.137.187 "marzban cli user delete --username alice"
```

## Обновление Marzban

```powershell
# [PowerShell]
ssh root@193.233.137.187 "marzban update"
```

## Бюджет

| Ресурс | Стоимость |
|---|---|
| VPS Финляндия (Aeza) | ~265 ₽/мес |
| Домен .ru | ~100 ₽/год |
| Cloudflare | Бесплатно |
| Marzban | Бесплатно (open source) |
| Hiddify (Windows/Android) | Бесплатно |
| Shadowrocket (iOS) | $2.99 разово |

## Структура файлов

```
/opt/marzban/
├── .env                  # Основные настройки (порты, TLS, БД)
├── docker-compose.yml    # Конфигурация Docker
├── xray_config.json      # Конфиг Xray-core (inbound-ы)
└── mysql/                # База данных (пользователи, ключи)
```

## FAQ

**Q: Порт 443 заблокирован провайдером — что делать?**
A: Используй порт **4500** — он стандартно разрешён для IPsec/IKEv2 и редко блокируется DPI.
- В `xray_config.json`: `"port": 4500` в inbound VLESS Reality
- В `/opt/marzban/.env`: `UVICORN_PORT=4500`
- На файрволле: `ufw allow 4500/tcp` затем `ufw allow 4500/udp`
- Клиенту (Hiddify/Shadowrocket): обновить подписку — порт подтянется автоматически

Альтернативные «безопасные» порты если 4500 тоже заблокируют: **8443, 2096, 2087, 2083** (разрешены Cloudflare для HTTPS).

**Q: Marzban стартует на 127.0.0.1 и недоступен извне?**
A: Без SSL Marzban принудительно слушает только localhost. Убедись что в `.env` прописаны **правильные** переменные:
```
UVICORN_SSL_CERTFILE=/etc/letsencrypt/live/panel.alphaceiling23.ru/fullchain.pem
UVICORN_SSL_KEYFILE=/etc/letsencrypt/live/panel.alphaceiling23.ru/privkey.pem
```
⚠️ Переменные `SSL_CERT_FILE` / `SSL_KEY_FILE` — **НЕ работают**. Marzban их не читает.

**Q: Как продлить SSL-сертификат?**
A: Certbot добавляет cron-задачу автоматически, но порт 80 должен быть временно открыт. Проверить и продлить вручную:
```bash
ufw allow 80/tcp
marzban stop
certbot renew
ufw delete allow 80/tcp
marzban restart
```

**Q: Как добавить ещё один сервер (node)?**
A: Используй [Marzban-node](https://github.com/Gozargah/Marzban-node) — устанавливается на второй VPS, подключается к основной панели. Все пользователи работают через оба сервера автоматически.

**Q: Потерял пароль администратора?**

```powershell
# [PowerShell]
ssh root@193.233.137.187 "marzban cli admin update --username YOUR_ADMIN --password NEW_PASSWORD"
```

**Q: Как настроить автоматическое продление сертификата?**
A: Создай скрипт, который откроет порт 80, продлит сертификат и перезапустит Marzban:

```bash
# [VPS] — Создать скрипт автопродления
cat > /opt/marzban/renew-cert.sh << 'EOF'
#!/bin/bash
ufw allow 80/tcp
marzban stop
certbot renew --quiet
ufw delete allow 80/tcp
marzban restart
EOF
chmod +x /opt/marzban/renew-cert.sh

# [VPS] — Добавить в cron (раз в 2 месяца)
(crontab -l 2>/dev/null; echo "0 3 1 */2 * /opt/marzban/renew-cert.sh") | crontab -
```

Проверить текущий cron:
```bash
crontab -l
```

**Q: Работает ли Marzban с Outline / ShadowBox?**
A: Нет, Outline использует собственный протокол. Marzban — для VLESS/VMess/Trojan/SS через Xray.

**Q: Как смотреть статистику трафика?**
A: В веб-панели на вкладке **Пользователи** видно потребление трафика. Полная статистика — в разделе **Нода**.

**Q: Как установить curl.exe для проверки из PowerShell?**

```powershell
# [PowerShell] — Установить curl через winget (встроен в Windows 10/11)
winget install curl.se.curl
```
