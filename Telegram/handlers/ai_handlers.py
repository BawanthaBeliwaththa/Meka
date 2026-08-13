from aiogram import Router, F
from aiogram.filters import Command
from aiogram.types import (
    Message, FSInputFile, URLInputFile,
    InlineKeyboardMarkup, InlineKeyboardButton, WebAppInfo
)
import os
import tempfile
import asyncio
import aiohttp
import yt_dlp
import re
from gtts import gTTS

from database import get_user, increment_command_count
from services.llm_service import generate_response
from handlers.admin_handlers import is_admin
import services.esp32_service as esp32_service
from services.vision_service import vision_service
from services.firebase_storage_service import firebase_storage_service

ai_router = Router()

HUB_URL   = os.getenv("HUB_URL",   "https://localhost:5000")

# Per-user preferred output device (mac address or 'all')
_user_output_device: dict[int, str] = {}
# Admin-selected output device
_admin_output_device: str = "all"


async def _broadcast_tts(text: str, output_mac: str = "all") -> None:
    """Send TTS text to all connected phone bridge speakers via IoT Hub."""
    try:
        connector = aiohttp.TCPConnector(ssl=False)
        async with aiohttp.ClientSession(connector=connector) as session:
            await session.post(
                f"{HUB_URL}/api/audio/tts",
                json={"text": text, "output_mac": output_mac, "volume": 1.0},
                timeout=aiohttp.ClientTimeout(total=10),  # Increased from 3s — hub can be slow
            )
    except Exception:
        pass  # Hub not running or unreachable — silent fail


@ai_router.message(Command("output"))
async def cmd_set_output(message: Message):
    """Set preferred output device for voice replies."""
    global _admin_output_device
    user_id = message.from_user.id
    text = message.text or ""
    parts = text.split(maxsplit=1)

    if len(parts) < 2 or parts[1].strip().lower() in ("all", "everyone"):
        mac = "all"
        label = "All connected speakers"
    else:
        mac = parts[1].strip()
        label = f"Device {mac}"

    admin_check = await is_admin(user_id, message.from_user.username)
    if admin_check:
        _admin_output_device = mac
        await message.reply(
            f"🔊 **Admin output device set**\n"
            f"All MEKA replies will now play on: **{label}**\n\n"
            f"_Use /output all to broadcast to all devices._",
            parse_mode="Markdown"
        )
    else:
        _user_output_device[user_id] = mac
        await message.reply(
            f"🔊 **Your output device set**\n"
            f"Your MEKA replies will play on: **{label}**",
            parse_mode="Markdown"
        )


async def check_access(message: Message) -> tuple[bool, bool]:
    """
    Returns (allowed: bool, show_on_oled: bool)
    - Admin: (True, True) -> Unlimited, OLED Enabled
    - Registered WebApp User: (True, True) -> 20/day, OLED Enabled
    - Non-Registered User: (True/False, False) -> 5/day max, OLED Disabled
    """
    user = await get_user(message.from_user.id)
    if not user or not user['email']:
        await message.reply(
            "⚠️ **Registration / Email linking required**\n\n"
            "Please send /start to enter your Google email address!"
        )
        return False, False

    user_email = user['email'].strip().lower()
    admin_status = await is_admin(message.from_user.id, message.from_user.username) or (user_email == "bawanthabeliwaththa@gmail.com")
    
    if admin_status:
        return True, True

    from datetime import datetime
    now = datetime.now()
    current_date = now.strftime('%Y-%m-%d')
    
    daily_count = user['daily_count'] if user['daily_count'] is not None else 0
    if user['last_command_date'] != current_date:
        daily_count = 0

    # Check if email is registered under /meka/users or /meka/admins in Firebase
    is_registered = False
    if user_email:
        email_key = user_email.replace('.', '_dot_')
        from firebase_admin import db as fb_db
        try:
            u_snap = fb_db.reference(f"/meka/users/{email_key}").get()
            a_snap = fb_db.reference(f"/meka/admins/{email_key}").get()
            if u_snap or a_snap:
                is_registered = True
        except Exception:
            pass

    if is_registered:
        if daily_count >= 20:
            await message.reply("🔒 You have reached your limit of **20 chats today**.")
            return False, False
        return True, True
    else:
        if daily_count >= 5:
            await message.reply(
                "🔒 You have reached your limit of **5 chats today** for non-registered users.\n\n"
                "🌐 Please log into the Web App using your Google account to unlock **20 daily chats + OLED display sync**!"
            )
            return False, False
        return True, False

