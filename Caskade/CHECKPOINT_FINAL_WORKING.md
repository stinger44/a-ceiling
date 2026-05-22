# Caskade VPN — Финальный чекпоинт

# Дата: 06.05.2026

# Статус: ✅ РАБОТАЕТ (Entry нода перенесена на YC сервер 111.88.249.82)

## Архитектура

```
Клиент (ограничен белым списком)
  │  VLESS + Reality (TLS маскировка)
  │  Домен: alphaceiling23.ru:443
  ▼
┌───────────────────────────────────────────────┐
│  yc — YC Entry                                │
│  IP: 111.88.249.82                            │
│  SSH: yc (порт 22)                            │
│  Xray: VLESS_YC_ENTRY, порт 443              │
│  Reality dest: 127.0.0.1:4433                 │
│  nginx на 4433 — Let's Encrypt cert           │
└───────┬───────────────────────────────────────┘
        │                               
        │ VLESS plain TCP               
        │ UUID: a1b2c3d4-...            
        │ Порт: 2223                    
        ▼                               
┌──────────────────────────────┐       
│ remna — panel + exit         │       
│ IP: 91.184.243.118           │       
│ SSH: remna (22222)           │       
│ xray-transit                 │       
└─────────┬────────────────────┘       
          │ DIRECT → freedom              
          ▼                               
       Интернет
```

## Серверы

| Роль                    | SSH алиас | IP               | Домен             | SSH порт |
|-------------------------|-----------|------------------|-------------------|----------|
| Remnawave панель + Exit | remna     | 91.184.243.118   | panelhide.su      | 22222    |
| YC Entry                | yc        | 111.88.249.82    | alphaceiling23.ru | 22       |

> aesa exit и node_e выведены из эксплуатации.

## DNS

- Домен: **alphaceiling23.ru**
- Провайдер: **Cloudflare**
- A запись: `111.88.249.82` (yc)
- Прокси: выключен (DNS only) — обязательно для Reality

## Ключи и секреты

| Параметр              | Значение                                         |
|-----------------------|--------------------------------------------------|
| Reality private key   | SB1BD0THeV9Ravrbm3OWvc4-_jWlh7YRpEkztv_nUG8      |
| Reality public key    | zKq30UObQcXEENWkRK8kXgDyqX06KNvXH6ukN7bSZxo      |
| Reality short ID      | 1a2b3c4d                                         |
| Transit VLESS UUID    | a1b2c3d4-e5f6-7890-abcd-ef1234567890             |
| Subscription token    | jk99Ho0Q5XBoPBfq                                 |
| Node UUID (Списки)    | 1fe06f8f-2f9f-4656-ba83-56e920066959             |

## Подписка для клиентов

```
https://panelhide.su/api/sub/jk99Ho0Q5XBoPBfq
```

## Remnawave Panel

- **Нода:** `Списки` → адрес `111.88.249.82:2222` → профиль `YC-Entry-Cascade`
- **Профиль `YC-Entry-Cascade`:** inbound `VLESS_YC_ENTRY`, прямая маршрутизация на `remna` exit (91.184.243.118)
- **Выходные ноды:** `aeza pink` (remna)
- **Squad:** `Default-Squad` → inbound `VLESS_YC_ENTRY`

## Сертификаты

| Сервер | Сертификат | Путь | Истекает |
|--------|-----------|------|----------|
| yc (порт 4433) | Let's Encrypt | `/etc/letsencrypt/live/alphaceiling23.ru/` | 2026-08-04 |

Auto-renewal настроен certbot'ом.

## Диагностика

```bash
# Статус entry ноды
ssh yc "sudo docker logs remnawave-node --tail 20"

# Проверить что 443 слушает
ssh yc "ss -tlnp | grep ':443 '"

# Статус в панели
ssh remna "docker exec remnawave-db psql -U postgres -d postgres -t -c 'SELECT name, address, is_connected FROM nodes'"

# Лог transit (видно реальный трафик)
ssh remna "docker logs xray-transit --tail 20"
```

## Откат (если нужно вернуть на node_e)

Откат более не поддерживается. node_e и aesa выведены из конфигурации.

## Файлы проекта

| Файл                              | Назначение                                              |
|-----------------------------------|---------------------------------------------------------|
| setup_nginx_4433_yc.sh            | Настройка nginx:4433 на yc (Reality маскировка)         |
| migrate_entry_node.sh             | Мастер-скрипт миграции (архив)                          |
| rollback_entry_node.sh            | Быстрый откат на node_e                                 |
| switch_node_address_to_yc.sql     | SQL смены адреса ноды в панели                          |
| apply_leastping_balancer.sql      | SQL настройки leastPing балансировки                    |
| rollback_cascade_config.sql       | SQL отката к конфигу без балансировщика                 |
| deploy_node_f.sh                  | Мастер-скрипт развёртывания aesa                        |

## История изменений

- **06.05.2026** — Перенесена entry нода с node_e (153.80.247.239) на yc (111.88.249.82).
  Настроен nginx:4433, получен Let's Encrypt сертификат. node_e остановлен.
- **06.05.2026** — Исправлен SECRET_KEY на aesa. Нода aesa exit Online.
- **06.05.2026** — Внедрена умная балансировка leastPing с observatory.
- **06.05.2026** — Синхронизированы UUID транзитных туннелей.
- **28.04.2026** — Развёрнут xray-transit на node_d:2223. Смена на VLESS.

## Telegram-бот (Admin Web)

- **Версия бота:** Remnawave Admin Web + Bot (Case211)
- **Домен панели:** `https://admin.panelhide.su` (HTTPS через Cloudflare Proxy)
- **Порт Web Frontend:** 3010 (привязан только к 127.0.0.1)
- **Порт Web Backend:** 8081
- **БД бота:** PostgreSQL (`remnawave-admin-db`)
- **Telegram Bot:** `@watcerbot`
- **Команды бота:** `/start` (админское меню), `/health` (проверка статуса)
