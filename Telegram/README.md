# MEKA Telemetry & Command: Telegram Bot Integration

This repository encapsulates the secure remote-control integration for **Project MEKA**, powered by the Telegram Bot API. 

Designed as a fail-safe command-and-control bridge, this Python-based daemon runs independently of the MEKA hardware, allowing administrators to interface with the MEKA ecosystem from anywhere in the world.

## Core Responsibilities & Features

### 1. Secure Authentication & Authorization
The bot utilizes a strict access-control list (ACL) defined in the Firebase Realtime Database. It distinguishes between standard users and system administrators, silently dropping commands from unauthorized Telegram IDs to maintain absolute security.

### 2. Real-Time Hardware Routing
Through direct synchronization with the MEKA Firebase state tree, the bot can dynamically alter the physical routing of MEKA's hardware. 
- **Audio Control:** Toggle microphone inputs and speaker outputs remotely.
- **Visuals:** Override the physical ESP32 LCD matrix to display specific messages.
- **Camera Access:** Securely retrieve live image feeds from MEKA's optical sensors.

### 3. System Telemetry & Status
Administrators can request comprehensive diagnostic reports, including:
- Current active client connections (Desktop/Mobile).
- ESP32 hardware health and uptime.
- Latest conversational logs and system errors.

## Technical Stack
- **Language:** Python 3.10+
- **Frameworks:** `python-telegram-bot` (Asynchronous event loop)
- **Cloud Integration:** `firebase-admin` for secure backend mutations.
- **Containerization:** Pre-configured `Dockerfile` and `docker-compose.yml` for rapid, isolated deployment on any VPS or local server.
