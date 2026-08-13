import os
import uuid
import logging
from gtts import gTTS
from google import genai
from dotenv import load_dotenv

load_dotenv()
logger = logging.getLogger(__name__)

_gemini_api_key = os.getenv("GEMINI_API_KEY")
gemini_client = genai.Client(api_key=_gemini_api_key) if _gemini_api_key else None

class VoiceService:
    def __init__(self):
        self.audio_dir = "static/audio"
        os.makedirs(self.audio_dir, exist_ok=True)

    def generate_tts(self, text: str) -> str:
        """Generates TTS audio from text and returns the file path."""
        try:
            filename = f"response_{uuid.uuid4().hex[:8]}.mp3"
            filepath = os.path.join(self.audio_dir, filename)
            
            tts = gTTS(text=text, lang="en", slow=False)
            tts.save(filepath)
            
            logger.info(f"Generated TTS audio: {filepath}")
            return filepath
        except Exception as e:
            logger.error(f"Failed to generate TTS: {e}")
            return None

    def speech_to_text(self, audio_bytes: bytes, mime_type: str = "audio/wav") -> str:
        """Uses Gemini 1.5 Multimodal to transcribe audio."""
        if not audio_bytes:
            return ""
            
        try:
            if not gemini_client:
                return ""
            logger.info("Transcribing audio with Gemini...")
            response = gemini_client.models.generate_content(
                model="gemini-1.5-flash",
                contents=[
                    "Please transcribe this audio exactly as spoken.",
                    {
                        "mime_type": mime_type,
                        "data": audio_bytes
                    }
                ]
            )
            return response.text.strip()
        except Exception as e:
            logger.error(f"Audio transcription failed: {e}")
            return ""

voice_service = VoiceService()
