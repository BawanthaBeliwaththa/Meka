from aiogram import Router, F
from aiogram.filters import Command
from aiogram.types import (
    Message, InlineKeyboardMarkup, InlineKeyboardButton,
    CallbackQuery, FSInputFile, BufferedInputFile, WebAppInfo,
)
import os
import io
import asyncio
import aiohttp

from database import set_role, get_all_users, get_user

HUB_URL   = os.getenv("HUB_URL",   "https://localhost:5000")
HUB_PROTO = os.getenv("HUB_PROTO", "https")
HUB_IP    = os.getenv("HUB_IP",    "localhost")
HUB_PORT  = os.getenv("HUB_PORT",  "5000")

admin_router = Router()

async def is_admin(user_id: int, username: str = None) -> bool:
    user = await get_user(user_id)
    if user and user['role'] == 'admin':
        return True
    
    admin_id_env = os.getenv('ADMIN_ID', '').strip()
    if str(user_id) == admin_id_env:
        return True
    if username and admin_id_env.lower() in [username.lower(), f"@{username.lower()}"]:
        return True
    return False

@admin_router.message(Command("admin"))
async def cmd_admin(message: Message):
    if not await is_admin(message.from_user.id, message.from_user.username):
        return
        
    keyboard = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="👥 Manage Users", callback_data="admin_users")],
        [InlineKeyboardButton(text="✅ Pending Approvals", callback_data="admin_pending")],
        [InlineKeyboardButton(text="📊 Stats", callback_data="admin_stats")]
    ])
    
    await message.reply("⚙️ **MEKA Admin Dashboard**\n\nSelect an option below:", reply_markup=keyboard, parse_mode="Markdown")

@admin_router.callback_query(F.data.startswith("admin_"))
async def handle_admin_callbacks(callback: CallbackQuery):
    if not await is_admin(callback.from_user.id, callback.from_user.username):
        await callback.answer("Unauthorized", show_alert=True)
        return
        
    action = callback.data.split("_")[1]
    
    if action == "users":
        users = await get_all_users()
        if not users:
            text = "No users found."
        else:
            text = "👥 **User List**\n\n"
            for u in users:
                paid_status = "💳 Paid" if u['is_paid'] else "🆓 Free"
                text += f"ID: `{u['id']}` | @{u['username']} | Role: {u['role']} | Used: {u['command_count']}/5 | {paid_status}\n"
        
        keyboard = InlineKeyboardMarkup(inline_keyboard=[[InlineKeyboardButton(text="🔙 Back", callback_data="admin_dashboard")]])
        await callback.message.edit_text(text, parse_mode="Markdown", reply_markup=keyboard)
        
    elif action == "pending":
        users = await get_all_users()
        pending = [u for u in users if u['role'] == 'pending']
        if not pending:
            text = "No pending approvals."
            keyboard = InlineKeyboardMarkup(inline_keyboard=[[InlineKeyboardButton(text="🔙 Back", callback_data="admin_dashboard")]])
            await callback.message.edit_text(text, parse_mode="Markdown", reply_markup=keyboard)
        else:
            keyboard = []
            for u in pending:
                keyboard.append([InlineKeyboardButton(text=f"Approve @{u['username']}", callback_data=f"approve_{u['id']}")])
            keyboard.append([InlineKeyboardButton(text="🔙 Back", callback_data="admin_dashboard")])
            reply_markup = InlineKeyboardMarkup(inline_keyboard=keyboard)
            await callback.message.edit_text("✅ **Pending Approvals**", reply_markup=reply_markup, parse_mode="Markdown")
            
    elif action == "stats":
        users = await get_all_users()
        total = len(users)
        admins = len([u for u in users if u['role'] == 'admin'])
        premium = len([u for u in users if u['is_paid']])
        total_commands = sum([u['command_count'] for u in users])
        
        text = (
            "📊 **System Statistics**\n\n"
            f"Total Users: {total}\n"
            f"Admins: {admins}\n"
            f"Premium Users: {premium}\n"
            f"Total Commands Processed: {total_commands}"
        )
        keyboard = InlineKeyboardMarkup(inline_keyboard=[[InlineKeyboardButton(text="🔙 Back", callback_data="admin_dashboard")]])
        await callback.message.edit_text(text, parse_mode="Markdown", reply_markup=keyboard)
        
    elif action == "dashboard":
        keyboard = InlineKeyboardMarkup(inline_keyboard=[
            [InlineKeyboardButton(text="👥 Manage Users", callback_data="admin_users")],
            [InlineKeyboardButton(text="✅ Pending Approvals", callback_data="admin_pending")],
            [InlineKeyboardButton(text="📊 Stats", callback_data="admin_stats")]
        ])
        await callback.message.edit_text("⚙️ **MEKA Admin Dashboard**\n\nSelect an option below:", reply_markup=keyboard, parse_mode="Markdown")

    await callback.answer()