async def process_llm_reply(message: Message, reply: str, send_voice: bool = False):
    """Parses Gemini's reply for special tags like [PLAY_MUSIC: ...] and sends the response."""
    
    import re
    
    # Check for [TURN_SERVO: angle]
    servo_match = re.search(r'\[TURN_SERVO:\s*(\d+)\]', reply)
    servo_angle = None
    if servo_match:
        servo_angle = int(servo_match.group(1))
        reply = re.sub(r'\[TURN_SERVO:\s*\d+\]', '', reply).strip()
        
    # Check for [CAPTURE_PHOTO]
    capture_photo = False
    if '[CAPTURE_PHOTO]' in reply:
        capture_photo = True
        reply = reply.replace('[CAPTURE_PHOTO]', '').strip()

    # Check for [LIVE_CAMERA]
    live_camera = False
    if '[LIVE_CAMERA]' in reply:
        live_camera = True
        reply = reply.replace('[LIVE_CAMERA]', '').strip()
        
    # Check for [GENERATE_IMAGE: query]
    img_match = re.search(r'\[GENERATE_IMAGE:\s*(.+?)\]', reply)
    image_query = None
    if img_match:
        image_query = img_match.group(1).strip()
        reply = re.sub(r'\[GENERATE_IMAGE:\s*(.+?)\]', '', reply).strip()

    # Check for [PLAY_MUSIC: song name]
    music_match = re.search(r'\[PLAY_MUSIC:\s*(.+?)\]', reply)
    music_query = None
    if music_match:
        music_query = music_match.group(1).strip()
        reply = re.sub(r'\[PLAY_MUSIC:\s*(.+?)\]', '', reply).strip()
        
    # Check for [ADB_UNLOCK]
    if '[ADB_UNLOCK]' in reply:
        reply = reply.replace('[ADB_UNLOCK]', '').strip()
        async def _unlock():
            try:
                connector = aiohttp.TCPConnector(ssl=False)
                async with aiohttp.ClientSession(connector=connector) as session:
                    await session.post(f"{HUB_URL}/api/adb/192.168.1.100:5555/unlock", json={}, timeout=aiohttp.ClientTimeout(total=5))
            except Exception: pass
        asyncio.create_task(_unlock())

    # Check for [ADB_MIRROR]
    if '[ADB_MIRROR]' in reply:
        reply = reply.replace('[ADB_MIRROR]', '').strip()
        async def _mirror():
            try:
                connector = aiohttp.TCPConnector(ssl=False)
                async with aiohttp.ClientSession(connector=connector) as session:
                    await session.post(f"{HUB_URL}/api/adb/192.168.1.100:5555/mirror/start", json={}, timeout=aiohttp.ClientTimeout(total=5))
            except Exception: pass
        asyncio.create_task(_mirror())

    # Check for [START_RECORDING]
    if '[START_RECORDING]' in reply:
        reply = reply.replace('[START_RECORDING]', '').strip()
        async def _start_rec():
            try:
                connector = aiohttp.TCPConnector(ssl=False)
                async with aiohttp.ClientSession(connector=connector) as session:
                    await session.post(f"{HUB_URL}/api/cameras/record/start-all", json={}, timeout=aiohttp.ClientTimeout(total=5))
            except Exception: pass
        asyncio.create_task(_start_rec())

    # Check for [STOP_RECORDING]
    if '[STOP_RECORDING]' in reply:
        reply = reply.replace('[STOP_RECORDING]', '').strip()
        async def _stop_rec():
            try:
                connector = aiohttp.TCPConnector(ssl=False)
                async with aiohttp.ClientSession(connector=connector) as session:
                    await session.post(f"{HUB_URL}/api/cameras/record/stop-all", json={}, timeout=aiohttp.ClientTimeout(total=5))
            except Exception: pass
        asyncio.create_task(_stop_rec())

    # Check for [IOT_SCAN]
    if '[IOT_SCAN]' in reply:
        reply = reply.replace('[IOT_SCAN]', '').strip()
        async def _scan():
            try:
                connector = aiohttp.TCPConnector(ssl=False)
                async with aiohttp.ClientSession(connector=connector) as session:
                    await session.post(f"{HUB_URL}/api/devices/scan", json={}, timeout=aiohttp.ClientTimeout(total=5))
            except Exception: pass
        asyncio.create_task(_scan())

    # Check for [ESP_CMD: device, param1, param2]
    esp_match = re.search(r'\[ESP_CMD:\s*([^,\]]+?)\s*,\s*([^,\]]+?)(?:\s*,\s*([^,\]]+?))?\]', reply)
    if esp_match:
        device = esp_match.group(1).strip()
        param1 = esp_match.group(2).strip()
        param2 = esp_match.group(3).strip() if esp_match.group(3) else None
        
        # Fire and forget the hardware control task
        asyncio.create_task(esp32_service.control_hardware(device, param1, param2))
        
        reply = re.sub(r'\[ESP_CMD:[^\]]+\]', '', reply).strip()

    # Send Text Safely to Telegram and ESP32 Display (full text — no truncation)
    if reply:
        # Extract original text and user info for logging
        original_text = message.text or message.caption or ""
        username = message.from_user.username or str(message.from_user.id)
        
        # Send to LCD
        asyncio.create_task(esp32_service.send_display_q(f"Q: {original_text}"))
        asyncio.create_task(esp32_service.send_display_a(f"A: {reply}"))
        asyncio.create_task(esp32_service.log_command(username, original_text, reply, "success"))

        # Always broadcast TTS to all connected phone bridge speaker devices
        asyncio.create_task(_broadcast_tts(reply))
        
        try:
            await message.reply(reply, parse_mode="Markdown")
        except Exception:
            await message.reply(reply, parse_mode=None)
        
    # Send Voice back in Telegram (if it was a voice input)
    if reply and send_voice:
        audio_path = None
        try:
            with tempfile.NamedTemporaryFile(delete=False, suffix=".mp3") as audio_out:
                audio_path = audio_out.name
            tts = gTTS(text=reply, lang='en', tld='co.uk')
            tts.save(audio_path)
            voice_file = FSInputFile(audio_path)
            await message.reply_voice(voice_file)
        except Exception as e:
            await message.reply(f"⚠️ Voice generation failed: {e}")
        finally:
            # Always clean up the temp file whether or not sending succeeded
            if audio_path and os.path.exists(audio_path):
                os.unlink(audio_path)

            
    # Process Image Generation Request
    if image_query:
        await message.bot.send_chat_action(chat_id=message.chat.id, action="upload_photo")
        encoded_prompt = image_query.replace(" ", "%20")
        url = f"https://image.pollinations.ai/prompt/{encoded_prompt}"
        try:
            photo = URLInputFile(url)
            await message.reply_photo(photo, caption=f"🎨 `{image_query}`")
        except Exception as e:
            await message.reply(f"⚠️ Failed to generate image: {e}")
            
    # Process Music Request
    if music_query:
        msg = await message.answer(f"🔍 Searching and downloading `{music_query}` for native playback...")
        
        def download_song(q: str) -> str:
            ydl_opts = {
                'format': 'bestaudio[ext=m4a]/bestaudio/best',
                'outtmpl': '%(id)s.%(ext)s',
                'noplaylist': True,
                'quiet': True,
                'default_search': 'ytsearch'
            }
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(f"ytsearch:{q}", download=True)
                if 'entries' in info:
                    info = info['entries'][0]
                return f"{info['id']}.{info['ext']}"
                
        try:
            file_path = await asyncio.to_thread(download_song, music_query)
            audio = FSInputFile(file_path)
            await message.reply_audio(audio, caption="🎵 Enjoy your music natively inside Telegram!")
            os.remove(file_path)
            await msg.delete()
        except Exception as e:
            await msg.edit_text("⚠️ Failed to download music. (FFmpeg or connection error)", parse_mode=None)

    # Process Live Camera Request
    if live_camera:
        hub_ip = os.getenv("HUB_IP", "localhost")
        hub_port = os.getenv("HUB_PORT", "5000")
        hub_proto = os.getenv("HUB_PROTO", "https")
        stream_url = f"{hub_proto}://{hub_ip}:{hub_port}/camera-viewer"

        keyboard = InlineKeyboardMarkup(inline_keyboard=[
            [
                InlineKeyboardButton(
                    text="📺 Open Live Camera Window",
                    web_app=WebAppInfo(url=stream_url)
                )
            ],
            [
                InlineKeyboardButton(
                    text="🔗 Open Stream Link",
                    url=stream_url
                )
            ]
        ])


        await message.answer(
            f"📹 **MEKA Live Camera Stream**\n\n"
            f"Tap below to open the live camera view window directly in Telegram:\n"
            f"`{stream_url}`",
            parse_mode="Markdown",
            reply_markup=keyboard
        )


    # Process Capture Photo Request
    if capture_photo:
        await message.bot.send_chat_action(chat_id=message.chat.id, action="upload_photo")
        msg = await message.answer("📸 Capturing photo from MEKA's camera...")
        
        # Run in thread so we don't block — tries ESP32 first, then phone bridge
        image_bytes = await asyncio.to_thread(vision_service.capture_image)
        if image_bytes:
            # Save temporarily
            tmp_path = f"capture_{message.from_user.id}.jpg"
            with open(tmp_path, "wb") as f:
                f.write(image_bytes)
                
            # Send to Telegram
            photo = FSInputFile(tmp_path)
            await message.reply_photo(photo, caption="📸 Here is what I see!")
            
            # Upload to Cloud Storage
            await message.answer("☁️ Uploading to Firebase Cloud Storage...")
            success, result = await asyncio.to_thread(firebase_storage_service.upload_file, tmp_path)
            if success:
                await message.answer(f"✅ Uploaded: {result}")
            else:
                await message.answer(f"⚠️ Upload failed: {result}")
                
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
        else:
            hub_ip = os.getenv("HUB_IP", "localhost")
            hub_port = os.getenv("HUB_PORT", "5000")
            hub_proto = os.getenv("HUB_PROTO", "https")
            await msg.edit_text(
                f"⚠️ Direct ESP32 camera unavailable.\n\n"
                f"📱 To get a snapshot, open the phone bridge and tap 'Capture':\n"
                f"`{hub_proto}://{hub_ip}:{hub_port}/phone-bridge`",
                parse_mode="Markdown"
            )


