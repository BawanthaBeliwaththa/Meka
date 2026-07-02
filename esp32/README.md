# 🔌 Meka ESP32 Hardware Node

Control physical hardware with your voice through Meka.

## Supported Boards

| Board | Status |
|---|---|
| ESP32 DevKit v1 (38-pin) | ✅ Recommended |
| ESP32-S3 | ✅ Supported |
| ESP32-S2 | ✅ Supported |
| ESP32-C3 | ✅ Supported |
| ESP8266 (NodeMCU) | ⚠️ Partial (no NeoPixel, different pins) |

## Required Arduino Libraries

Install via **Arduino IDE → Tools → Manage Libraries**:

| Library | Author | Version |
|---|---|---|
| `ESPAsyncWebServer` | me-no-dev | latest |
| `AsyncTCP` | me-no-dev | latest |
| `ArduinoJson` | bblanchon | ≥6.0 |
| `DHT sensor library` | Adafruit | latest |
| `Adafruit NeoPixel` | Adafruit | latest |
| `ESP32Servo` | jkb-git | latest |

## Default Pin Mapping

```
ESP32 GPIO  │ Connected To
────────────┼─────────────────────────────────
GPIO 2      │ Built-in LED (also PWM output)
GPIO 4      │ DHT22 Data pin
GPIO 13     │ NeoPixel RGB strip (Din)
GPIO 15     │ Buzzer
GPIO 18     │ Servo motor signal wire
GPIO 26     │ Relay channel 1
GPIO 27     │ Relay channel 2
GPIO 14     │ Relay channel 3
GPIO 12     │ Relay channel 4
GPIO 25     │ Relay channel 5
GPIO 33     │ Relay channel 6
GPIO 32     │ Relay channel 7
GPIO 19     │ Relay channel 8
GPIO 34     │ Analog input (ADC)
```

## Wiring Diagrams

### Basic LED + Relay Setup
```
ESP32                 Relay Module (8-ch)
3.3V ─────────────── VCC
GND ──────────────── GND
GPIO 26 ─────────── IN1  ──► COM1 → Light 1
GPIO 27 ─────────── IN2  ──► COM2 → Light 2
GPIO 14 ─────────── IN3
GPIO 12 ─────────── IN4
GPIO 25 ─────────── IN5
GPIO 33 ─────────── IN6
GPIO 32 ─────────── IN7
GPIO 19 ─────────── IN8
```

### DHT22 Temperature Sensor
```
DHT22 Pin  │ ESP32
───────────┼──────────
VCC (1)    │ 3.3V
Data (2)   │ GPIO 4  (+ 10kΩ pullup to 3.3V)
NC (3)     │ —
GND (4)    │ GND
```

### NeoPixel RGB Strip
```
NeoPixel   │ ESP32
───────────┼──────────
5V         │ 5V (VIN)
GND        │ GND
Din        │ GPIO 13  (+ 330Ω series resistor recommended)
```

### Servo Motor
```
Servo Wire │ ESP32
───────────┼──────────
Red        │ 5V (VIN)
Brown/Black│ GND
Orange/Yellow│ GPIO 18
```

## Flash Instructions

### Method 1: Arduino IDE (Recommended)