@admin_router.callback_query(F.data.startswith("approve_"))
async def handle_approve_callback(callback: CallbackQuery):
    if not await is_admin(callback.from_user.id, callback.from_user.username):
        await callback.answer("Unauthorized", show_alert=True)
        return
        
    target_id = int(callback.data.split("_")[1])
    await set_role(target_id, 'approved')
    await callback.answer(f"User {target_id} approved!", show_alert=True)
    
    # Refresh pending list
    users = await get_all_users()
    pending = [u for u in users if u['role'] == 'pending']
    if not pending:
        text = "No pending approvals left."
        keyboard = InlineKeyboardMarkup(inline_keyboard=[[InlineKeyboardButton(text="🔙 Back", callback_data="admin_dashboard")]])
        await callback.message.edit_text(text, reply_markup=keyboard, parse_mode="Markdown")
    else:
        keyboard = []
        for u in pending:
            keyboard.append([InlineKeyboardButton(text=f"Approve @{u['username']}", callback_data=f"approve_{u['id']}")])
        keyboard.append([InlineKeyboardButton(text="🔙 Back", callback_data="admin_dashboard")])
        reply_markup = InlineKeyboardMarkup(inline_keyboard=keyboard)
        await callback.message.edit_text("✅ **Pending Approvals**", reply_markup=reply_markup, parse_mode="Markdown")

@admin_router.message(Command("addadmin"))
async def cmd_addadmin(message: Message):
    if not await is_admin(message.from_user.id, message.from_user.username):
        return
        
    args = message.text.split()
    if len(args) != 2:
        await message.reply("Usage: /addadmin <user_id>")
        return
        
    target_id = args[1]
    if not target_id.isdigit():
        await message.reply("User ID must be a number.")
        return
        
    await set_role(int(target_id), 'admin')
    await message.reply(f"User {target_id} is now an Admin.")


# ══════════════════════════════════════════════════════════════════════
# Hub-Integrated Admin Commands
# ══════════════════════════════════════════════════════════════════════

async def _hub_get(path: str) -> dict | None:
    """GET from IoT hub. Returns parsed JSON or None on error."""
    try:
        async with aiohttp.ClientSession(
            connector=aiohttp.TCPConnector(ssl=False)
        ) as session:
            async with session.get(f"{HUB_URL}{path}", timeout=aiohttp.ClientTimeout(total=8)) as r:
                if r.status == 200:
                    return await r.json()
    except Exception:
        pass
    return None


async def _hub_post(path: str, payload: dict) -> dict | None:
    """POST to IoT hub. Returns parsed JSON or None on error."""
    try:
        async with aiohttp.ClientSession(
            connector=aiohttp.TCPConnector(ssl=False)
        ) as session:
            async with session.post(
                f"{HUB_URL}{path}", json=payload,
                timeout=aiohttp.ClientTimeout(total=8)
            ) as r:
                return await r.json()
    except Exception:
        pass
    return None


async def _hub_get_bytes(path: str) -> bytes | None:
    """GET binary data (image) from IoT hub."""
    try:
        async with aiohttp.ClientSession(
            connector=aiohttp.TCPConnector(ssl=False)
        ) as session:
            async with session.get(f"{HUB_URL}{path}", timeout=aiohttp.ClientTimeout(total=10)) as r:
                if r.status == 200:
                    return await r.read()
    except Exception:
        pass
    return None


# ── /cameras ──────────────────────────────────────────────────────────