@ai_router.message(Command("imagine"))
async def cmd_imagine(message: Message):
    allowed, _ = await check_access(message)
    if not allowed:
        return
        
    args = message.text.split(maxsplit=1)
    if len(args) < 2:
        await message.reply("Usage: /imagine <prompt>")
        return
        
    prompt = args[1]
    await message.bot.send_chat_action(chat_id=message.chat.id, action="upload_photo")
    
    encoded_prompt = prompt.replace(" ", "%20")
    url = f"https://image.pollinations.ai/prompt/{encoded_prompt}"
    
    try:
        photo = URLInputFile(url)
        await message.reply_photo(photo, caption=f"🎨 `{prompt}`")
        await increment_command_count(message.from_user.id)
    except Exception as e:
        await message.reply(f"⚠️ Failed to generate image: {e}")

@ai_router.message(F.photo)
async def handle_photo(message: Message):
    allowed, _ = await check_access(message)
    if not allowed:
        return
        
    user_id = message.from_user.id
    await message.bot.send_chat_action(chat_id=message.chat.id, action="typing")
    
    try:
        photo = message.photo[-1]
        file = await message.bot.get_file(photo.file_id)
        file_path = file.file_path
        
        with tempfile.NamedTemporaryFile(delete=False, suffix=".jpg") as tmp:
            await message.bot.download_file(file_path, tmp.name)
            
            if os.getenv("GEMINI_API_KEY"):
                from google import genai
                client = genai.Client(api_key=os.getenv("GEMINI_API_KEY"))
                img_file = client.files.upload(file=tmp.name)
                
                prompt = message.caption if message.caption else "Describe this image in detail."
                
                response = client.models.generate_content(
                    model='gemini-2.5-flash',
                    contents=[
                        "You are MEKA, a JARVIS-inspired AI. Analyze the image and reply to the user's prompt.",
                        prompt,
                        img_file
                    ]
                )
                reply = response.text or ""
                client.files.delete(name=img_file.name)
                
                await process_llm_reply(message, reply, send_voice=False)
                
            else:
                await message.reply("Vision features require the Gemini API, which is not configured.")
                
        os.unlink(tmp.name)
        
    except Exception as e:
        await message.reply(f"⚠️ Sorry, I couldn't process your photo: {e}")
        
    await increment_command_count(user_id)

