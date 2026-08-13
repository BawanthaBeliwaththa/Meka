# 🐧 MEKA Linux Desktop App

<p align="center">
  <a href="https://github.com/project-meka/Linux-APP/releases/latest">
    <img src="https://img.shields.io/github/v/release/project-meka/Linux-APP?style=for-the-badge&logo=linux&color=00D4FF&label=LATEST%20RELEASE" alt="Latest Release"/>
  </a>
  <a href="https://github.com/project-meka/Linux-APP/releases/latest">
    <img src="https://img.shields.io/github/downloads/project-meka/Linux-APP/total?style=for-the-badge&color=7C4DFF&label=TOTAL%20DOWNLOADS" alt="Total Downloads"/>
  </a>
  <img src="https://img.shields.io/badge/Ubuntu-20.04%2B-E95420?style=for-the-badge&logo=ubuntu" alt="Ubuntu 20.04+"/>
  <img src="https://img.shields.io/badge/Fedora-36%2B-294172?style=for-the-badge&logo=fedora" alt="Fedora 36+"/>
  <img src="https://img.shields.io/badge/Arch-Linux-1793D1?style=for-the-badge&logo=archlinux" alt="Arch Linux"/>
  <img src="https://img.shields.io/badge/Flutter-3.24-00B4D8?style=for-the-badge&logo=flutter" alt="Flutter"/>
</p>

> **MEKA** — Master Electronic Kinetic Assistant. A native GTK3 Linux desktop client for your MEKA smart home AI assistant. Built with Flutter, runs on Ubuntu, Fedora, Arch, and any x86_64 distro.

---

## ⬇️ Download & Install

### [→ Download Latest from GitHub Releases](https://github.com/project-meka/Linux-APP/releases/latest)

| File | Format | Works On |
|------|--------|----------|
| `MEKA-vX.X.X-Linux-x86_64.AppImage` | **AppImage** | ✅ Any distro (Ubuntu, Fedora, Arch, openSUSE, etc.) |
| `meka_vX.X.X_amd64.deb` | **.deb** | ✅ Debian, Ubuntu, Mint, Pop!_OS, Elementary OS |
| `MEKA-vX.X.X-Linux.tar.gz` | **Portable tar.gz** | ✅ Any distro, manual setup |

---

### 🚀 Install — AppImage (Recommended for any distro)

```bash
# Download
wget https://github.com/project-meka/Linux-APP/releases/latest/download/MEKA-vX.X.X-Linux-x86_64.AppImage

# Make executable
chmod +x MEKA-vX.X.X-Linux-x86_64.AppImage

# Run
./MEKA-vX.X.X-Linux-x86_64.AppImage
```

> 💡 **Tip:** Use [AppImageLauncher](https://github.com/TheAssassin/AppImageLauncher) to integrate AppImage into your app launcher.

---

### 🚀 Install — .deb (Ubuntu / Debian / Mint)

```bash
# Download and install
sudo dpkg -i meka_vX.X.X_amd64.deb

# Fix any missing dependencies automatically
sudo apt-get install -f

# Launch
meka    # or find "MEKA" in your application menu
```

---

### 🚀 Install — Portable tar.gz

```bash
tar -xzf MEKA-vX.X.X-Linux.tar.gz
cd MEKA-vX.X.X-Linux/
./run-meka.sh
```

---

## 🚀 Features

- 💬 **AI Chat** — Gemini-powered voice & text interaction
- 🏠 **Multi-hub support** — setup wizard + hub switching for multi-home management
- 💡 **ESP32 Sidebar** — LED controls, servo, live temperature/humidity per node
- 🔊 **Native audio** — ALSA/PulseAudio/PipeWire integration for clear voice I/O
- 📡 **Real-time hub status** — WebSocket live updates
- 🎙️ **Voice commands** — fully hands-free via microphone
- 🔌 **ADB Manager** — wireless Android device management
- 📋 **Audit Log** — full MEKA action history

---

## 📋 System Requirements

- **OS**: 64-bit Linux x86_64 (Ubuntu 20.04+, Fedora 36+, Arch, Debian 11+, etc.)
- **Libs**: GTK3 (`libgtk-3-0`), GStreamer (`libgstreamer1.0-0`)
- **RAM**: 256MB minimum
- **Network**: Wi-Fi connection to your MEKA Hub

### Install missing dependencies (Ubuntu/Debian)
```bash
sudo apt-get install libgtk-3-0 libgstreamer1.0-0 libgstreamer-plugins-base1.0-0
```

### Install missing dependencies (Fedora/RHEL)
```bash
sudo dnf install gtk3 gstreamer1 gstreamer1-plugins-base
```

---

## 🔧 Build from Source

```bash
# Prerequisites: Flutter 3.24+ with Linux desktop enabled
flutter config --enable-linux-desktop

git clone https://github.com/project-meka/Linux-APP.git
cd Linux-APP

# Install system dependencies
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev

flutter pub get
flutter build linux --release

# Binary output:
# build/linux/x64/release/bundle/meka_linux
```

---

## 🏗️ CI/CD Architecture

Every push to a version tag (`v*`) automatically:
1. Builds on `ubuntu-22.04` runner
2. Creates AppImage (universal), `.deb`, and `.tar.gz`
3. Publishes all 3 to GitHub Releases

---

## 📦 Related Repositories

| Repo | Description |
|------|-------------|
| [Android-APP](https://github.com/project-meka/Android-APP) | Android 7+ mobile client |
| [Windows-APP](https://github.com/project-meka/Windows-APP) | Windows 10/11 desktop client |
| [MEKA-Hub](https://github.com/project-meka/MEKA-Hub) | Python IoT Hub backend |
| [ESP32-Firmware](https://github.com/project-meka/ESP32-Firmware) | Hardware ESP32 firmware |
