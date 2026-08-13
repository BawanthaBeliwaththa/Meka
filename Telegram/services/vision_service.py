import os
import io
import time
import requests
import logging
import urllib3
from google import genai
from dotenv import load_dotenv

# Suppress InsecureRequestWarning from verify=False calls to ESP32/Hub with self-signed certs
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

load_dotenv()
logger = logging.getLogger(__name__)

# ESP32-CAM direct capture URL (if module attached)
ESP32_IP = os.getenv("ESP32_IP", "meka.local")

# IoT Hub phone-bridge snapshot fallback
HUB_IP   = os.getenv("HUB_IP",    "localhost")
HUB_PORT = os.getenv("HUB_PORT",  "5000")
HUB_PROTO = os.getenv("HUB_PROTO", "https")

def get_gemini_client():
    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key:
        return None
    try:
        return genai.Client(api_key=api_key)
    except Exception as e:
        logger.error(f"Failed to initialize Gemini client in vision_service: {e}")
        return None

class VisionService:
    def __init__(self):
        self.esp32_url  = f"http://{ESP32_IP}/capture"
        self.hub_url    = f"{HUB_PROTO}://{HUB_IP}:{HUB_PORT}/api/phone/latest-frame"

    def capture_image(self) -> bytes:
        """Fetches a JPEG frame — tries ESP32 camera first, then hub phone-bridge."""
        # --- Try ESP32-CAM directly ---
        try:
            logger.info(f"Trying ESP32 capture: {self.esp32_url}")
            response = requests.get(self.esp32_url, timeout=5, verify=False)
            if response.status_code == 200 and len(response.content) > 1000:
                logger.info("ESP32 capture successful")
                return response.content
        except Exception as e:
            logger.warning(f"ESP32 camera unavailable: {e}")

        # --- Fallback: phone bridge latest frame ---
        try:
            logger.info(f"Trying hub phone-bridge: {self.hub_url}")
            response = requests.get(self.hub_url, timeout=8, verify=False)
            if response.status_code == 200 and len(response.content) > 1000:
                logger.info("Phone bridge capture successful")
                return response.content
        except Exception as e:
            logger.warning(f"Hub phone bridge unavailable: {e}")

        logger.error("All camera sources failed")
        return None

    def analyze_image(self, prompt: str, image_bytes: bytes) -> str:
        """Sends the image to Gemini Vision for analysis."""
        if not image_bytes:
            return "Error: I couldn't capture an image from my camera right now. I might be blind!"
        
        client = get_gemini_client()
        if not client:
            return "Gemini API key is not configured in .env."

        try:
            logger.info("Analyzing image with Gemini Pro Vision...")
            response = client.models.generate_content(
                model="gemini-2.5-flash",
                contents=[
                    prompt,
                    {
                        "mime_type": "image/jpeg",
                        "data": image_bytes
                    }
                ]
            )
            return response.text
        except Exception as e:
            logger.error(f"Gemini Vision failed: {e}")
            return "My vision processing circuits encountered an error. I can't analyze this right now."

vision_service = VisionService()
