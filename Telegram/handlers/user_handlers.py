from aiogram import Router, F
from aiogram.filters import Command, CommandStart
from aiogram.types import Message, LabeledPrice, PreCheckoutQuery, InlineKeyboardMarkup, InlineKeyboardButton, CallbackQuery
from aiogram.fsm.context import FSMContext
from aiogram.fsm.state import State, StatesGroup
import os

from database import add_user, get_user, set_paid, set_role, set_onboarding_data, set_user_email

user_router = Router()
PROVIDER_TOKEN = os.getenv("PROVIDER_TOKEN")

class Onboarding(StatesGroup):
    email = State()
    gender = State()
    name = State()

@user_router.message(CommandStart())
async def cmd_start(message: Message, state: FSMContext):
    await add_user(message.from_user.id, message.from_user.username or "Unknown")
    user = await get_user(message.from_user.id)
    
    from handlers.admin_handlers import is_admin
    if await is_admin(message.from_user.id, message.from_user.username):
        await set_role(message.from_user.id, 'admin')
        user = await get_user(message.from_user.id)
        
    if user and user['email']:
        daily = user['daily_count'] if user['daily_count'] else 0
        welcome_text = (
            "🤖 **Welcome back to MEKA AI**\n\n"
            f"📧 Linked Email: `{user['email']}`\n\n"
        )
        if user['role'] == 'admin' or user['email'] == "bawanthabeliwaththa@gmail.com":
            welcome_text += "👑 *Admin Tier:* Unlimited chats (OLED enabled)"
        else:
            welcome_text += f"📊 *Registered User Tier:* {daily}/20 chats used today (OLED enabled)"
        await message.answer(welcome_text, parse_mode="Markdown")
        return
        
    await state.set_state(Onboarding.email)
    await message.answer(
        "👋 **Welcome to MEKA Cybernetic AI!**\n\n"
        "Please enter your **Google Email Address** (the one you used/will use on the Web App):\n\n"
        "💡 *Registered users get 20 daily chats + OLED display sync! Non-registered users get 5 chats/day.*",
        parse_mode="Markdown"
    )

@user_router.message(Onboarding.email)
async def process_email(message: Message, state: FSMContext):
    email = message.text.strip().lower()
    if "@" not in email or "." not in email:
        await message.answer("❌ Invalid email address. Please enter a valid email:")
        return
        
    await set_user_email(message.from_user.id, email)
    await state.clear()
    
    if email == "bawanthabeliwaththa@gmail.com":
        await set_role(message.from_user.id, 'admin')
        await message.answer("👑 **Admin Email Verified!** You have unlimited access & OLED display sync enabled.", parse_mode="Markdown")
    else:
        await message.answer(
            f"✅ **Email linked:** `{email}`\n\n"
            "🎉 If registered on the WebApp, you have **20 daily chats** with OLED display sync!\n"
            "If not registered yet, please log in at the WebApp to upgrade from 5 to 20 chats/day.",
            parse_mode="Markdown"
        )

@user_router.message(Command("status"))
async def cmd_status(message: Message):
    user = await get_user(message.from_user.id)
    if not user:
        await message.reply("Please type /start first.")
        return
        
    status = "Premium 💳" if user['is_paid'] or user['role'] == 'admin' else "Free Tier 🆓"
    daily = user['daily_count'] if user['daily_count'] else 0
    weekly = user['weekly_count'] if user['weekly_count'] else 0
    
    text = (
        f"📊 **Your Status**\n\n"
        f"Role: {user['role'].capitalize()}\n"
        f"Tier: {status}\n"
    )
    
    if user['role'] == 'admin' or user['is_paid']:
        text += "Limit: Unlimited ♾️\n"
    elif user['role'] == 'approved':
        text += f"Daily Limit: {daily} / 20\n"
    else:
        # Non-registered users: 5 per DAY (not per week — see check_access in ai_handlers.py)
        text += f"Daily Limit: {daily} / 5\n"
    
    if not user['is_paid'] and user['role'] != 'admin':
        text += "\nUse /pay to unlock unlimited access!"
        
    await message.reply(text, parse_mode="Markdown")

@user_router.message(Command("pay"))
async def cmd_pay(message: Message):
    user = await get_user(message.from_user.id)
    if user and (user['is_paid'] or user['role'] == 'admin'):
        await message.reply("You already have Premium access! Thank you. 💳✅")
        return
        
    prices = [LabeledPrice(label="MEKA Premium Lifetime", amount=500)]
    
    if not PROVIDER_TOKEN:
        await message.reply("Payment provider token is not configured by the admin.")
        return
        
    await message.bot.send_invoice(
        message.chat.id,
        title="MEKA AI Premium",
        description="Unlock unlimited AI chatting and voice notes forever.",
        payload="meka_premium_lifetime",
        provider_token=PROVIDER_TOKEN,
        currency="XTR",
        prices=prices,
        start_parameter="premium-access"
    )

@user_router.pre_checkout_query()
async def pre_checkout_query(pre_checkout_q: PreCheckoutQuery):
    await pre_checkout_q.answer(ok=True)

@user_router.message(F.successful_payment)
async def successful_payment(message: Message):
    await set_paid(message.from_user.id, True)
    await message.reply("🎉 Payment successful! You now have unlimited access to MEKA AI. Thank you for your support!")
