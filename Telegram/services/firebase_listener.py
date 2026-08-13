import logging
import asyncio
from firebase_admin import db
from services.llm_service import generate_response
import services.esp32_service as esp32_service

logger = logging.getLogger(__name__)

def on_command_input(event, loop):
    if not event.data: return
    # We only care about new commands (dict)
    data = event.data
    if isinstance(data, dict) and "command" in data:
        text = data["command"]
        source = data.get("source", "web_user")
        
        # Clear the command_input node so we don't process it again
        if event.path == "/":
            db.reference("/meka/command_input").delete()
        else:
            db.reference(f"/meka/command_input{event.path}").delete()
            
        logger.info(f"Received web command: {text}")
        
        # Dispatch to the main async loop
        asyncio.run_coroutine_threadsafe(process_web_command(text, source), loop)

async def process_web_command(prompt: str, source: str):
    logger.info(f"Processing web command from {source}: {prompt}")
    
    # 🔵 Blue LED — Listening
    await esp32_service.set_status("listening")
    
    # Update LCD to show the question
    await esp32_service.send_display_q(f"Q: {prompt}")
    await esp32_service.send_display_a("Processing...")
    
    # 🟡 Yellow LED — Processing
    await asyncio.sleep(0.5)
    await esp32_service.set_status("processing")
    
    try:
        # LLM processing
        reply = await generate_response(user_id=0, prompt=prompt) # 0 for web users
        
        # Check for [ESP_CMD: device, param1, param2]
        import re
        esp_match = re.search(r'\[ESP_CMD:\s*([^,\]]+?)\s*,\s*([^,\]]+?)(?:\s*,\s*([^,\]]+?))?\]', reply)
        if esp_match:
            device = esp_match.group(1).strip()
            param1 = esp_match.group(2).strip()
            param2 = esp_match.group(3).strip() if esp_match.group(3) else None
            asyncio.create_task(esp32_service.control_hardware(device, param1, param2))
            reply = re.sub(r'\[ESP_CMD:[^\]]+\]', '', reply).strip()
            
        # Clean tags for display
        reply = re.sub(r'\[PLAY_MUSIC:\s*(.+?)\]', '', reply).strip()
        reply = re.sub(r'\[GENERATE_IMAGE:\s*(.+?)\]', '', reply).strip()

        # Update LCD to show the answer
        await esp32_service.send_display_a(f"A: {reply}")
        
        # 🟢 Green LED — Success
        await esp32_service.set_status("success")
        await esp32_service.log_command(source, prompt, reply, "success")
        
    except Exception as e:
        logger.error(f"Error processing web command: {e}")
        # 🔴 Red LED — Error
        await esp32_service.set_status("error")
        await esp32_service.log_command(source, prompt, str(e), "error")

from services.email_service import send_admin_login_notification

def on_login_event(event, loop):
    if not event.data: return
    data = event.data
    if isinstance(data, dict) and "email" in data:
        name = data.get("name", "User")
        email = data.get("email", "")
        is_new = data.get("isNew", False)
        
        # Clear node after reading
        if event.path == "/":
            db.reference("/meka/login_events").delete()
        else:
            db.reference(f"/meka/login_events{event.path}").delete()
            
        logger.info(f"🔔 Login event received: Name={name}, Email={email}, New={is_new}")
        
        # Get list of admin emails from Firebase /meka/admins
        admin_emails = []
        try:
            admins_snap = db.reference("/meka/admins").get()
            if isinstance(admins_snap, dict):
                admin_emails = [a["email"] for a in admins_snap.values() if isinstance(a, dict) and "email" in a]
        except Exception:
            pass
        if "bawanthabeliwaththa@gmail.com" not in admin_emails:
            admin_emails.append("bawanthabeliwaththa@gmail.com")
            
        asyncio.run_coroutine_threadsafe(
            send_admin_login_notification(name, email, is_new, admin_emails),
            loop
        )

def start_firebase_listener(loop):
    esp32_service._get_firebase_app() # Ensure initialized
    
    # 1. Command Input Listener
    cmd_ref = db.reference("/meka/command_input")
    cmd_ref.delete()
    cmd_ref.listen(lambda event: on_command_input(event, loop))
    logger.info("Started listening for web commands on Firebase.")
    
    # 2. Login Events Listener for Admin Email Notifications
    login_ref = db.reference("/meka/login_events")
    login_ref.delete()
    login_ref.listen(lambda event: on_login_event(event, loop))
    logger.info("Started listening for login events on Firebase.")
