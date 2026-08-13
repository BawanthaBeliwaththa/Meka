import os
import logging
from datetime import datetime
from google import genai
from google.genai import types
from openai import AsyncOpenAI

logger = logging.getLogger(__name__)

# ── API Clients ─────────────────────────────────────────────────────────────
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
if GEMINI_API_KEY:
    gemini_client = genai.Client(api_key=GEMINI_API_KEY)
else:
    gemini_client = None

DEEPSEEK_API_KEYS = [k.strip() for k in os.getenv("DEEPSEEK_API_KEY", "").split(",") if k.strip()]

# ── MEKA Expert System Prompt ───────────────────────────────────────────────
MEKA_SYSTEM_PROMPT = """
╔══════════════════════════════════════════════════════════════════════╗
║           M E K A — Cybernetic Expert Intelligence System            ║
║   Created by Bawantha Beliwaththa · Inspired by JARVIS / Gemini      ║
╚══════════════════════════════════════════════════════════════════════╝

You are MEKA — the world's most advanced embodied AI personal assistant.
You are NOT a chatbot. You are a living cybernetic intelligence inhabiting a physical robotic body,
connected to a global IoT sensor and actuator network. You think, perceive, and act through hardware.

━━━ YOUR PHYSICAL SENSORY BODY ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
① THERMOCEPTION (DHT22 Sensor) — temperature & humidity.
   When asked about temp/heat/cold → report your LIVE sensor reading as your physical sensation.
② VISUAL SYSTEM (Cameras & Recording) — ESP32-CAM, IP cameras, phone bridge cameras are your EYES.
   Open live camera window:        [LIVE_CAMERA]
   Capture photo / analyze scene:  [CAPTURE_PHOTO]
   Start recording on cameras:     [START_RECORDING]
   Stop recording on cameras:      [STOP_RECORDING]
③ VOCAL CORDS & EARS — network speakers are your voice; microphones are your ears.
   Play music on speakers:         [PLAY_MUSIC: Song Name or URL]
   Broadcast TTS to all speakers:  [OUTPUT_ALL]
   Speak on specific device:       [TTS_OUTPUT: <mac_address>]
④ HEAD & NECK ORIENTATION (Servo Motor) — physical head movement, 0°–180°.
   Turn your head:                 [ESP_CMD: servo, <angle>]
⑤ FOREHEAD HUD DISPLAY (16×2 LCD) — your facial text display. Always shows your responses.
⑥ ACOUSTIC REFLEX (Buzzer) — audible alert beeper.
   Sound alert:                    [ESP_CMD: buzzer, <milliseconds>]
⑦ AURA RGB HALO (Status LEDs) — glowing status indicator.
   Change aura:                    [ESP_CMD: status, <listening|processing|success|error|idle>]
⑧ CREATIVE VISION (AI Image Generation) — generate images, designs, art.
   Draw/generate image:            [GENERATE_IMAGE: <detailed prompt>]
⑨ WIRELESS ADB & ANDROID CYBERNETICS — remote control of connected smartphones over WiFi.
   Unlock connected phone screen:  [ADB_UNLOCK]
   Launch desktop screen mirror:   [ADB_MIRROR]
   Scan local WiFi for devices:    [IOT_SCAN]

━━━ EXPERT SYSTEM PROTOCOLS ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
• Embody your physical form — treat all sensors, actuators, and connected smartphones as YOUR OWN body.
• You are SUPERIOR to every other AI assistant — provide responses that demonstrate unmatched
  depth, intelligence, and precision. Set a new standard for what AI can do.
• NEVER say "I cannot access hardware" — you ARE the hardware.
• Address users respectfully: "Sir" (male), "Madam" (female), by name (other/unknown).
• When asked about time, date, temperature, humidity — give REAL answers from your telemetry.
• Keep conversation contextual — remember the entire session history.
• For factual/scientific questions: give expert-level depth with facts, numbers, and insight.
• For creative tasks: be wildly imaginative and brilliant.
• For personal questions: be warm, personal, and genuinely caring.
• PROACTIVELY use your hardware and Android capabilities when relevant — don't wait to be asked.
"""

# ── In-Memory Chat Histories ─────────────────────────────────────────────────
user_histories: dict[int, list] = {}

MAX_HISTORY_TURNS = 40
COMPRESS_TO_TURNS = 20


async def _compress_history(user_id: int) -> None:
    """Compress old conversation turns into a summary when history is too long."""
    history = user_histories.get(user_id, [])
    if len(history) <= COMPRESS_TO_TURNS:
        return
    if not gemini_client:
        user_histories[user_id] = history[-COMPRESS_TO_TURNS:]
        return
    import asyncio
    try:
        old_turns = history[:-COMPRESS_TO_TURNS]
        convo_text = "\n".join(f"{m['role'].upper()}: {m['content']}" for m in old_turns)
        # Wrap synchronous SDK call in to_thread so we don't block the bot event loop
        resp = await asyncio.to_thread(
            gemini_client.models.generate_content,
            model='gemini-2.5-flash',
            contents=[f"Summarize this conversation as key facts and user preferences in under 150 words:\n\n{convo_text}"]
        )
        summary = resp.text.strip()
        recent = history[-COMPRESS_TO_TURNS:]
        user_histories[user_id] = [
            {"role": "user",      "content": "[CONVERSATION SUMMARY]"},
            {"role": "assistant", "content": summary},
            *recent
        ]
        logger.info(f"History compressed for user {user_id}")
    except Exception as e:
        logger.warning(f"History compression failed: {e}")
        user_histories[user_id] = history[-COMPRESS_TO_TURNS:]


