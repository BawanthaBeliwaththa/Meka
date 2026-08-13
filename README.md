# Project MEKA: Next-Generation Modular AI Assistant

Welcome to the central repository hub for **Project MEKA**, a highly advanced, decentralized personal AI assistant. 

Project MEKA is engineered to transcend traditional monolithic application structures. By utilizing a highly modular architecture, MEKA separates its physical hardware, core intelligence, and multi-platform clients into isolated, highly optimized partitions. This design ensures maximum scalability, fault tolerance, and cross-platform synergy.

## System Architecture

MEKA operates on a distributed architecture, seamlessly synchronized via real-time cloud infrastructure (Firebase Realtime Database) and localized WebSocket layers. The ecosystem is divided into seven core partitions:

### 1. [Future (AI) Hub](./Future (AI))
The central intelligence core and routing brain of MEKA. It currently manages external AI API bridging and device registries, with an aggressive roadmap to transition into a completely autonomous, offline, on-device AI engine (zero latency, zero external tracking).

### 2. [Hardware & Firmware](./Hardware)
The physical embodiment of MEKA. Powered by the ESP32 microcontroller, this repository contains the embedded C++ firmware that drives MEKA's sensory inputs, LCD matrix displays, and physical actuators, alongside the 3D printable chassis schematics.

### 3. [Cybernetic Web Dashboard](./Webapp)
A cutting-edge, cyberpunk-themed web application built in React. It serves as the visual command center, offering real-time telemetry, sensor monitoring, and administrative overrides through a stunning graphical interface.

### 4. [Telegram Telemetry Bot](./Telegram)
A secure, Python-based remote command-and-control interface. It allows administrators to securely authenticate, query system status, and execute low-level hardware routing commands (e.g., mic/speaker toggles) directly from the Telegram app.

### 5. Mobile & Desktop Ecosystem
Built utilizing a shared Flutter codebase, MEKA provides native client applications across all major operating systems to ensure the assistant is accessible anywhere:
- **[Android App](./Android APP):** The mobile bridge for on-the-go voice interaction and configuration.
- **[Linux App](./Linux APP):** Native desktop integration for Linux workstations.
- **[Windows App](./Windows APP):** Native desktop integration for Windows workstations.

## Core Design Principles
- **Decentralization:** No single point of failure. If the web UI drops, the hardware continues operating. If the mobile app is uninstalled, the Telegram bot maintains control.
- **Real-Time Synergy:** All components react instantly to state changes across the network.
- **Uncompromised Aesthetics:** The system is designed to look and feel like a premium, futuristic entity, avoiding generic UI patterns in favor of highly stylized, immersive interfaces.