1. Install [Arduino IDE](https://www.arduino.cc/en/software) 2.x
2. Add ESP32 board support:
   - **File → Preferences → Additional Board URLs:**
     ```
     https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
     ```
   - **Tools → Board → Board Manager** → Search "esp32" → Install **"esp32 by Espressif"**
3. Install all required libraries (see table above)
4. Open `meka_esp32/meka_esp32.ino`
5. **Edit lines 17-18** with your WiFi credentials:
   ```cpp
   #define WIFI_SSID     "YourNetworkName"
   #define WIFI_PASSWORD "YourPassword"
   ```
6. **Tools → Board** → Select `ESP32 Dev Module`
7. **Tools → Port** → Select your COM port
8. Click **Upload** ⬆️
9. Open Serial Monitor (115200 baud) to see the IP address

### Method 2: PlatformIO (VS Code)

```ini
; platformio.ini
[env:esp32dev]
platform = espressif32
board = esp32dev
framework = arduino
lib_deps =
    me-no-dev/ESPAsyncWebServer @ ^1.2.3
    me-no-dev/AsyncTCP @ ^1.1.1
    bblanchon/ArduinoJson @ ^6.21.3
    adafruit/DHT sensor library @ ^1.4.4
    adafruit/Adafruit NeoPixel @ ^1.12.0
    madhephaestus/ESP32Servo @ ^0.13.0
```

```bash
cd esp32
pio run --target upload
pio device monitor --baud 115200
```

## HTTP API Reference

Base URL: `http://meka.local` or `http://<ESP32_IP>`

### `GET /status`
Returns full board status.
```json
{
  "device": "meka",
  "firmware": "1.0.0",
  "uptime_s": 3600,
  "ip": "192.168.1.42",
  "rssi": -65,
  "relays": [false, true, false, false, false, false, false, false],
  "servo_angle": 90,
  "led_brightness": 128
}
```

### `POST /relay`
Toggle or set a relay channel (1–8).
```json
{ "channel": 1, "state": "on" }
{ "channel": 2, "state": "off" }
{ "channel": 3, "state": "toggle" }
```

### `POST /pin`
Raw GPIO control.
```json
{ "pin": 2, "state": "high" }
{ "pin": 2, "state": "low" }
{ "pin": 2, "state": "toggle" }
```

### `POST /pwm`
PWM (analog) output, 0–255 duty cycle.
```json
{ "pin": 2, "duty": 128 }
```

### `POST /servo`
Move servo to angle (0–180°).
```json
{ "angle": 90 }
```

### `POST /led`
Control NeoPixel RGB strip.
```json
{ "r": 255, "g": 0, "b": 128 }
{ "brightness": 50 }
```

### `POST /buzzer`
Buzz for a duration.
```json
{ "duration_ms": 300 }
```

### `GET /sensor/dht`
Read DHT22 temperature & humidity.
```json
{
  "temperature_c": "28.5",
  "temperature_f": "83.3",
  "humidity": "65.2"
}
```

### `GET /sensor/analog`
Read analog voltage on GPIO 34.
```json
{ "raw": 2048, "volts": "1.650" }
```

### `POST /reset`
Turn off all relays, reset servo and LEDs.

## Meka Voice Commands

Once configured in the Meka app, say these commands:

| Voice Command | What Happens |
|---|---|
| *"Turn on relay 1"* | Relay 1 switches ON |
| *"Turn off relay 2"* | Relay 2 switches OFF |
| *"Toggle relay 3"* | Relay 3 flips state |
| *"Move servo to 90 degrees"* | Servo rotates to 90° |
| *"Set LED to blue"* | NeoPixels turn blue |
| *"Set LED to red"* | NeoPixels turn red |
| *"Dim LED to 50 percent"* | NeoPixel brightness 50% |
| *"What is the temperature?"* | Reads DHT22, speaks result |
| *"What is the humidity?"* | Reads DHT22, speaks result |
| *"Buzz the buzzer"* | Buzzes for 200ms |
| *"Turn off pin 2"* | Sets GPIO 2 LOW |
| *"Reset all outputs"* | All relays OFF, defaults restored |

## Configuring Meka App

1. Open Meka → **Settings**
2. Scroll to **ESP32 Hardware Node**
3. Enter the IP address shown in Serial Monitor (e.g., `192.168.1.42`)
   - Or use `meka.local` if your phone supports mDNS
4. Tap **Test Connection** — you should see ✅
5. Save

## OTA Updates

After initial flash, update firmware wirelessly:
1. Open Arduino IDE
2. **Tools → Port** → Select `meka.local` (network port)
3. Click Upload

Password: `meka2024` (change in `#define OTA_PASSWORD`)