# ── Poor Reply Detection ──────────────────────────────────────────────

# Phrases that indicate the AI could not fulfil the request — trigger buzzer
_REFUSAL_PHRASES = [
    "i apologize", "i cannot", "i can't", "i don't have access",
    "i am unable", "i'm unable", "not able to", "don't have the ability",
    "my current capabilities do not", "as an ai", "i have no access",
]

def _is_poor_reply(reply: str | None) -> bool:
    """Return True if the AI reply is empty, too short, or a refusal."""
    if not reply or len(reply.strip()) < 12:
        return True
    lower = reply.lower()
    return any(phrase in lower for phrase in _REFUSAL_PHRASES)


@ai_router.message(F.text.regexp(r'^[^/]'))
async def handle_text(message: Message):
    allowed, show_on_oled = await check_access(message)
    if not allowed:
        return
        
    user_id = message.from_user.id
    prompt = message.text
    
    await message.bot.send_chat_action(chat_id=message.chat.id, action="typing")
    
    # 🔵 Blue LED — Listening
    asyncio.create_task(esp32_service.set_status("listening"))
    await asyncio.sleep(0.5)
    
    # 🟡 Yellow LED — Processing
    asyncio.create_task(esp32_service.set_status("processing"))
    if show_on_oled:
        asyncio.create_task(esp32_service.send_display_q(f"Q: {prompt}"))
        asyncio.create_task(esp32_service.send_display_a("Processing..."))
    
    try:
        reply = await generate_response(user_id, prompt)

        if _is_poor_reply(reply):
            # Poor reply: fire buzzer + status, but STILL send the reply once so user sees it
            asyncio.create_task(esp32_service.set_status("error"))
            asyncio.create_task(esp32_service.control_hardware("buzzer", "600"))
            asyncio.create_task(esp32_service.log_command("telegram", prompt, reply or "[empty]", "error"))
            if reply:
                # Send the poor reply once — no duplicate
                await process_llm_reply(message, reply, send_voice=False)
        else:
            await process_llm_reply(message, reply, send_voice=False)
            await increment_command_count(user_id)
            # 🟢 Green LED — Success
            asyncio.create_task(esp32_service.set_status("success"))
            if show_on_oled:
                asyncio.create_task(esp32_service.send_display_a(f"A: {reply}"))
            asyncio.create_task(esp32_service.log_command("telegram", prompt, reply, "success"))

    except Exception as e:
        # 🔴 Red LED + Buzzer — Exception
        asyncio.create_task(esp32_service.set_status("error"))
        asyncio.create_task(esp32_service.control_hardware("buzzer", "800"))
        asyncio.create_task(esp32_service.log_command("telegram", prompt, str(e), "error"))
        raise

