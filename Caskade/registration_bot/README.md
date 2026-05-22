# Registration Bot for Remnawave

Этот бот предназначен для автоматической регистрации пользователей в системе Remnawave и выдачи им ссылок на подписку.

## Возможности
-   Автоматическое создание пользователя в Remnawave через API.
-   Выдача ссылки на подписку.
-   Проверка существующей регистрации (повторная выдача ссылки).
-   База данных SQLite для учета пользователей.

## Настройка
1.  Создайте файл `.env` на основе `.env.example`.
2.  Укажите `BOT_TOKEN` (от @BotFather).
3.  Укажите `REMNWAVE_API_URL` и `REMNWAVE_API_TOKEN` (токен можно найти в настройках панели или в `.env` файле панели).

## Запуск через Docker
```bash
docker build -t registration-bot .
docker run -d --name registration-bot --env-file .env registration-bot
```

## Запуск локально
```bash
pip install -r requirements.txt
python main.py
```
