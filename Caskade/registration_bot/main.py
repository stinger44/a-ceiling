import asyncio
import logging
import os
import secrets
import string
from datetime import datetime, timedelta
from typing import Optional

import aiohttp
from aiogram import Bot, Dispatcher, types, F
from aiogram.filters import Command
from aiogram.utils.keyboard import InlineKeyboardBuilder
from dotenv import load_dotenv
from sqlmodel import Field, SQLModel, create_all, Session, create_engine, select

# Load environment
load_dotenv()

# Configuration
BOT_TOKEN = os.getenv("BOT_TOKEN")
API_URL = os.getenv("REMNWAVE_API_URL", "https://panelhide.su")
API_TOKEN = os.getenv("REMNWAVE_API_TOKEN")
TRIAL_DAYS = int(os.getenv("DEFAULT_TRIAL_DAYS", "30"))
SUB_DOMAIN = os.getenv("SUB_DOMAIN", "sub.panelhide.su/api/sub")
SQUAD_UUID = os.getenv("SQUAD_UUID")
DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./bot.db")

# Models
class User(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    tg_id: int = Field(unique=True, index=True)
    username: str
    remna_uuid: Optional[str] = None
    remna_short_uuid: Optional[str] = None
    registered_at: datetime = Field(default_factory=datetime.utcnow)

# Database
engine = create_engine(DATABASE_URL)

def create_db_and_tables():
    SQLModel.metadata.create_all(engine)

# Remnawave API Client
class RemnaAPI:
    def __init__(self, base_url: str, token: str):
        self.base_url = base_url.rstrip("/")
        self.headers = {"Authorization": f"Bearer {token}"}

    async def create_user(self, username: str, expire_days: int, squad_uuid: Optional[str] = None):
        expire_at = (datetime.utcnow() + timedelta(days=expire_days)).isoformat() + "Z"
        password = ''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(12))
        
        payload = {
            "username": username,
            "password": password,
            "role": "USER",
            "status": "ACTIVE",
            "trafficLimit": 0,
            "trafficLimitResetStrategy": "NONE",
            "expireAt": expire_at
        }
        
        if squad_uuid:
            payload["squadUuid"] = squad_uuid
        
        async with aiohttp.ClientSession() as session:
            async with session.post(f"{self.base_url}/api/users", json=payload, headers=self.headers) as resp:
                if resp.status == 201:
                    return await resp.json()
                else:
                    text = await resp.text()
                    logging.error(f"Failed to create user: {resp.status} - {text}")
                    return None

    async def get_subscription(self, user_uuid: str):
        async with aiohttp.ClientSession() as session:
            async with session.get(f"{self.base_url}/api/subscriptions/by-uuid/{user_uuid}", headers=self.headers) as resp:
                if resp.status == 200:
                    return await resp.json()
                else:
                    return None

# Bot Handlers
bot = Bot(token=BOT_TOKEN)
dp = Dispatcher()
remna_api = RemnaAPI(API_URL, API_TOKEN)

@dp.message(Command("start"))
async def cmd_start(message: types.Message):
    builder = InlineKeyboardBuilder()
    builder.row(types.InlineKeyboardButton(
        text="🚀 Регистрация / Получить подписку",
        callback_data="register"
    ))
    
    await message.answer(
        "👋 Привет! Я бот для регистрации в Caskade VPN.\n\n"
        "Нажми кнопку ниже, чтобы создать аккаунт и получить ссылку на подписку.",
        reply_markup=builder.as_markup()
    )

@dp.callback_query(F.data == "register")
async def process_registration(callback: types.CallbackQuery):
    tg_id = callback.from_user.id
    
    with Session(engine) as session:
        statement = select(User).where(User.tg_id == tg_id)
        user = session.exec(statement).first()
        
        if user:
            # User already registered, refresh subscription link
            sub = await remna_api.get_subscription(user.remna_uuid)
            if sub:
                sub_url = f"https://{SUB_DOMAIN}/{sub.get('shortUuid')}"
                await callback.message.answer(
                    f"✅ У тебя уже есть аккаунт!\n\n"
                    f"Твоя ссылка на подписку:\n`{sub_url}`\n\n"
                    f"Добавь её в свой VPN клиент (v2rayNG, Streisand, V2Box и др.)",
                    parse_mode="Markdown"
                )
            else:
                await callback.message.answer("❌ Не удалось получить данные подписки. Обратитесь в поддержку.")
            await callback.answer()
            return

        # New registration
        await callback.message.answer("⏳ Создаю твой аккаунт, подожди немного...")
        
        remna_username = f"tg_{tg_id}"
        remna_user_data = await remna_api.create_user(remna_username, TRIAL_DAYS, SQUAD_UUID)
        
        if not remna_user_data:
            await callback.message.answer("❌ Ошибка при создании аккаунта. Попробуйте позже.")
            await callback.answer()
            return
        
        uuid = remna_user_data.get("uuid")
        
        # Get shortUuid for the link
        sub_data = await remna_api.get_subscription(uuid)
        short_uuid = sub_data.get("shortUuid") if sub_data else None
        
        new_user = User(
            tg_id=tg_id,
            username=remna_username,
            remna_uuid=uuid,
            remna_short_uuid=short_uuid
        )
        session.add(new_user)
        session.commit()
        
        sub_url = f"https://{SUB_DOMAIN}/{short_uuid}" if short_uuid else "Ошибка генерации ссылки"
        
        await callback.message.answer(
            f"🎉 Поздравляем! Твой аккаунт создан.\n\n"
            f"📅 Подписка активна на {TRIAL_DAYS} дней.\n"
            f"🔗 Твоя ссылка:\n`{sub_url}`\n\n"
            f"Скопируй эту ссылку и импортируй её в приложение (V2Ray / Xray).",
            parse_mode="Markdown"
        )
    
    await callback.answer()

async def main():
    logging.basicConfig(level=logging.INFO)
    create_db_and_tables()
    await dp.start_polling(bot)

if __name__ == "__main__":
    asyncio.run(main())