@ai_router.message(F.voice)
async def handle_voice(message: Message):
    allowed, _ = await check_access(message)
    if not allowed:
        return
        
    user_id = message.from_user.id
    await message.bot.send_chat_action(chat_id=message.chat.id, action="record_voice")
    
    # 🔵 Blue LED — Listening
    asyncio.create_task(esp32_service.set_status("listening"))
    await asyncio.sleep(0.5)
    # 🟡 Yellow LED — Processing
    asyncio.create_task(esp32_service.set_status("processing"))
    asyncio.create_task(esp32_service.send_display_q("Q: [Voice Note]"))
    asyncio.create_task(esp32_service.send_display_a("Processing..."))
    
    try:
        file_id = message.voice.file_id
        file = await message.bot.get_file(file_id)
        file_path = file.file_path
        
        with tempfile.NamedTemporaryFile(delete=False, suffix=".ogg") as tmp:
            await message.bot.download_file(file_path, tmp.name)
            
            if os.getenv("GEMINI_API_KEY"):
                from google import genai
                client = genai.Client(api_key=os.getenv("GEMINI_API_KEY"))
                audio_file = client.files.upload(file=tmp.name)
                
                response = client.models.generate_content(
                    model='gemini-2.5-flash',
                    contents=[
                        "You are MEKA, a JARVIS-inspired AI. Listen to the user's voice note, process what they are saying, and reply intelligently.",
                        audio_file
                    ]
                )
                reply = response.text or ""
                client.files.delete(name=audio_file.name)

                # 🔔 Buzzer on poor voice reply
                if _is_poor_reply(reply):
                    asyncio.create_task(esp32_service.set_status("error"))
                    asyncio.create_task(esp32_service.control_hardware("buzzer", "600"))
                    asyncio.create_task(esp32_service.log_command("telegram_voice", "[Voice Note]", reply or "[empty]", "error"))
                else:
                    asyncio.create_task(esp32_service.set_status("success"))
                    asyncio.create_task(esp32_service.log_command("telegram_voice", "[Voice Note]", reply, "success"))

                await process_llm_reply(message, reply, send_voice=True)

            else:
                await message.reply("Voice notes require the Gemini API, which is not configured.", parse_mode="Markdown")

        os.unlink(tmp.name)

    except Exception as e:
        asyncio.create_task(esp32_service.set_status("error"))
        asyncio.create_task(esp32_service.control_hardware("buzzer", "800"))
        asyncio.create_task(esp32_service.log_command("telegram_voice", "[Voice Note]", str(e), "error"))
        await message.reply(f"⚠️ Sorry, I couldn't process your voice note: {e}", parse_mode="Markdown")
        
    await increment_command_count(user_id)
