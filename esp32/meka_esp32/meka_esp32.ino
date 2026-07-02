/*
 * ╔══════════════════════════════════════════════════════════╗
 * ║          MEKA — ESP32 Hardware Intelligence Node         ║
 * ║       Voice-controlled IoT via Meka Android App          ║
 * ║                                                          ║
 * ║  Board   : ESP32 DevKit (any variant), ESP8266           ║
 * ║  Protocol: HTTP REST (port 80) + WebSocket (port 81)     ║
 * ║  mDNS    : http://meka.local                             ║
 * ║  OTA     : Enabled (password: meka2024)                  ║
 * ╚══════════════════════════════════════════════════════════╝
 *
 * QUICK WIRING:
 *   Relay 1  → GPIO 26    LED (built-in) → GPIO 2
 *   Relay 2  → GPIO 27    Servo          → GPIO 18
 *   Relay 3  → GPIO 14    DHT22 Data     → GPIO 4
 *   Relay 4  → GPIO 12    NeoPixel Data  → GPIO 13
 *   Relay 5  → GPIO 25    Analog In      → GPIO 34
 *   Relay 6  → GPIO 33    Buzzer         → GPIO 15
 *   Relay 7  → GPIO 32
 *   Relay 8  → GPIO 19
 *
 * VOICE COMMANDS (via Meka Android App):
 *   "Turn on relay 1"
 *   "Set LED to blue"
 *   "Move servo to 90 degrees"
 *   "What is the temperature?"
 *   "Dim light to 50 percent"
 *   "Buzz the buzzer"
 *
 * DEPENDENCIES (install via Arduino Library Manager):
 *   - ESPAsyncWebServer  (me-no-dev/ESPAsyncWebServer)
 *   - AsyncTCP           (me-no-dev/AsyncTCP)  ← ESP32 only
 *   - ESP8266WiFi        ← ESP8266 only
 *   - ArduinoJson        (bblanchon/ArduinoJson) v6+
 *   - DHT sensor library (adafruit/DHT-sensor-library)
 *   - Adafruit NeoPixel  (adafruit/Adafruit_NeoPixel)
 *   - ESP32Servo         (jkb-git/ESP32Servo)
 *   - ESPmDNS            (built-in ESP32 core)
 *   - ArduinoOTA         (built-in)
 */

// ─────────────────────────── CONFIGURATION ───────────────────────────────
#define WIFI_SSID       "YOUR_WIFI_SSID"          // ← Change this
#define WIFI_PASSWORD   "YOUR_WIFI_PASSWORD"       // ← Change this
#define DEVICE_NAME     "meka"                     // mDNS: http://meka.local
#define OTA_PASSWORD    "meka2024"
#define FIRMWARE_VER    "1.0.0"

// Pin Definitions
#define PIN_BUILTIN_LED  2
#define PIN_BUZZER       15
#define PIN_SERVO        18
#define PIN_DHT          4
#define PIN_NEOPIXEL     13
#define PIN_ANALOG       34

// Relay Pins (active LOW for most relay modules)
const int RELAY_PINS[] = {26, 27, 14, 12, 25, 33, 32, 19};
const int RELAY_COUNT  = 8;
#define RELAY_ON  LOW
#define RELAY_OFF HIGH

// NeoPixel
#define NEOPIXEL_COUNT  8

// ─────────────────────────── INCLUDES ────────────────────────────────────
#include <WiFi.h>
#include <ESPAsyncWebServer.h>
#include <ESPmDNS.h>
#include <ArduinoOTA.h>
#include <ArduinoJson.h>
#include <DHT.h>
#include <Adafruit_NeoPixel.h>
#include <ESP32Servo.h>

// ─────────────────────────── GLOBALS ─────────────────────────────────────
AsyncWebServer server(80);
AsyncWebSocket ws("/ws");

