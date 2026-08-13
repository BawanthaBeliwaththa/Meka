# MEKA Hardware & Firmware Subsystem

This repository contains the physical blueprint and embedded intelligence of **Project MEKA**.

It represents the intersection of MEKA's digital brain and physical existence, managing environmental sensors, visual feedback displays, and network communication at the microcontroller level.

## Core Responsibilities & Features

### 1. Embedded Firmware (`meka_esp32.ino`)
The brain of the physical unit is an ESP32 microcontroller. The C++ firmware is engineered for high stability and real-time responsiveness:
- **Display Matrix Management:** Drives a 16x2 I2C LCD display (`LiquidCrystal_I2C`). It features advanced logic to dynamically scroll text that exceeds the 16-character limit, formatting responses cleanly (e.g., separating `Q:` and `A:` lines).
- **Asynchronous Processing:** Utilizes non-blocking timing logic (`millis()`) to ensure the display can scroll text simultaneously while the ESP32 listens for incoming serial or network commands.
- **JSON Payload Parsing:** Efficiently deserializes incoming command payloads from the MEKA IoT Hub to trigger hardware state changes (e.g., turning on LEDs, enabling relays).

### 2. 3D Physical Architecture
The repository includes the mathematical models required to construct MEKA's body:
- **`meka_chassis.scad`:** Parametric OpenSCAD designs that can be modified dynamically based on specific hardware tolerances.
- **STL Files:** Sliced and ready-to-print 3D models for the chassis, LCD mounting brackets, and sensor enclosures.

## Technical Stack
- **Microcontroller:** ESP32 (Dual-core Xtensa)
- **Language:** C++ (Arduino Framework / PlatformIO)
- **Libraries:** `Wire.h`, `LiquidCrystal_I2C.h`, `ArduinoJson.h`
- **CAD:** OpenSCAD
