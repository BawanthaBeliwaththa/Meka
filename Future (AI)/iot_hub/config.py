# Meka IoT Hub — Configuration
# ──────────────────────────────────────────────────────────────────────

import os

# ── Network Scanner ──────────────────────────────────────────────────
SCAN_INTERVAL_SECONDS = 60          # Background scan interval
SCAN_TIMEOUT_SECONDS = 3            # ARP/TCP timeout
MDNS_BROWSE_TIMEOUT = 5             # mDNS browse duration
SSDP_TIMEOUT = 3                    # UPnP SSDP timeout

# ── Camera Ports ─────────────────────────────────────────────────────
CAMERA_PORTS = [554, 8554, 80, 8080, 8899, 37777, 8000, 443]
RTSP_PORTS = [554, 8554]
ONVIF_PORTS = [8899, 80, 8080]
HTTP_STREAM_PORTS = [80, 8080, 81]

# ── Service Ports ────────────────────────────────────────────────────
SPEAKER_PORTS = [8008, 8009, 1400, 3689]   # Chromecast, Sonos, iTunes
MIC_PORTS = [5050]                          # Meka companion agent
MEKA_AGENT_PORT = 5050                      # Companion agent port

# ── Hub Server ───────────────────────────────────────────────────────
HUB_HOST = "0.0.0.0"
HUB_PORT = 5000
HUB_SECRET = os.environ.get("MEKA_HUB_SECRET", "meka-iot-2024")

# ── Storage ──────────────────────────────────────────────────────────
DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
DB_PATH = os.path.join(DATA_DIR, "devices.db")
RECORDINGS_DIR = os.path.join(DATA_DIR, "recordings")
SNAPSHOTS_DIR = os.path.join(DATA_DIR, "snapshots")

# ── Device Classification ────────────────────────────────────────────
# MAC vendor prefixes that indicate camera manufacturers
CAMERA_VENDORS = [
    "hikvision", "dahua", "axis", "vivotek", "sony", "panasonic",
    "trendnet", "foscam", "reolink", "amcrest", "wyze", "eufy",
    "tp-link", "tapo", "ezviz", "uniview", "hanwha", "bosch",
    "avigilon", "pelco", "geovision", "acti", "mobotix",
]

SPEAKER_VENDORS = [
    "google", "amazon", "sonos", "bose", "harman", "jbl",
    "apple", "samsung", "lg", "marshall",
]

PHONE_VENDORS = [
    "apple", "samsung", "xiaomi", "huawei", "oneplus", "oppo",
    "vivo", "realme", "motorola", "nokia", "google", "sony",
    "lg", "zte", "tcl", "honor",
]

PC_VENDORS = [
    "dell", "hp", "lenovo", "asus", "acer", "msi", "intel",
    "microsoft", "gigabyte", "asrock",
]

# ── Device Types ─────────────────────────────────────────────────────
DEVICE_TYPE_CAMERA = "camera"
DEVICE_TYPE_SPEAKER = "speaker"
DEVICE_TYPE_PHONE = "phone"
DEVICE_TYPE_PC = "pc"
DEVICE_TYPE_IOT = "iot"
DEVICE_TYPE_MEKA_NODE = "meka_node"
DEVICE_TYPE_ESP32_NODE = "esp32_node"        # Physical MEKA ESP32 product node
DEVICE_TYPE_BLUETOOTH_SPEAKER = "bt_speaker"
DEVICE_TYPE_BLUETOOTH_MIC = "bt_mic"
DEVICE_TYPE_UNKNOWN = "unknown"

# ── Product Info ─────────────────────────────────────────────────────
MEKA_PRODUCT_VERSION = "3.0"
MEKA_PRODUCT_NAME = "MEKA Smart Home Hub"

# ── Permission States ────────────────────────────────────────────────
PERM_PENDING = "pending"
PERM_GRANTED = "granted"
PERM_DENIED = "denied"

# ── Capability Flags ─────────────────────────────────────────────────
CAP_CAMERA = "camera"
CAP_MICROPHONE = "microphone"
CAP_MIC = "mic"                     # Alias for CAP_MICROPHONE
CAP_SPEAKER = "speaker"
CAP_RELAY = "relay"
CAP_SENSOR = "sensor"
CAP_DISPLAY = "display"
CAP_LED = "led"                     # RGB/status LEDs on ESP32
CAP_SERVO = "servo"                 # Servo motor control
CAP_BUZZER = "buzzer"               # Piezo buzzer

# ── Fallback Priority ────────────────────────────────────────────────
# Lower number = higher priority
FALLBACK_PRIORITY = {
    DEVICE_TYPE_CAMERA: 1,      # Dedicated IP cameras first
    DEVICE_TYPE_MEKA_NODE: 2,   # ESP32-CAM nodes
    DEVICE_TYPE_PHONE: 3,       # Phone cameras
    DEVICE_TYPE_PC: 4,          # Laptop/PC webcams
    "local": 99,                # Local device hardware (last resort)
}

# Ensure data directories exist
os.makedirs(DATA_DIR, exist_ok=True)
os.makedirs(RECORDINGS_DIR, exist_ok=True)
os.makedirs(SNAPSHOTS_DIR, exist_ok=True)
