# MEKA Core Intelligence: IoT Hub & Future AI

This repository contains the central "Brain" of **Project MEKA**.

Currently operating as an advanced **IoT Hub**, this Python-based server acts as the primary orchestrator for the entire MEKA ecosystem. It is the crucial middle-layer that receives hardware inputs, processes voice commands from client apps, and dispatches responses back to the physical world.

## Current Responsibilities & Architecture

### 1. Traffic Routing & Fallback Management
The Hub manages all incoming and outgoing data between the ESP32 hardware, the Flutter mobile/desktop apps, and the Web/Telegram dashboards.
- **`fallback_manager.py`:** A highly resilient system designed to handle connection drops. If a primary hardware node goes offline, the Hub automatically routes data to alternative pathways.
- **`device_registry.py`:** Maintains an active manifest of all connected MEKA components, monitoring their health and latency.

### 2. Audio & Visual Processing
- **`audio_controller.py`:** Handles the heavy lifting of audio buffering, managing STT (Speech-to-Text) conversions, and piping TTS (Text-to-Speech) streams back to the hardware.
- **`camera_controller.py`:** Manages encrypted video feeds, allowing secure remote viewing capabilities for administrators.

---

## 🚀 The Road Ahead: Transitioning to Local, Offline AI

At present, MEKA relies on external, third-party APIs (such as OpenAI for logic, Google for STT/TTS) to achieve its intelligence. **This is only a temporary stepping stone.**

The ultimate vision for this repository is to completely sever MEKA's reliance on the cloud. In the upcoming development phases, this hub will be transformed into a **Proprietary, On-Device AI Engine**.

### Our Offline AI Roadmap:
1. **Local Large Language Models (LLMs):** We will integrate localized instances of highly optimized models (e.g., LLaMA 3, Mistral, or custom-trained weights) running directly on local hardware via `llama.cpp` or `Ollama`. MEKA's brain will live entirely on your local machine.
2. **Local Speech-to-Text (STT):** External transcription will be replaced by localized implementations of OpenAI's **Whisper** model, ensuring voice data never leaves your network.
3. **Local Text-to-Speech (TTS):** We will implement high-fidelity, real-time voice synthesis using systems like **Piper TTS** or **Coqui TTS**, giving MEKA a unique, localized voice with zero network latency.

**The Result:** A personal assistant that boasts absolute privacy, zero ongoing API costs, and instantaneous, zero-latency response times.
