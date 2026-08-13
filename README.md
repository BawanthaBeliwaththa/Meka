# 🤖 Project MEKA: Master Electronic Kinetic Assistant
### *Next-Generation Decentralized AI Assistant & Multi-Hub Commercial Smart Home Ecosystem*

[![MEKA Multi-Platform Build & Release](https://github.com/BawanthaBeliwaththa/Meka/actions/workflows/release.yml/badge.svg)](https://github.com/BawanthaBeliwaththa/Meka/actions/workflows/release.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-cyan.svg)](https://opensource.org/licenses/MIT)
[![Version: v3.0.0](https://img.shields.io/badge/Version-v3.0.0-7C3AED.svg)](https://github.com/BawanthaBeliwaththa/Meka/releases)

---

Welcome to **Project MEKA**, an advanced, enterprise-grade, decentralized personal AI assistant and smart home platform. Built for both personal deployment and commercial distribution (white-label Multi-ESP32 smart homes), MEKA separates physical hardware nodes, core AI processing, real-time telemetry, and multi-platform client applications into robust, fault-tolerant modules.

---

## 🌟 Executive Features & Capabilities

- 🧠 **Decentralized AI Brain & Local IoT Hub**: Python FastAPI/Flask backend providing zero-latency LLM routing, device telemetry logging, and multi-hub profile synchronization.
- 📱 **Native Mobile Client (Android)**: Flutter app featuring real-time voice activation, QR hub onboarding, ESP32 quick-action switches, and background wake locks.
- 🖥️ **Native Desktop Clients (Windows & Linux)**: Cyberpunk-styled desktop suites with hardware telemetry cards, speech-to-text input, and direct hub control.
- 🌌 **Cybernetic Web Dashboard**: React + Three.js dynamic orb visualization, real-time Firebase & WebSocket telemetry, and ESP32 node administration.
- ⚡ **Multi-ESP32 Commercial Hardware Architecture**: Supports unlimited ESP32 microcontrollers per household (Living Room, Kitchen, Bedrooms) with automated Wi-Fi provisioning and REST API heartbeat monitoring.
- ✈️ **Telegram Control Bot**: Remote command-and-control bot for status queries, emergency overrides, and micro-controller relays.

---

## 🏗️ Ecosystem Architecture

```
                               ┌─────────────────────────┐
                               │   MEKA Cloud / Local    │
                               │   Firebase & WebSockets │
                               └───────────┬─────────────┘
                                           │
         ┌─────────────────────────────────┼─────────────────────────────────┐
         │                                 │                                 │
┌────────▼────────┐               ┌────────▼────────┐               ┌────────▼────────┐
│  Android App    │               │   Windows App   │               │    Linux App    │
│ (Flutter APK)   │               │  (Win32 / NSIS) │               │   (.deb Package)│
└────────┬────────┘               └────────┬────────┘               └────────┬────────┘
         │                                 │                                 │
         └─────────────────────────────────┼─────────────────────────────────┘
                                           │
                               ┌───────────▼───────────┐
                               │   Future (AI) Hub     │
                               │   IoT Gateway (Py)    │
                               └───────────┬───────────┘
                                           │
         ┌─────────────────────────────────┼─────────────────────────────────┐
         │                                 │                                 │
┌────────▼────────┐               ┌────────▼────────┐               ┌────────▼────────┐
│ ESP32 Node #1   │               │ ESP32 Node #2   │               │ ESP32 Node #N   │
│ (Living Room)   │               │ (Master Bedroom)│               │ (Kitchen / Yard)│
└─────────────────┘               └─────────────────┘               └─────────────────┘
```

---

## 📥 Installation & Download Guidance

Pre-compiled production binaries for all operating systems are generated automatically via GitHub Actions:
👉 **[Download MEKA Releases](https://github.com/BawanthaBeliwaththa/Meka/releases)**

### 📱 1. Android Installation
- **Universal APK**: Download `MEKA-v3.0.0-Android-Universal.apk` and tap to install on any Android 7.0+ device.
- **Architecture Specific**:
  - 64-bit ARM: `MEKA-v3.0.0-Android-arm64.apk`
  - 32-bit ARM: `MEKA-v3.0.0-Android-arm32.apk`

### 🖥️ 2. Windows Installation
- **Setup Installer**: Download `MEKA-v3.0.0-Windows-Setup.exe` and run the wizard to create Start Menu & Desktop shortcuts.
- **Portable Edition**: Download `MEKA-v3.0.0-Windows-Portable.zip`, extract to any folder, and execute `meka_desktop.exe`.

### 🐧 3. Linux Installation
- **Debian / Ubuntu / Mint**:
  ```bash
  sudo dpkg -i MEKA-v3.0.0-Linux-amd64.deb
  sudo apt-get install -f # resolve any missing runtime libs
  ```
- **Universal Linux Portable**:
  ```bash
  tar -xzf MEKA-v3.0.0-Linux.tar.gz
  cd MEKA-v3.0.0-Linux
  ./meka_linux
  ```

---

## 🚀 Quick Start & Development Setup

### 1. IoT Hub Server Setup (`Future (AI)`)
```bash
cd "Future (AI)/iot_hub"
python -m venv venv
# On Windows:
.\venv\Scripts\activate
# On Linux/macOS:
source venv/bin/activate

pip install -r requirements.txt
python hub_server.py
```
*Hub running on `http://localhost:8000` or `http://<YOUR_LOCAL_IP>:8000`*

### 2. Web Application Setup (`Webapp`)
```bash
cd Webapp
npm install
cp .env.example .env # Set your Firebase & Hub URL
npm run dev
```
*Access Web Dashboard at `http://localhost:5173`*

### 3. Telegram Telemetry Bot (`Telegram`)
```bash
cd Telegram
python -m venv venv
.\venv\Scripts\activate
pip install -r requirements.txt
cp firebase-adminsdk.json.example firebase-adminsdk.json # Add service key
python bot.py
```

### 4. Commercial ESP32 Micro-Controller Firmware (`Hardware`)
1. Open `Hardware/` in VS Code with the **PlatformIO** extension.
2. Update `config.h` with your local Wi-Fi SSIDs and MEKA IoT Hub Server IP address.
3. Connect your ESP32 board via USB.
4. Click **PlatformIO: Build & Upload**.

---

## 🔌 Hardware Wiring & ESP32 Configuration

| ESP32 Pin | Connected Component | Function |
|:---:|:---:|:---:|
| `GPIO 2` | Onboard LED | Status / Heartbeat indicator |
| `GPIO 4` | Relay Switch #1 | Living Room Main Lighting |
| `GPIO 5` | Relay Switch #2 | Fan / Climate Control |
| `GPIO 21 (SDA)` | OLED Display SSD1306 | System Status UI |
| `GPIO 22 (SCL)` | OLED Display SSD1306 | System Status Clock |
| `GPIO 34 (ADC)`| Analog DHT11 / LM35 | Temperature & Humidity Telemetry |

---

## 📄 License & Attribution

Project MEKA is released under the **MIT License**. Created by [Bawantha Beliwaththa](https://github.com/BawanthaBeliwaththa).