DHT dht(PIN_DHT, DHT22);
Adafruit_NeoPixel strip(NEOPIXEL_COUNT, PIN_NEOPIXEL, NEO_GRB + NEO_KHZ800);
Servo myServo;

bool relayState[8] = {false};
int  servoAngle    = 0;
int  ledBrightness = 0;

unsigned long startTime;

// ─────────────────────────── HELPERS ─────────────────────────────────────
String buildStatusJson() {
    StaticJsonDocument<512> doc;
    doc["device"]   = DEVICE_NAME;
    doc["firmware"] = FIRMWARE_VER;
    doc["uptime_s"] = (millis() - startTime) / 1000;
    doc["ip"]       = WiFi.localIP().toString();
    doc["rssi"]     = WiFi.RSSI();
    doc["hostname"] = String(DEVICE_NAME) + ".local";

    JsonArray relays = doc.createNestedArray("relays");
    for (int i = 0; i < RELAY_COUNT; i++) relays.add(relayState[i]);

    doc["servo_angle"]     = servoAngle;
    doc["led_brightness"]  = ledBrightness;

    String out;
    serializeJson(doc, out);
    return out;
}

void setCorsHeaders(AsyncWebServerResponse* response) {
    response->addHeader("Access-Control-Allow-Origin",  "*");
    response->addHeader("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
    response->addHeader("Access-Control-Allow-Headers", "Content-Type");
}

void sendJson(AsyncWebServerRequest* request, int code, String body) {
    AsyncWebServerResponse* response = request->beginResponse(code, "application/json", body);
    setCorsHeaders(response);
    request->send(response);
}

void broadcastStatus() {
    ws.textAll(buildStatusJson());
}

// ─────────────────────────── SETUP ───────────────────────────────────────
void setup() {
    Serial.begin(115200);
    Serial.println("\n\n╔══════════════════════════════╗");
    Serial.println(  "║  MEKA ESP32 Node — Booting   ║");
    Serial.println(  "╚══════════════════════════════╝");

    startTime = millis();

    // Relay pins
    for (int i = 0; i < RELAY_COUNT; i++) {
        pinMode(RELAY_PINS[i], OUTPUT);
        digitalWrite(RELAY_PINS[i], RELAY_OFF);
    }

    // Built-in LED
    pinMode(PIN_BUILTIN_LED, OUTPUT);
    digitalWrite(PIN_BUILTIN_LED, LOW);

    // Buzzer
    pinMode(PIN_BUZZER, OUTPUT);
    digitalWrite(PIN_BUZZER, LOW);

    // Servo
    myServo.attach(PIN_SERVO);
    myServo.write(0);

    // DHT22
    dht.begin();

    // NeoPixel
    strip.begin();
    strip.setBrightness(50);
    strip.show();

    // ── WiFi ──
    Serial.printf("Connecting to WiFi: %s\n", WIFI_SSID);
    WiFi.mode(WIFI_STA);
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    int attempts = 0;
    while (WiFi.status() != WL_CONNECTED && attempts < 40) {
        delay(500);
        Serial.print(".");
        attempts++;
    }
    if (WiFi.status() == WL_CONNECTED) {
        Serial.printf("\n✅ Connected! IP: %s\n", WiFi.localIP().toString().c_str());
        // Blink built-in LED 3x to signal connection
        for (int i = 0; i < 3; i++) {
            digitalWrite(PIN_BUILTIN_LED, HIGH); delay(100);
            digitalWrite(PIN_BUILTIN_LED, LOW);  delay(100);
        }
    } else {
        Serial.println("\n❌ WiFi failed. Check credentials.");
    }

    // ── mDNS ──
    if (MDNS.begin(DEVICE_NAME)) {
        MDNS.addService("http", "tcp", 80);
        Serial.printf("mDNS: http://%s.local\n", DEVICE_NAME);
    }

    // ── OTA ──
    ArduinoOTA.setHostname(DEVICE_NAME);
    ArduinoOTA.setPassword(OTA_PASSWORD);
    ArduinoOTA.onStart([]()  { Serial.println("OTA Update starting..."); });
    ArduinoOTA.onEnd([]()    { Serial.println("\nOTA Done!"); });
    ArduinoOTA.onError([](ota_error_t e) { Serial.printf("OTA Error[%u]\n", e); });
    ArduinoOTA.begin();

    // ── WebSocket ──
    ws.onEvent([](AsyncWebSocket* server, AsyncWebSocketClient* client,
                  AwsEventType type, void* arg, uint8_t* data, size_t len) {
        if (type == WS_EVT_CONNECT) {
            Serial.printf("WS Client #%u connected\n", client->id());
            client->text(buildStatusJson());
        }
    });
    server.addHandler(&ws);

    // ══════════════════ HTTP REST ROUTES ══════════════════

    // OPTIONS preflight (CORS)
    server.onNotFound([](AsyncWebServerRequest* request) {
        if (request->method() == HTTP_OPTIONS) {
            AsyncWebServerResponse* r = request->beginResponse(200);
            setCorsHeaders(r);
            request->send(r);
        } else {
            request->send(404, "application/json", "{\"error\":\"Not found\"}");
        }
    });

    // GET /  — welcome page
    server.on("/", HTTP_GET, [](AsyncWebServerRequest* request) {
        String html = R"(<!DOCTYPE html><html><head>
<title>Meka ESP32 Node</title>
<style>body{background:#010409;color:#00D4FF;font-family:monospace;padding:2rem}
h1{color:#7C4DFF}a{color:#00D4FF}table{border-collapse:collapse;width:100%}
td,th{border:1px solid #333;padding:8px;text-align:left}</style></head><body>
<h1>🤖 MEKA ESP32 Hardware Node</h1>
<p>Firmware v)" + String(FIRMWARE_VER) + R"( | <a href="/status">Status JSON</a></p>
<h2>Endpoints</h2><table>
<tr><th>Method</th><th>Path</th><th>Description</th></tr>
<tr><td>GET</td><td>/status</td><td>Board status & relay states</td></tr>
<tr><td>POST</td><td>/pin</td><td>{"pin":2,"state":"high"|"low"|"toggle"}</td></tr>
<tr><td>POST</td><td>/relay</td><td>{"channel":1,"state":"on"|"off"|"toggle"}</td></tr>
<tr><td>POST</td><td>/pwm</td><td>{"pin":2,"duty":0-255}</td></tr>
<tr><td>POST</td><td>/servo</td><td>{"angle":0-180}</td></tr>
<tr><td>POST</td><td>/led</td><td>{"r":255,"g":0,"b":128} or {"brightness":50}</td></tr>
<tr><td>POST</td><td>/buzzer</td><td>{"duration_ms":200}</td></tr>
<tr><td>GET</td><td>/sensor/dht</td><td>Temperature & humidity (DHT22)</td></tr>
<tr><td>GET</td><td>/sensor/analog</td><td>Analog pin voltage reading</td></tr>
<tr><td>POST</td><td>/reset</td><td>All relays OFF, defaults restored</td></tr>
</table></body></html>)";
        request->send(200, "text/html", html);
    });

    // GET /status
    server.on("/status", HTTP_GET, [](AsyncWebServerRequest* request) {
        sendJson(request, 200, buildStatusJson());
    });

    // POST /pin — raw GPIO control
    server.on("/pin", HTTP_POST, [](AsyncWebServerRequest* request) {}, nullptr,
    [](AsyncWebServerRequest* request, uint8_t* data, size_t len, size_t, size_t) {
        StaticJsonDocument<128> doc;
        if (deserializeJson(doc, data, len)) {
            sendJson(request, 400, "{\"error\":\"Invalid JSON\"}");
            return;
        }
        int pin        = doc["pin"] | -1;
        String state   = doc["state"] | "toggle";
        if (pin < 0 || pin > 39) {
            sendJson(request, 400, "{\"error\":\"Invalid pin\"}");
            return;
        }
        pinMode(pin, OUTPUT);
        bool current = digitalRead(pin);
        bool newState = (state == "high") ? HIGH : (state == "low") ? LOW : !current;
        digitalWrite(pin, newState);
        StaticJsonDocument<128> res;
        res["pin"]   = pin;
        res["state"] = newState ? "high" : "low";
        String out; serializeJson(res, out);
        sendJson(request, 200, out);
        broadcastStatus();
    });

    // POST /relay
    server.on("/relay", HTTP_POST, [](AsyncWebServerRequest* request) {}, nullptr,
    [](AsyncWebServerRequest* request, uint8_t* data, size_t len, size_t, size_t) {
        StaticJsonDocument<128> doc;
        if (deserializeJson(doc, data, len)) {
            sendJson(request, 400, "{\"error\":\"Invalid JSON\"}");
            return;
        }
        int ch     = (doc["channel"] | 1) - 1;  // 1-indexed → 0-indexed
        String st  = doc["state"] | "toggle";
        if (ch < 0 || ch >= RELAY_COUNT) {
            sendJson(request, 400, "{\"error\":\"Channel out of range (1-8)\"}");
            return;
        }
        if (st == "on")       relayState[ch] = true;
        else if (st == "off") relayState[ch] = false;
        else                  relayState[ch] = !relayState[ch];

        digitalWrite(RELAY_PINS[ch], relayState[ch] ? RELAY_ON : RELAY_OFF);

        StaticJsonDocument<128> res;
        res["channel"] = ch + 1;
        res["state"]   = relayState[ch] ? "on" : "off";
        String out; serializeJson(res, out);
        sendJson(request, 200, out);
        broadcastStatus();
        Serial.printf("Relay %d → %s\n", ch + 1, relayState[ch] ? "ON" : "OFF");
    });

    // POST /pwm — analog write
    server.on("/pwm", HTTP_POST, [](AsyncWebServerRequest* request) {}, nullptr,
    [](AsyncWebServerRequest* request, uint8_t* data, size_t len, size_t, size_t) {
        StaticJsonDocument<128> doc;
        if (deserializeJson(doc, data, len)) {
            sendJson(request, 400, "{\"error\":\"Invalid JSON\"}");
            return;
        }
        int pin  = doc["pin"]  | PIN_BUILTIN_LED;
        int duty = doc["duty"] | 0;
        duty = constrain(duty, 0, 255);
        ledcSetup(0, 5000, 8);
        ledcAttachPin(pin, 0);
        ledcWrite(0, duty);
        ledBrightness = duty;
        StaticJsonDocument<128> res;
        res["pin"]  = pin;
        res["duty"] = duty;
        String out; serializeJson(res, out);
        sendJson(request, 200, out);
        broadcastStatus();
    });

    // POST /servo
    server.on("/servo", HTTP_POST, [](AsyncWebServerRequest* request) {}, nullptr,
    [](AsyncWebServerRequest* request, uint8_t* data, size_t len, size_t, size_t) {
        StaticJsonDocument<64> doc;
        if (deserializeJson(doc, data, len)) {
            sendJson(request, 400, "{\"error\":\"Invalid JSON\"}");
            return;
        }
        int angle = doc["angle"] | 90;
        angle = constrain(angle, 0, 180);
        myServo.write(angle);
        servoAngle = angle;
        StaticJsonDocument<64> res;
        res["angle"] = angle;
        String out; serializeJson(res, out);
        sendJson(request, 200, out);
        broadcastStatus();
        Serial.printf("Servo → %d°\n", angle);
    });

    // POST /led — NeoPixel RGB control
    server.on("/led", HTTP_POST, [](AsyncWebServerRequest* request) {}, nullptr,
    [](AsyncWebServerRequest* request, uint8_t* data, size_t len, size_t, size_t) {
        StaticJsonDocument<128> doc;
        if (deserializeJson(doc, data, len)) {
            sendJson(request, 400, "{\"error\":\"Invalid JSON\"}");
            return;
        }
        if (doc.containsKey("brightness")) {
            int b = constrain((int)doc["brightness"], 0, 255);
            strip.setBrightness(b);
            strip.show();
        } else {
            int r = doc["r"] | 0;
            int g = doc["g"] | 0;
            int b = doc["b"] | 0;
            for (int i = 0; i < strip.numPixels(); i++)
                strip.setPixelColor(i, strip.Color(r, g, b));
            strip.show();
        }
        sendJson(request, 200, "{\"ok\":true}");
    });

    // POST /buzzer
    server.on("/buzzer", HTTP_POST, [](AsyncWebServerRequest* request) {}, nullptr,
    [](AsyncWebServerRequest* request, uint8_t* data, size_t len, size_t, size_t) {
        StaticJsonDocument<64> doc;
        deserializeJson(doc, data, len);
        int dur = constrain((int)(doc["duration_ms"] | 200), 10, 5000);
        digitalWrite(PIN_BUZZER, HIGH);
        delay(dur);
        digitalWrite(PIN_BUZZER, LOW);
        sendJson(request, 200, "{\"ok\":true}");
    });

    // GET /sensor/dht — temperature & humidity
    server.on("/sensor/dht", HTTP_GET, [](AsyncWebServerRequest* request) {
        float temp = dht.readTemperature();
        float humi = dht.readHumidity();
        if (isnan(temp) || isnan(humi)) {
            sendJson(request, 503, "{\"error\":\"DHT22 read failed. Check wiring on GPIO 4.\"}");
            return;
        }
        StaticJsonDocument<128> doc;
        doc["temperature_c"] = serialized(String(temp, 1));
        doc["temperature_f"] = serialized(String(temp * 9.0 / 5.0 + 32.0, 1));
        doc["humidity"]      = serialized(String(humi, 1));
        String out; serializeJson(doc, out);
        sendJson(request, 200, out);
    });

    // GET /sensor/analog
    server.on("/sensor/analog", HTTP_GET, [](AsyncWebServerRequest* request) {
        int raw     = analogRead(PIN_ANALOG);
        float volts = raw * 3.3f / 4095.0f;
        StaticJsonDocument<64> doc;
        doc["raw"]   = raw;
        doc["volts"] = serialized(String(volts, 3));
        String out; serializeJson(doc, out);
        sendJson(request, 200, out);
    });

    // POST /reset — all relays off, defaults
    server.on("/reset", HTTP_POST, [](AsyncWebServerRequest* request) {
        for (int i = 0; i < RELAY_COUNT; i++) {
            relayState[i] = false;
            digitalWrite(RELAY_PINS[i], RELAY_OFF);
        }
        myServo.write(0);
        servoAngle = 0;
        for (int i = 0; i < strip.numPixels(); i++) strip.setPixelColor(i, 0);
        strip.show();
        digitalWrite(PIN_BUILTIN_LED, LOW);
        sendJson(request, 200, "{\"ok\":true,\"message\":\"All outputs reset\"}");
        broadcastStatus();
        Serial.println("🔄 All outputs reset");
    });

    server.begin();
    Serial.println("✅ HTTP server started on port 80");
    Serial.printf("📡 Open: http://%s.local  or  http://%s\n",
                  DEVICE_NAME, WiFi.localIP().toString().c_str());
    Serial.println("═══════════════════════════════════════");
}

// ─────────────────────────── LOOP ────────────────────────────────────────
void loop() {
    ArduinoOTA.handle();
    ws.cleanupClients();

    // Heartbeat WebSocket broadcast every 10s
    static unsigned long lastBroadcast = 0;
    if (millis() - lastBroadcast > 10000) {
        lastBroadcast = millis();
        broadcastStatus();
    }
}
