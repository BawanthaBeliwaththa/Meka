# MEKA V3 - Full Project How-To Guide

Welcome to the MEKA V3 project! This guide will take you step-by-step through setting up the ultimate AI-powered smart node, complete with a Telegram Bot, Web App, LCD Display, Firebase synchronization, and the newly added **Voice, Vision, and Cloud Capabilities**.

---

## 1. Hardware Requirements

### Base Components (Always Required)
- **ESP32 Development Board** (ESP32-S3 or ESP32-CAM recommended for full features)
- **1602 LCD Display** (with I2C module)
- **DHT11 / DHT22** (Temperature & Humidity Sensor)
- **SG90 Servo Motor**
- **4x LEDs** (Blue, Yellow, Green, Red) with 220Ω resistors

### V3 Expansion Components
- **Microphone:** INMP441 (I2S Digital Microphone)
- **Speaker:** MAX98357A (I2S Amplifier) + 3W 4Ω Speaker
- **Camera:** OV2640 Camera Module (requires ESP32-CAM or ESP32-S3 with PSRAM)

---

## 2. Hardware Wiring Guide

### Standard Sensors & Outputs
* **I2C LCD:** `SDA -> GPIO 21`, `SCL -> GPIO 22`
* **Servo Motor:** `Signal -> GPIO 13`
* **DHT Sensor:** `Data -> GPIO 4`
* **LEDs:** `Blue -> 26`, `Yellow -> 27`, `Green -> 14`, `Red -> 12`

### V3 Audio & Vision Expansion (I2S)
* **INMP441 Mic:** `SCK -> 32`, `WS -> 33`, `SD -> 34`, `L/R -> GND`
* **MAX98357A Speaker:** `BCLK -> 25`, `LRC -> 15`, `DIN -> 2`
* *(Note: Camera wiring is built into the ESP32-CAM board. If using an S3, refer to standard 24-pin camera wiring).*

---

## 3. 3D Printing the Enclosure

We have provided a custom 3D design for the MEKA chassis.
1. Open the `meka_chassis.scad` (or `3d_print_design/meka_enclosure.scad`) file using **OpenSCAD**.
2. Press `F6` to render the model.
3. Press `F7` to export it as an `.STL` file.
4. Slice in Cura or PrusaSlicer (Recommended: 20% Infill, PLA/PETG, No Supports needed for the main body if oriented correctly).

---

## 4. Software Setup

### A. ESP32 Firmware
1. Open the project in **PlatformIO** (VS Code).
2. Ensure you have the `Firebase ESP Client`, `ArduinoJson`, `ESP32Servo`, and `hd44780` libraries installed.
3. Edit the Wi-Fi credentials and Firebase database URL/Keys in the `.env` or configuration file.
4. Run the upload command: `pio run --target upload`.

### B. Python Telegram Bot
1. Navigate to the `telegram_bot` directory.
2. Install dependencies: `pip install -r requirements.txt`
3. Configure your `.env` file with:
   - `TELEGRAM_BOT_TOKEN`
   - `GEMINI_API_KEY`
   - `FIREBASE_CREDENTIALS_PATH` (Point to your downloaded service account JSON)
   - `ONEDRIVE_CLIENT_ID`, `ONEDRIVE_CLIENT_SECRET`, `ONEDRIVE_TENANT_ID`, and `ONEDRIVE_USER_ID` (For cloud storage).
4. Run the bot: `python bot.py`

### C. React Web App
1. Navigate to the `webapp` directory.
2. Install dependencies: `npm install`
3. Configure your `src/firebase.js` with your Firebase web configuration.
4. Start the app: `npm run dev`

---

## 5. Setting up OneDrive (Microsoft Graph API)

To enable the new `[CAPTURE_PHOTO]` and `[CAPTURE_VIDEO]` features:
1. Go to the [Azure Portal](https://portal.azure.com/).
2. Create a new "App Registration".
3. Under **API Permissions**, add `Files.ReadWrite` (Microsoft Graph).
4. Under **Certificates & secrets**, generate a Client Secret.
5. Copy the Client ID, Tenant ID, and Secret into your Telegram bot's `.env` file.

---

## 6. How to Use MEKA

- **Telegram:** Send a message to your bot. If you say "Take a photo of what you see", the bot will use the Gemini Vision API to trigger the ESP32 camera, fetch the JPEG frame, analyze it, send the picture to Telegram, and permanently back it up to your OneDrive!
- **Web App:** Go to the `/user` dashboard to see real-time sensor updates and interact with the AI via the text console.
- **Physical Voice:** Speak to the INMP441 mic (once fully wired). MEKA will transcribe your voice using Gemini STT and speak back via the I2S speaker using Google TTS!

*Enjoy your fully integrated Smart AI Node!*
