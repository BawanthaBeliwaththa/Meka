import asyncio
import logging
import os
from aiogram import Bot, Dispatcher
from aiogram.enums import ParseMode
from aiogram.client.default import DefaultBotProperties
from dotenv import load_dotenv
load_dotenv()

from database import init_db
from handlers.admin_handlers import admin_router
from handlers.user_handlers import user_router
from handlers.ai_handlers import ai_router

# Setup logging
logging.basicConfig(level=logging.INFO,
                    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

async def main():
    BOT_TOKEN = os.getenv("BOT_TOKEN")
    if not BOT_TOKEN:
        logger.error("BOT_TOKEN not found in environment variables.")
        return

    # Initialize database
    await init_db()
    logger.info("Database initialized.")

    # Start Firebase Listener for Web App Commands
    from services.firebase_listener import start_firebase_listener
    loop = asyncio.get_running_loop()
    start_firebase_listener(loop)

    # Initialize bot and dispatcher
    bot = Bot(token=BOT_TOKEN, default=DefaultBotProperties(parse_mode=ParseMode.MARKDOWN))
    dp = Dispatcher()

    # Include routers
    dp.include_router(admin_router)
    dp.include_router(user_router)
    dp.include_router(ai_router)

    logger.info("Starting bot polling...")
    await bot.delete_webhook(drop_pending_updates=True)
    await dp.start_polling(bot)

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except (KeyboardInterrupt, SystemExit):
        logger.info("Bot stopped.")
