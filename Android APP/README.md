# 🤖 MEKA Android App

<p align="center">
  <img src="assets/images/logo.png" width="120" alt="MEKA Logo"/>
</p>

<p align="center">
  <a href="https://github.com/project-meka/Android-APP/releases/latest">
    <img src="https://img.shields.io/github/v/release/project-meka/Android-APP?style=for-the-badge&logo=android&color=00D4FF&label=LATEST%20RELEASE" alt="Latest Release"/>
  </a>
  <a href="https://github.com/project-meka/Android-APP/releases/latest">
    <img src="https://img.shields.io/github/downloads/project-meka/Android-APP/total?style=for-the-badge&color=7C4DFF&label=TOTAL%20DOWNLOADS" alt="Total Downloads"/>
  </a>
  <img src="https://img.shields.io/badge/Android-7.0%2B-00E676?style=for-the-badge&logo=android" alt="Android 7+"/>
  <img src="https://img.shields.io/badge/Flutter-3.24-00B4D8?style=for-the-badge&logo=flutter" alt="Flutter"/>
</p>

> **MEKA** — Master Electronic Kinetic Assistant. Your AI-powered smart home controller. Control ESP32 devices, use voice commands, and manage your home from a cyberpunk-themed mobile interface.

---

## ⬇️ Download & Install

### [→ Download Latest APK from GitHub Releases](https://github.com/project-meka/Android-APP/releases/latest)

| File | Description |
|------|-------------|
| `MEKA-vX.X.X-universal.apk` | **Recommended** — works on all Android 7+ devices |
| `MEKA-vX.X.X-arm64.apk` | Smaller download, arm64-only (most modern phones) |
| `MEKA-vX.X.X-arm32.apk` | Older 32-bit devices |

### Installation Steps
1. **Download** `MEKA-vX.X.X-universal.apk` from the Releases page
2. On your Android device: **Settings → Security → Install unknown apps** → Enable for your browser/Downloads app
3. Open the downloaded APK file → tap **Install**
4. Launch MEKA → follow the **Setup Wizard** to connect your MEKA Hub

---

## 🚀 Features

- 🎙️ **Wake word detection** — say "Hey MEKA" hands-free
- 🏠 **Multi-hub support** — manage multiple homes from one app
- 💡 **ESP32 Quick Controls** — LED colors, servo, buzzer, temp/humidity at a glance
- 🔄 **Real-time sync** — Firebase-powered instant state updates across all devices
- 🌐 **Hub Selector** — switch between homes with one tap
- 🤖 **AI Chat** — Gemini-powered conversations with your assistant

---

## 🛠️ Requirements

- Android **7.0+** (API 24+)
- Wi-Fi connection (same network as your MEKA Hub, or remote via VPS)
- Microphone permission for voice control

---

## 🔧 Build from Source

```bash
# Clone the repository
git clone https://github.com/project-meka/Android-APP.git
cd Android-APP

# Install Flutter dependencies
flutter pub get

# Run in debug mode
flutter run

# Build release APK
flutter build apk --release
```

---

## 📡 Hub Connection

Point the app to your MEKA IoT Hub:
- **Local**: `http://192.168.x.x:5000` (same Wi-Fi network)
- **Remote**: `https://your-vps.com` (via VPS deployment)
- **Auto-discover**: tap the 🔍 button in the Hub Selector

---

## 📦 Related Repositories

| Repo | Description |
|------|-------------|
| [Windows-APP](https://github.com/project-meka/Windows-APP) | Windows 10/11 desktop client |
| [Linux-APP](https://github.com/project-meka/Linux-APP) | Linux desktop client (AppImage, .deb) |
| [MEKA-Hub](https://github.com/project-meka/MEKA-Hub) | Python IoT Hub (backend) |
| [ESP32-Firmware](https://github.com/project-meka/ESP32-Firmware) | Hardware firmware |