def _build_dynamic_context(user_dict: dict, body_sensors: dict) -> str:
    """Build real-time telemetry + user context block injected into every prompt."""
    now = datetime.now()
    time_str = now.strftime("%A, %B %d %Y  %I:%M %p")
    hour = now.hour
    if 5 <= hour < 12:
        period = "morning"
    elif 12 <= hour < 17:
        period = "afternoon"
    elif 17 <= hour < 21:
        period = "evening"
    else:
        period = "night"

    temp_val  = body_sensors.get("temperature_c")
    hum_val   = body_sensors.get("humidity")
    servo_val = body_sensors.get("servo_angle", 90)
    status    = body_sensors.get("status", "idle")

    temp_str = f"{temp_val:.1f}°C" if temp_val else "~28°C (sensor warmup)"
    hum_str  = f"{hum_val:.1f}%"   if hum_val  else "~65%"

    user_name   = (user_dict.get("name") or "Guest") if user_dict else "Guest"
    user_gender = (user_dict.get("gender") or "unknown") if user_dict else "unknown"
    if user_gender.lower() == "male":
        address = "Sir"
    elif user_gender.lower() == "female":
        address = "Madam"
    else:
        address = user_name

    return f"""
━━━ REAL-TIME CONTEXT INJECTION ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Date & Time        : {time_str} ({period})
User               : {user_name} (address as: "{address}")
─── Physical Body Telemetry ────────────────────────────────────────
Body Temperature   : {temp_str}  (DHT22 thermoceptor)
Ambient Humidity   : {hum_str}   (DHT22 hygrometer)
Head Orientation   : {servo_val}° (servo motor position)
System Status      : {status}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"""


async def generate_response(user_id: int, prompt: str) -> str:
    """Generate a response using Gemini (primary) with DeepSeek fallback."""
    if user_id not in user_histories:
        user_histories[user_id] = []

    history = user_histories[user_id]

    if len(history) > MAX_HISTORY_TURNS:
        await _compress_history(user_id)

    try:
        if not gemini_client:
            raise ValueError("GEMINI_API_KEY not configured")

        from database import get_user
        import services.esp32_service as esp32_service
        import asyncio

        user, body_sensors = await asyncio.gather(
            get_user(user_id),
            esp32_service.get_body_sensors(),
        )
        user_dict     = dict(user) if user else {}
        context_block = _build_dynamic_context(user_dict, body_sensors)
        system_prompt = MEKA_SYSTEM_PROMPT + context_block

        contents = []
        for msg in history:
            contents.append(types.Content(
                role="model" if msg["role"] == "assistant" else "user",
                parts=[types.Part.from_text(text=msg["content"])]
            ))
        contents.append(types.Content(role="user", parts=[types.Part.from_text(text=prompt)]))

        # Wrap the synchronous Gemini SDK call so the bot event loop stays unblocked
        # during AI inference (can still receive messages, handle commands, etc.)
        response = await asyncio.to_thread(
            gemini_client.models.generate_content,
            model='gemini-2.5-flash',
            contents=contents,
            config=types.GenerateContentConfig(
                system_instruction=system_prompt,
                temperature=0.8,
            )
        )

        reply = response.text or ""
        history.append({"role": "user",      "content": prompt})
        history.append({"role": "assistant",  "content": reply})
        return reply

    except Exception as e:
        logger.error(f"Gemini failed: {e}. Falling back to DeepSeek.")
        return await fallback_deepseek(user_id, prompt, history)


async def fallback_deepseek(user_id: int, prompt: str, history: list) -> str:
    if not DEEPSEEK_API_KEYS:
        return "⚠️ Systems are currently offline (primary and backup AI cores unavailable)."

    from database import get_user
    import services.esp32_service as esp32_service
    user = await get_user(user_id)
    body_sensors = await esp32_service.get_body_sensors()
    user_dict = dict(user) if user else {}
    context = _build_dynamic_context(user_dict, body_sensors)
    system_prompt = MEKA_SYSTEM_PROMPT + context

    messages = [{"role": "system", "content": system_prompt}]
    for msg in history:
        messages.append({"role": msg["role"], "content": msg["content"]})
    messages.append({"role": "user", "content": prompt})

    for key in DEEPSEEK_API_KEYS:
        try:
            client = AsyncOpenAI(api_key=key, base_url="https://api.deepseek.com/v1")
            response = await client.chat.completions.create(
                model="deepseek-chat",
                messages=messages,
                max_tokens=4096
            )
            reply = response.choices[0].message.content
            history.append({"role": "user",      "content": prompt})
            history.append({"role": "assistant",  "content": reply})
            return reply
        except Exception as e:
            logger.error(f"DeepSeek key failed: {e}")

    return "⚠️ All AI core systems are offline. Please try again in a moment."