@admin_router.message(Command("cameras"))
async def cmd_cameras(message: Message):
    """List all discovered cameras & broadcast camera permission popups to all Wi-Fi network devices."""
    if not await is_admin(message.from_user.id, message.from_user.username):
        return

    await message.bot.send_chat_action(chat_id=message.chat.id, action="typing")
    
    # Broadcast start-all cameras command to hub (sends popups to laptops/phones & auto-connects IP cams)
    start_res = await _hub_post("/api/cameras/start-all", {})
    data = await _hub_get("/api/cameras/all-streams")

    if data is None:
        await message.reply(
            "⚠️ **IoT Hub is offline.**\n\n"
            f"Start the hub at `{HUB_URL}` then try again.",
            parse_mode="Markdown"
        )
        return

    cameras = data.get("cameras", [])
    keyboard = []
    text = "📹 **MEKA Camera System Activated**\n\n"
    if start_res and "message" in start_res:
        text += f"📡 _{start_res['message']}_\n\n"

    for cam in cameras:
        status = "🟢" if cam.get("online") else "🔴"
        name   = cam.get("name") or cam.get("device_type") or "Camera"
        ip     = cam.get("ip", "—")
        mac    = cam.get("mac", "")
        text  += f"{status} **{name}** — `{ip}`\n"
        keyboard.append([
            InlineKeyboardButton(
                text=f"📸 Snapshot — {name}",
                callback_data=f"camsnap_{mac}"
            )
        ])

    keyboard.append([
        InlineKeyboardButton(text="📺 Open Live Camera Window", web_app=WebAppInfo(url=f"{HUB_URL}/camera-viewer")),
        InlineKeyboardButton(text="📡 Broadcast Popups", callback_data="cameras_start_all")
    ])

    keyboard.append([
        InlineKeyboardButton(text="🔄 Refresh", callback_data="cameras_refresh")
    ])

    await message.reply(
        text,
        parse_mode="Markdown",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=keyboard)
    )


@admin_router.callback_query(F.data == "cameras_start_all")
async def handle_cameras_start_all(callback: CallbackQuery):
    """Callback to re-trigger camera start-all broadcast."""
    if not await is_admin(callback.from_user.id, callback.from_user.username):
        await callback.answer("Unauthorized", show_alert=True)
        return

    res = await _hub_post("/api/cameras/start-all", {})
    if res:
        msg = res.get("message", "Permission popups broadcasted!")
        await callback.answer(f"📡 {msg}", show_alert=True)
    else:
        await callback.answer("❌ Hub offline", show_alert=True)



@admin_router.callback_query(F.data.startswith("camsnap_"))
async def handle_camsnap(callback: CallbackQuery):
    """Take snapshot from a specific camera MAC."""
    if not await is_admin(callback.from_user.id, callback.from_user.username):
        await callback.answer("Unauthorized", show_alert=True)
        return

    mac = callback.data.replace("camsnap_", "")
    await callback.answer("📸 Capturing...")
    await callback.bot.send_chat_action(chat_id=callback.message.chat.id, action="upload_photo")

    # Phone bridge uses latest-frame; other cameras use /snapshot endpoint
    if mac == "phone_bridge":
        img_bytes = await _hub_get_bytes("/api/phone/latest-frame")
    else:
        img_bytes = await _hub_get_bytes(f"/api/cameras/{mac}/snapshot")

    if img_bytes and len(img_bytes) > 1000:
        photo = BufferedInputFile(img_bytes, filename="snapshot.jpg")
        await callback.message.reply_photo(photo, caption="📸 MEKA Camera Snapshot")
    else:
        await callback.message.reply(
            "⚠️ Could not capture snapshot.\n"
            f"📱 Open phone bridge to share your camera:\n`{HUB_URL}/phone-bridge`",
            parse_mode="Markdown"
        )


