# 🖥️ MEKA Windows Desktop App

<p align="center">
  <a href="https://github.com/project-meka/Windows-APP/releases/latest">
    <img src="https://img.shields.io/github/v/release/project-meka/Windows-APP?style=for-the-badge&logo=windows&color=00D4FF&label=LATEST%20RELEASE" alt="Latest Release"/>
  </a>
  <a href="https://github.com/project-meka/Windows-APP/releases/latest">
    <img src="https://img.shields.io/github/downloads/project-meka/Windows-APP/total?style=for-the-badge&color=7C4DFF&label=TOTAL%20DOWNLOADS" alt="Total Downloads"/>
  </a>
  <img src="https://img.shields.io/badge/Windows-10%2F11-0078D4?style=for-the-badge&logo=windows11" alt="Windows 10/11"/>
  <img src="https://img.shields.io/badge/Flutter-3.24-00B4D8?style=for-the-badge&logo=flutter" alt="Flutter"/>
</p>

> **MEKA** — Master Electronic Kinetic Assistant. A premium cyberpunk-themed desktop client for your MEKA smart home AI assistant. Control ESP32 devices, run voice AI, and monitor your home from your workstation.

---

## ⬇️ Download & Install

### [→ Download Latest from GitHub Releases](https://github.com/project-meka/Windows-APP/releases/latest)

| File | Description |
|------|-------------|
| `MEKA-vX.X.X-Windows-Setup.exe` | **Installer** (Start Menu + Desktop shortcut) |
| `MEKA-vX.X.X-Windows-Portable.zip` | **Portable** — no install, extract & run anywhere |

### Option 1: Installer
1. Download `MEKA-vX.X.X-Windows-Setup.exe`
2. If Windows SmartScreen appears → click **"More info"** → **"Run anyway"**
3. Follow the installer, then launch from Desktop/Start Menu

### Option 2: Portable
1. Download `MEKA-vX.X.X-Windows-Portable.zip`
2. Extract to any folder (e.g. `C:\MEKA`)
3. Run `meka_desktop.exe`

---

## 🚀 Features

- 💬 **AI Chat** — Gemini-powered conversations with full context
- 🏠 **Multi-hub support** — setup wizard for first-time configuration + hub switching
- 💡 **ESP32 Sidebar Panel** — LED controls, servo, temperature/humidity per node
- 📡 **Real-time hub status** — online/offline indicator with live ping
- 🖥️ **Workstation integration** — system tray, minimize to tray
- 🎙️ **Voice commands** — speak to MEKA directly from your desk
- 🔌 **ADB Manager** — wireless Android Debug Bridge control panel
- 📋 **Audit Log** — full history of MEKA actions

---

## 📋 Requirements

- Windows **10 or 11** (64-bit only)
- 200MB free disk space
- Wi-Fi connection to your MEKA Hub

---

## 🔧 Build from Source

```bash
git clone https://github.com/project-meka/Windows-APP.git
cd Windows-APP
flutter pub get
flutter build windows --release
# Output: build\windows\x64\runner\Release\
```

---

## 📦 Related Repositories

| Repo | Description |
|------|-------------|
| [Android-APP](https://github.com/project-meka/Android-APP) | Android 7+ mobile client (APK) |
| [Linux-APP](https://github.com/project-meka/Linux-APP) | Linux desktop (AppImage, .deb) |
| [MEKA-Hub](https://github.com/project-meka/MEKA-Hub) | Python IoT Hub backend |
| [ESP32-Firmware](https://github.com/project-meka/ESP32-Firmware) | Hardware firmware |
