import logging
import asyncio
import os
import time
import firebase_admin
from firebase_admin import credentials, db

logger = logging.getLogger(__name__)

# ── Firebase Init ──────────────────────────────────────────────────────────
# Reads FIREBASE_SERVICE_ACCOUNT_JSON path from env, or uses Application Default Credentials
_firebase_app = None

def _get_firebase_app():
    global _firebase_app
    if _firebase_app is None:
        db_url = os.getenv("FIREBASE_DATABASE_URL")
        if not db_url:
            raise ValueError("FIREBASE_DATABASE_URL not set in .env")

        sa_path = os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON")
        if sa_path and os.path.exists(sa_path):
            cred = credentials.Certificate(sa_path)
        else:
            cred = credentials.ApplicationDefault()

        bucket = os.getenv("FIREBASE_STORAGE_BUCKET")
        _firebase_app = firebase_admin.initialize_app(cred, {
            "databaseURL": db_url,
            "storageBucket": bucket
        })
    return _firebase_app

def _meka_ref(path: str = ""):
    """Returns a Firebase reference under /meka/<path>."""
    _get_firebase_app()
    return db.reference(f"/meka{path}")

# ── Status Control ─────────────────────────────────────────────────────────

async def set_status(status: str):
    """
    Sets MEKA's status in Firebase, which the ESP32 will react to instantly.
    status: 'listening' | 'processing' | 'success' | 'error' | 'idle'
    """
    try:
        await asyncio.to_thread(_meka_ref("/status").set, status)
        logger.info(f"Firebase status → {status}")
    except Exception as e:
        logger.error(f"Firebase set_status failed: {e}")

async def send_display_q(question: str):
    """Sends the Question to Firebase for the LCD top line."""
    clean = question.replace("\n", " ").strip()
    try:
        await asyncio.to_thread(_meka_ref("/lcd_q").set, clean)
        logger.info(f"Firebase lcd_q updated: {clean[:20]}...")
    except Exception as e:
        logger.error(f"Firebase send_display_q failed: {e}")

async def send_display_a(answer: str):
    """Sends the Answer to Firebase for the LCD bottom line. Also updates /lcd_text for backward compatibility."""
    clean = answer.replace("\n", " ").strip()
    try:
        await asyncio.to_thread(_meka_ref("/lcd_a").set, clean)
        # Backward compatibility for old ESP32 firmware
        await asyncio.to_thread(_meka_ref("/lcd_text").set, clean)
        logger.info(f"Firebase lcd_a updated: {clean[:20]}...")
    except Exception as e:
        logger.error(f"Firebase send_display_a failed: {e}")


async def control_hardware(device: str, param1: str, param2: str = None):
    """
    Writes a hardware command to Firebase for the ESP32 to pick up.
    device: 'buzzer' | 'servo'
    """
    try:
        if device == "buzzer":
            payload = {"duration_ms": int(param1), "ts": int(time.time())}
            await asyncio.to_thread(_meka_ref("/buzzer_cmd").set, payload)
        elif device == "servo":
            payload = {"angle": int(param1), "ts": int(time.time())}
            await asyncio.to_thread(_meka_ref("/servo_cmd").set, payload)
        else:
            logger.warning(f"Unknown device: {device}")
    except Exception as e:
        logger.error(f"Firebase control_hardware failed: {e}")

async def log_command(source: str, command: str, response: str, status: str = "success"):
    """Logs every command interaction to Firebase for the web panel history."""
    try:
        entry = {
            "source":   source,
            "command":  command[:200],
            "response": response[:300],
            "status":   status,
            "ts":       int(time.time())
        }
        await asyncio.to_thread(_meka_ref("/command_log").push, entry)
        logger.info(f"Firebase command logged from {source}")
    except Exception as e:
        logger.error(f"Firebase log_command failed: {e}")


async def get_body_sensors() -> dict:
    """Reads live physical telemetry (DHT sensors, head angle, LCD, status) from Firebase."""
    try:
        snapshot = await asyncio.to_thread(_meka_ref("").get)
        if not snapshot or not isinstance(snapshot, dict):
            return {}
        sensors = snapshot.get("sensors", {})
        servo = snapshot.get("servo_cmd", {})
        return {
            "temperature_c": sensors.get("temperature_c"),
            "humidity":      sensors.get("humidity"),
            "status":        snapshot.get("status", "idle"),
            "lcd_text":      snapshot.get("lcd_text", ""),
            "servo_angle":   servo.get("angle") if isinstance(servo, dict) else None,
        }
    except Exception as e:
        logger.error(f"Firebase get_body_sensors failed: {e}")
        return {}