@admin_router.callback_query(F.data == "cameras_refresh")
async def handle_cameras_refresh(callback: CallbackQuery):
    """Refresh camera list."""
    if not await is_admin(callback.from_user.id, callback.from_user.username):
        await callback.answer("Unauthorized", show_alert=True)
        return
    await callback.answer("🔄 Refreshed")
    # Re-run full cameras command logic inline
    data = await _hub_get("/api/cameras/all-streams")
    cameras = data.get("cameras", []) if data else []
    keyboard = []
    text = "📷 **MEKA Camera System** _(refreshed)_\n\n"
    for cam in cameras:
        status = "🟢" if cam.get("online") else "🔴"
        name   = cam.get("name") or cam.get("device_type") or "Camera"
        ip     = cam.get("ip", "—")
        mac    = cam.get("mac", "")
        text  += f"{status} **{name}** — `{ip}`\n"
        keyboard.append([
            InlineKeyboardButton(text=f"📸 Snapshot — {name}", callback_data=f"camsnap_{mac}")
        ])
    keyboard.append([InlineKeyboardButton(text="🎥 Open Phone Bridge", url=f"{HUB_URL}/phone-bridge")])
    keyboard.append([InlineKeyboardButton(text="🔄 Refresh", callback_data="cameras_refresh")])
    try:
        await callback.message.edit_text(
            text if cameras else "📷 No cameras discovered.\n",
            parse_mode="Markdown",
            reply_markup=InlineKeyboardMarkup(inline_keyboard=keyboard)
        )
    except Exception:
        pass


# ── /snapshot ─────────────────────────────────────────────────────────

@admin_router.message(Command("snapshot"))
async def cmd_snapshot(message: Message):
    """Pull the latest phone bridge frame as a photo."""
    if not await is_admin(message.from_user.id, message.from_user.username):
        return

    await message.bot.send_chat_action(chat_id=message.chat.id, action="upload_photo")
    msg = await message.reply("📸 Capturing from phone bridge...")

    img_bytes = await _hub_get_bytes("/api/phone/latest-frame")
    if img_bytes and len(img_bytes) > 1000:
        photo = BufferedInputFile(img_bytes, filename="meka_snapshot.jpg")
        await message.reply_photo(photo, caption="📸 MEKA Live Camera Snapshot")
        await msg.delete()
    else:
        await msg.edit_text(
            "⚠️ No frame available yet.\n\n"
            f"📱 Open phone bridge on your phone:\n`{HUB_URL}/phone-bridge`\n"
            "Connect and enable Camera sharing, then try again.",
            parse_mode="Markdown"
        )


# ── /speakers ─────────────────────────────────────────────────────────

@admin_router.message(Command("speakers"))
async def cmd_speakers(message: Message):
    """List all network speakers with control buttons."""
    if not await is_admin(message.from_user.id, message.from_user.username):
        return

    await message.bot.send_chat_action(chat_id=message.chat.id, action="typing")
    data = await _hub_get("/api/audio/speakers")

    if data is None:
        await message.reply("⚠️ IoT Hub is offline. Start the hub first.", parse_mode="Markdown")
        return

    speakers = data.get("speakers", [])
    if not speakers:
        await message.reply("🔊 No speakers discovered yet.")
        return

    text = "🔊 **MEKA Speaker System**\n\n"
    keyboard = []
    for spk in speakers:
        status   = "🟢" if spk.get("online") else "🔴"
        active   = " ✅ **(Active)**" if spk.get("is_active") else ""
        name     = spk.get("name") or spk.get("device_type") or "Speaker"
        ip       = spk.get("ip", "—")
        mac      = spk.get("mac", "")
        text    += f"{status} **{name}**{active} — `{ip}`\n"
        if not spk.get("is_active") and spk.get("online"):
            keyboard.append([
                InlineKeyboardButton(
                    text=f"🎯 Set Active — {name}",
                    callback_data=f"setspk_{mac}"
                )
            ])

    text += "\nUse `/play <text>` to speak through the active speaker."
    await message.reply(text, parse_mode="Markdown",
                        reply_markup=InlineKeyboardMarkup(inline_keyboard=keyboard) if keyboard else None)


@admin_router.callback_query(F.data.startswith("setspk_"))
async def handle_set_speaker(callback: CallbackQuery):
    """Set a speaker as active."""
    if not await is_admin(callback.from_user.id, callback.from_user.username):
        await callback.answer("Unauthorized", show_alert=True)
        return

    mac = callback.data.replace("setspk_", "")
    result = await _hub_post("/api/audio/speaker/select", {"mac": mac})
    if result:
        await callback.answer("✅ Speaker activated!", show_alert=False)
        await callback.message.reply(f"✅ Speaker `{mac}` is now the active output device.", parse_mode="Markdown")
    else:
        await callback.answer("❌ Failed to set speaker", show_alert=True)


# ── /play ─────────────────────────────────────────────────────────────

@admin_router.message(Command("play"))
async def cmd_play(message: Message):
    """Play text-to-speech through the active hub speaker."""
    if not await is_admin(message.from_user.id, message.from_user.username):
        return

    args = message.text.split(maxsplit=1)
    if len(args) < 2:
        await message.reply("Usage: `/play <text to speak>`", parse_mode="Markdown")
        return

    text = args[1].strip()
    await message.bot.send_chat_action(chat_id=message.chat.id, action="typing")

    result = await _hub_post("/api/audio/play", {"text": text})
    if result and result.get("status") == "broadcast":
        await message.reply(
            f"🔊 *Broadcasting:* _{text}_\n\n"
            f"Sent to all connected phone bridge speakers.",
            parse_mode="Markdown"
        )
    else:
        await message.reply(
            "⚠️ Hub is offline or could not broadcast.\n"
            "Start the hub and connect a phone via the bridge.",
            parse_mode="Markdown"
        )


# ── /permissions ──────────────────────────────────────────────────────

@admin_router.message(Command("permissions"))
async def cmd_permissions(message: Message):
    """View and manage device permissions on the Wi-Fi / Hotspot network."""
    if not await is_admin(message.from_user.id, message.from_user.username):
        return

    await message.bot.send_chat_action(chat_id=message.chat.id, action="typing")
    data = await _hub_get("/api/permissions")

    if not data or "devices" not in data:
        await message.reply("⚠️ Hub offline or could not fetch permissions.", parse_mode="Markdown")
        return

    devices = data.get("devices", [])
    if not devices:
        await message.reply("🛡️ **No network devices discovered yet.**", parse_mode="Markdown")
        return

    text = "🛡️ **MEKA Device Permission System**\n\n"
    keyboard = []
    for dev in devices:
        status_icon = "🟢" if dev.get("permission") == "granted" else "🔴" if dev.get("permission") == "denied" else "🟡"
        ip = dev.get("ip", "—")
        mac = dev.get("mac", "")
        name = dev.get("friendly_name") or dev.get("vendor") or dev.get("device_type") or "Wi-Fi Device"
        text += f"{status_icon} **{name}** — `{ip}` ({dev.get('permission', 'pending').upper()})\n"

        keyboard.append([
            InlineKeyboardButton(text=f"📲 Trigger Popup — {ip}", callback_data=f"promptperm_{mac}"),
            InlineKeyboardButton(text=f"🟢 Grant", callback_data=f"grantperm_{mac}"),
            InlineKeyboardButton(text=f"🚫 Revoke", callback_data=f"denyperm_{mac}"),
        ])

    await message.reply(text, parse_mode="Markdown", reply_markup=InlineKeyboardMarkup(inline_keyboard=keyboard))


@admin_router.callback_query(F.data.startswith("promptperm_"))
async def handle_prompt_perm(callback: CallbackQuery):
    mac = callback.data.replace("promptperm_", "")
    res = await _hub_post(f"/api/permissions/prompt/{mac}", {})
    if res:
        await callback.answer("📲 Permission request popup sent to device screen!", show_alert=True)
    else:
        await callback.answer("❌ Failed to send popup request", show_alert=True)


@admin_router.callback_query(F.data.startswith("grantperm_"))
async def handle_grant_perm(callback: CallbackQuery):
    mac = callback.data.replace("grantperm_", "")
    res = await _hub_post("/api/permissions/grant", {"mac": mac})
    if res:
        await callback.answer("🟢 Permission GRANTED!", show_alert=False)
        await callback.message.reply(f"🟢 Device `{mac}` permission set to GRANTED.", parse_mode="Markdown")
    else:
        await callback.answer("❌ Failed to grant permission", show_alert=True)


@admin_router.callback_query(F.data.startswith("denyperm_"))
async def handle_deny_perm(callback: CallbackQuery):
    mac = callback.data.replace("denyperm_", "")
    res = await _hub_post("/api/permissions/deny", {"mac": mac})
    if res:
        await callback.answer("🚫 Permission REVOKED!", show_alert=False)
        await callback.message.reply(f"🚫 Device `{mac}` permission set to DENIED.", parse_mode="Markdown")
    else:
        await callback.answer("❌ Failed to revoke permission", show_alert=True)

