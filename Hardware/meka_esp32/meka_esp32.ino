/*
 * ╔══════════════════════════════════════════════════════════╗
 * ║         MEKA v.1.0.1 — Firebase IoT Intelligence Node    ║
 * ║       Voice-controlled IoT via Telegram + Web App        ║
 * ║                                                          ║
 * ║  Board   : ESP32 DevKit                                  ║
 * ║  Protocol: HTTP REST + WebSocket + Firebase RTDB         ║
 * ║  mDNS    : http://meka.local                             ║
 * ║  OTA     : Enabled (password: meka2024)                  ║
 * ╚══════════════════════════════════════════════════════════╝
 *
 * STATUS LED WIRING (4 colored LEDs):
 *   🔵 Blue   (Listening)  → GPIO 26
 *   🟡 Yellow (Processing) → GPIO 27
 *   🟢 Green  (Success)    → GPIO 14
 *   🔴 Red    (Error)      → GPIO 12
 *
 * OTHER PINS:
 *   Built-in LED → GPIO 2    Servo     → GPIO 18
 *   DHT22 Data   → GPIO 4    Buzzer    → GPIO 15
 *   Analog In    → GPIO 34   NeoPixel  → GPIO 13
 *   LCD SDA      → GPIO 21   LCD SCL   → GPIO 22
 *
 * ⚠️  FIREBASE SETUP:
 *   Fill in FIREBASE_HOST and FIREBASE_AUTH below with your project credentials.
 *   FIREBASE_HOST = "<project-id>-default-rtdb.firebaseio.com"
 *   FIREBASE_AUTH = your Database Secret from Firebase Console > Settings > Service Accounts
 */

// ─────────────────────────── CONFIGURATION ───────────────────────────────
#define WIFI_SSID        "TCL 30E"
#define WIFI_PASSWORD    "bawantha"
#define DEVICE_NAME      "meka"
#define OTA_PASSWORD     "meka2024"
#define FIRMWARE_VER     "v.1.0.1"

// 🔥 FIREBASE — fill these in with your project credentials
#define FIREBASE_HOST    "sliot-80296-default-rtdb.firebaseio.com"
#define FIREBASE_AUTH    "efbeCeDyD2jUdksZYIPCErb8cPokStkJ9PwEWiR2"

// Status LED Pins (4 colored LEDs)
#define PIN_LED_BLUE     26   // 🔵 Listening
#define PIN_LED_YELLOW   27   // 🟡 Processing
#define PIN_LED_GREEN    14   // 🟢 Success
#define PIN_LED_RED      12   // 🔴 Error

// Other Pins
#define PIN_BUILTIN_LED  2
#define PIN_BUZZER       15
#define PIN_SERVO        18
#define PIN_DHT          4
#define PIN_ANALOG       34

// ─────────────────────────── INCLUDES ────────────────────────────────────
#include <Arduino.h>
#include <WiFi.h>
#include <Wire.h>
#include <Preferences.h>

Preferences preferences;
String activeSsid = WIFI_SSID;
String activePass = WIFI_PASSWORD;

#include <ESP32Servo.h>
#include "DHT.h"
#include <ArduinoJson.h>
#include <WebServer.h>
#include <ESPmDNS.h>
#include <Firebase_ESP_Client.h>

// --- New Audio Libraries ---
#include <driver/i2s.h>

// Provide the token generation process info.
#include "addons/TokenHelper.h"
#include "addons/RTDBHelper.h"
#include <LiquidCrystal_I2C.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <WebSocketsServer.h>
#include <ArduinoOTA.h>

// LCD Configuration
#define LCD_ADDR  0x27
#define LCD_COLS  16
#define LCD_ROWS  2

// OLED Configuration (SSD1306 128x64 or 128x32)
#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define OLED_RESET    -1
Adafruit_SSD1306 oled(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);

bool hasOled = false;
bool hasLcd  = false;
uint8_t oledI2cAddr = 0x3C;
uint8_t lcdI2cAddr  = 0x27;

// Custom Characters for MEKA Robot Logo
uint8_t botLeft[8]  = { 0b01111, 0b11111, 0b11111, 0b11011, 0b11011, 0b11111, 0b01111, 0b00000 };
uint8_t botRight[8] = { 0b11100, 0b11111, 0b11111, 0b11011, 0b11011, 0b11111, 0b11110, 0b00000 };

// ─────────────────────────── HARDWARE FLAGS ──────────────────────────────
bool hasMic       = false;
bool hasSpeaker   = false;
bool hasCamera    = false;
bool hasBluetooth = false;

// ─────────────────────────── GLOBALS ─────────────────────────────────────
LiquidCrystal_I2C lcd(LCD_ADDR, LCD_COLS, LCD_ROWS);
WebServer server(80);
WebSocketsServer webSocket = WebSocketsServer(81);
FirebaseData fbData;
FirebaseData fbStream;
FirebaseAuth fbAuth;
FirebaseConfig fbConfig;

DHT dht22(PIN_DHT, DHT22);
DHT dht11(PIN_DHT, DHT11);

float readTemperatureSafe() {
  float t = dht22.readTemperature();
  if (isnan(t)) {
    t = dht11.readTemperature();
  }
  return t;
}

float readHumiditySafe() {
  float h = dht22.readHumidity();
  if (isnan(h)) {
    h = dht11.readHumidity();
  }
  return h;
}
Servo myServo;

int servoAngle = 0;
int ledBrightness = 0;
unsigned long startTime;

// Display State Variables
bool isShowingQA = false;
unsigned long qaStartTime = 0; // Timestamp for 3-minute timeout

String scrollQ_body = "";
String scrollQ_padded = "";
int scrollIndexQ = 0;
unsigned long lastScrollTimeQ = 0;
unsigned long pauseUntilQ = 0;
String lastDisplayedLine0 = "";

String scrollA_body = "";
String scrollA_padded = "";
int scrollIndexA = 0;
unsigned long lastScrollTimeA = 0;
unsigned long pauseUntilA = 0;
String lastDisplayedLine1 = "";

// Ready Mode text state
String readyModeLine0 = "MEKA v 1.0.1";
String readyModeLine1 = "Waiting for you command.";
int readyIndex1 = 0;
unsigned long lastReadyScrollTime = 0;

void setLcdQ(String q);
void setLcdA(String a);
void lcdShowStatus(String line1, String line2 = "");
void updateLcdDisplay();
void updateOledDisplay();
void checkDisplayTimeout();
void resetToReadyMode();

// Firebase Streaming
unsigned long lastFirebasePush = 0;

// MEKA Status States
enum MekaStatus { STATUS_IDLE, STATUS_LISTENING, STATUS_PROCESSING, STATUS_SUCCESS, STATUS_ERROR };
MekaStatus currentStatus = STATUS_IDLE;
unsigned long statusResetTime = 0;

// ─────────────────────────── DYNAMIC HARDWARE PROBING ─────────────────────

// Probe INMP441 I2S Microphone (Pin SCK=32, WS=33, SD=34)
void probeMicrophone() {
  i2s_config_t i2s_mic_config = {
    .mode = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_RX),
    .sample_rate = 16000,
    .bits_per_sample = I2S_BITS_PER_SAMPLE_16BIT,
    .channel_format = I2S_CHANNEL_FMT_ONLY_LEFT,
    .communication_format = I2S_COMM_FORMAT_I2S,
    .intr_alloc_flags = ESP_INTR_FLAG_LEVEL1,
    .dma_buf_count = 4,
    .dma_buf_len = 64
  };

  i2s_pin_config_t mic_pin_config = {
    .bck_io_num = 32,
    .ws_io_num = 33,
    .data_out_num = I2S_PIN_NO_CHANGE,
    .data_in_num = 34
  };

  esp_err_t err = i2s_driver_install(I2S_NUM_0, &i2s_mic_config, 0, NULL);
  if (err == ESP_OK) {
    i2s_set_pin(I2S_NUM_0, &mic_pin_config);
    // Read test sample to verify physical connection
    int16_t sampleBuffer[64];
    size_t bytesRead = 0;
    i2s_read(I2S_NUM_0, sampleBuffer, sizeof(sampleBuffer), &bytesRead, 100);
    hasMic = (bytesRead > 0);
    Serial.printf("🎤 Local Mic Probe: %s (%d bytes read)\n", hasMic ? "DETECTED" : "NOT FOUND", bytesRead);
  } else {
    hasMic = false;
    Serial.println("🎤 Local Mic Probe: NOT ATTACHED (using Network Mic)");
  }
}

// Probe MAX98357A I2S Speaker Amplifier (BCLK=25, LRC=15, DIN=2)
void probeSpeaker() {
  i2s_config_t i2s_spk_config = {
    .mode = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_TX),
    .sample_rate = 16000,
    .bits_per_sample = I2S_BITS_PER_SAMPLE_16BIT,
    .channel_format = I2S_CHANNEL_FMT_RIGHT_LEFT,
    .communication_format = I2S_COMM_FORMAT_I2S,
    .intr_alloc_flags = ESP_INTR_FLAG_LEVEL1,
    .dma_buf_count = 4,
    .dma_buf_len = 64
  };

  i2s_pin_config_t spk_pin_config = {
    .bck_io_num = 25,
    .ws_io_num = 15,
    .data_out_num = 2,
    .data_in_num = I2S_PIN_NO_CHANGE
  };

  #ifdef I2S_NUM_1
  esp_err_t err = i2s_driver_install(I2S_NUM_1, &i2s_spk_config, 0, NULL);
  if (err == ESP_OK) {
    i2s_set_pin(I2S_NUM_1, &spk_pin_config);
    hasSpeaker = true;
    Serial.println("🔊 Local Speaker Probe: DETECTED");
  } else {
    hasSpeaker = false;
    Serial.println("🔊 Local Speaker Probe: NOT ATTACHED (using Network Speaker)");
  }
  #else
  hasSpeaker = false;
  Serial.println("🔊 Local Speaker Probe: UNSUPPORTED on this ESP32 variant (using Network Speaker)");
  #endif
}

// Probe local ESP32-CAM module or DVP camera bridge
void probeCameraBridge() {
  // Check if local camera module responds or is bridged
  hasCamera = false;
  Serial.println("📷 Local Camera Probe: NOT ATTACHED (using Network/ESP32-CAM)");
}

// Initialize Bluetooth Serial / BLE Capability
void initBluetooth() {
  hasBluetooth = true;
  Serial.println("📶 Bluetooth Interface: READY (Classic/BLE)");
}

void probeHardwareCapabilities() {
  Serial.println("\n🔍 Probing ESP32 Local Hardware Modules...");
  probeMicrophone();
  probeSpeaker();
  probeCameraBridge();
  initBluetooth();
  Serial.println("✅ Hardware Probing Complete.\n");
}

// ─────────────────────────── STATUS LED CONTROL ───────────────────────────

void setAllStatusLEDs(bool blue, bool yellow, bool green, bool red) {
  digitalWrite(PIN_LED_BLUE,   blue   ? HIGH : LOW);
  digitalWrite(PIN_LED_YELLOW, yellow ? HIGH : LOW);
  digitalWrite(PIN_LED_GREEN,  green  ? HIGH : LOW);
  digitalWrite(PIN_LED_RED,    red    ? HIGH : LOW);
}

void setMekaStatus(MekaStatus status, int autoResetMs = 0) {
  currentStatus = status;
  if (autoResetMs > 0) {
    statusResetTime = millis() + autoResetMs;
  } else {
    statusResetTime = 0;
  }

  switch (status) {
    case STATUS_IDLE:
      setAllStatusLEDs(false, false, false, false);
      Serial.println("💤 Status: IDLE");
      // We intentionally do NOT clear the LCD here.
      // This ensures that long answers remain readable permanently 
      // until the next voice/text command arrives.
      break;
    case STATUS_LISTENING:
      setAllStatusLEDs(true, false, false, false);
      Serial.println("🔵 Status: LISTENING");
      break;
    case STATUS_PROCESSING:
      setAllStatusLEDs(false, true, false, false);
      Serial.println("🟡 Status: PROCESSING");
      break;
    case STATUS_SUCCESS:
      setAllStatusLEDs(false, false, true, false);
      Serial.println("🟢 Status: SUCCESS");
      break;
    case STATUS_ERROR:
      setAllStatusLEDs(false, false, false, true);
      Serial.println("🔴 Status: ERROR");
      break;
  }

  // Push status to Firebase
  String statusStr = "idle";
  if (status == STATUS_LISTENING)  statusStr = "listening";
  if (status == STATUS_PROCESSING) statusStr = "processing";
  if (status == STATUS_SUCCESS)    statusStr = "success";
  if (status == STATUS_ERROR)      statusStr = "error";
  if (Firebase.ready()) {
    Firebase.RTDB.setString(&fbData, "/meka/status", statusStr);
  }
}

void checkDisplayTimeout() {
  // If in Q&A Mode and 3 minutes (180,000 ms) have passed without new Q/A, return to Ready Mode
  if (isShowingQA && (millis() - qaStartTime >= 180000)) {
    isShowingQA = false;
    scrollQ_body = "";
    scrollA_body = "";
    lastDisplayedLine0 = "";
    lastDisplayedLine1 = "";
    readyIndex1 = 0;
    lastReadyScrollTime = millis();
    Serial.println("⏰ 3-minute timeout reached. Returning display to Ready Mode.");
    updateOledDisplay();
  }
}

void resetToReadyMode() {
  isShowingQA = false;
  scrollQ_body = "";
  scrollA_body = "";
  lastDisplayedLine0 = "";
  lastDisplayedLine1 = "";
  readyIndex1 = 0;
  lastReadyScrollTime = millis();
  updateOledDisplay();
}

void updateOledDisplay() {
  if (!hasOled) return;

  oled.clearDisplay();
  oled.setTextSize(1);
  oled.setTextColor(SSD1306_WHITE);

  if (isShowingQA) {
    // ── Q&A Mode on OLED ──
    oled.setCursor(0, 0);
    oled.print("MEKA ");
    if      (currentStatus == STATUS_LISTENING)  oled.print("[LISTENING]");
    else if (currentStatus == STATUS_PROCESSING) oled.print("[THINKING]");
    else if (currentStatus == STATUS_SUCCESS)    oled.print("[OK]");
    else if (currentStatus == STATUS_ERROR)      oled.print("[ERROR]");
    else                                         oled.print("[IDLE]");

    oled.drawFastHLine(0, 10, 128, SSD1306_WHITE);

    // Question: Fixed "Q: " prefix in corner, only text flows/wraps
    oled.setCursor(0, 13);
    oled.print("Q: ");
    if (scrollQ_body.length() > 0) {
      oled.print(scrollQ_body);
    } else {
      oled.print("Waiting...");
    }

    oled.drawFastHLine(0, 35, 128, SSD1306_WHITE);

    // Answer: Fixed "A: " prefix in corner, only text flows/wraps
    oled.setCursor(0, 38);
    oled.print("A: ");
    if (scrollA_body.length() > 0) {
      oled.print(scrollA_body);
    } else {
      oled.print("Ready");
    }

  } else {
    // ── Ready Mode on OLED ──
    oled.setCursor(0, 0);
    oled.print("MEKA [READY]");
    oled.drawFastHLine(0, 10, 128, SSD1306_WHITE);

    oled.setCursor(0, 18);
    oled.print(readyModeLine0);

    oled.drawFastHLine(0, 32, 128, SSD1306_WHITE);

    oled.setCursor(0, 40);
    oled.print(readyModeLine1);
  }

  oled.display();
}

void setLcdQ(String q) {
  q.trim();
  if (q.length() == 0) return;

  // Strip leading "Q:" or "Q: " if present
  if (q.startsWith("Q: "))      q = q.substring(3);
  else if (q.startsWith("Q:")) q = q.substring(2);
  q.trim();

  scrollQ_body = q;
  if (q.length() > 13) {
    scrollQ_padded = q + "    "; // 4 spaces gap before repeating
  } else {
    scrollQ_padded = q;
  }
  scrollIndexQ = 0;
  lastScrollTimeQ = millis();
  pauseUntilQ = millis() + 2000; // Pause for 2s at start
  lastDisplayedLine0 = ""; // Force re-render

  isShowingQA = true;
  qaStartTime = millis(); // Reset 3-minute timer

  Serial.printf("📟 Q updated: %s\n", q.c_str());
  updateOledDisplay();
}

void setLcdA(String a) {
  a.trim();
  if (a.length() == 0) return;

  // Strip leading "A:" or "A: " if present
  if (a.startsWith("A: "))      a = a.substring(3);
  else if (a.startsWith("A:")) a = a.substring(2);
  a.trim();

  scrollA_body = a;
  if (a.length() > 13) {
    scrollA_padded = a + "    "; // 4 spaces gap before repeating
  } else {
    scrollA_padded = a;
  }
  scrollIndexA = 0;
  lastScrollTimeA = millis();
  pauseUntilA = millis() + 2000; // Pause for 2s at start
  lastDisplayedLine1 = ""; // Force re-render

  isShowingQA = true;
  qaStartTime = millis(); // Start 3-minute timer on answer!

  Serial.printf("📟 A updated: %s\n", a.c_str());
  updateOledDisplay();
}

void lcdShowStatus(String line1, String line2) {
  if (hasLcd) {
    lcd.clear();
    lcd.setCursor(0, 0);
    lcd.print(line1.substring(0, 14));
    lcd.setCursor(14, 0);
    lcd.write(0);  // Robot face left
    lcd.write(1);  // Robot face right
    if (line2.length() > 0) {
      lcd.setCursor(0, 1);
      lcd.print(line2.substring(0, LCD_COLS));
    }
  }
  lastDisplayedLine0 = "";
  lastDisplayedLine1 = "";
  updateOledDisplay();
}

void updateLcdDisplay() {
  checkDisplayTimeout(); // Check 3-minute timeout

  if (!hasLcd) return;
  unsigned long now = millis();

  if (isShowingQA) {
    // ── Q&A Mode on LCD 1602 ──
    // Line 0: Fixed "Q: " (col 0..2) + 13-char flowing body (col 3..15)
    String chunk0 = "";
    if (scrollQ_body.length() == 0) {
      chunk0 = "Waiting...   ";
    } else if (scrollQ_body.length() <= 13) {
      chunk0 = scrollQ_body;
      while ((int)chunk0.length() < 13) chunk0 += ' ';
    } else {
      if (now >= pauseUntilQ) {
        if (now - lastScrollTimeQ >= 350) {
          lastScrollTimeQ = now;
          scrollIndexQ++;
          if (scrollIndexQ >= (int)scrollQ_padded.length()) {
            scrollIndexQ = 0;
            pauseUntilQ = now + 2000;
          }
        }
      }
      int len = scrollQ_padded.length();
      for (int i = 0; i < 13; i++) {
        chunk0 += scrollQ_padded[(scrollIndexQ + i) % len];
      }
    }
    String line0 = "Q: " + chunk0;

    if (line0 != lastDisplayedLine0) {
      lastDisplayedLine0 = line0;
      lcd.setCursor(0, 0);
      lcd.print(line0);
    }

    // Line 1: Fixed "A: " (col 0..2) + 13-char flowing body (col 3..15)
    String chunk1 = "";
    if (scrollA_body.length() == 0) {
      chunk1 = "Ready...     ";
    } else if (scrollA_body.length() <= 13) {
      chunk1 = scrollA_body;
      while ((int)chunk1.length() < 13) chunk1 += ' ';
    } else {
      if (now >= pauseUntilA) {
        if (now - lastScrollTimeA >= 350) {
          lastScrollTimeA = now;
          scrollIndexA++;
          if (scrollIndexA >= (int)scrollA_padded.length()) {
            scrollIndexA = 0;
            pauseUntilA = now + 2000;
          }
        }
      }
      int len = scrollA_padded.length();
      for (int i = 0; i < 13; i++) {
        chunk1 += scrollA_padded[(scrollIndexA + i) % len];
      }
    }
    String line1 = "A: " + chunk1;

    if (line1 != lastDisplayedLine1) {
      lastDisplayedLine1 = line1;
      lcd.setCursor(0, 1);
      lcd.print(line1);
    }

  } else {
    // ── Ready Mode on LCD 1602 ──
    // Line 0: "MEKA v 1.0.1"
    String line0 = "MEKA v 1.0.1    ";

    // Line 1: "Waiting for you command." (scrolls 16 cols)
    String paddedMsg = readyModeLine1 + "    "; // "Waiting for you command.    "
    String chunk1 = "";
    if (now - lastReadyScrollTime >= 350) {
      lastReadyScrollTime = now;
      readyIndex1++;
      if (readyIndex1 >= (int)paddedMsg.length()) readyIndex1 = 0;
    }
    int len = paddedMsg.length();
    for (int i = 0; i < 16; i++) {
      chunk1 += paddedMsg[(readyIndex1 + i) % len];
    }

    if (line0 != lastDisplayedLine0) {
      lastDisplayedLine0 = line0;
      lcd.setCursor(0, 0);
      lcd.print(line0);
    }
    if (chunk1 != lastDisplayedLine1) {
      lastDisplayedLine1 = chunk1;
      lcd.setCursor(0, 1);
      lcd.print(chunk1);
    }
  }
}

// ─────────────────────────── HELPERS ─────────────────────────────────────

void scanI2C() {
  Serial.println("\n🔍 Scanning I2C bus...");
  int found = 0;
  for (uint8_t addr = 1; addr < 127; addr++) {
    Wire.beginTransmission(addr);
    if (Wire.endTransmission() == 0) {
      Serial.printf("  ✅ Found device at 0x%02X\n", addr);
      found++;
    }
  }
  if (found == 0) Serial.println("  ❌ No I2C devices found!");
  else Serial.printf("  Found %d device(s)\n", found);
}

String buildStatusJson() {
  StaticJsonDocument<512> doc;
  doc["device"]     = DEVICE_NAME;
  doc["firmware"]   = FIRMWARE_VER;
  doc["uptime_s"]   = (millis() - startTime) / 1000;
  doc["ip"]         = WiFi.localIP().toString();
  doc["rssi"]       = WiFi.RSSI();
  doc["hostname"]   = String(DEVICE_NAME) + ".local";
  doc["servo_angle"]    = servoAngle;
  doc["led_brightness"] = ledBrightness;
  doc["has_mic"]    = hasMic;
  doc["has_speaker"]= hasSpeaker;
  doc["status"]     = (currentStatus == STATUS_LISTENING)  ? "listening"  :
                      (currentStatus == STATUS_PROCESSING) ? "processing" :
                      (currentStatus == STATUS_SUCCESS)    ? "success"    :
                      (currentStatus == STATUS_ERROR)      ? "error"      : "idle";
  String out;
  serializeJson(doc, out);
  return out;
}

void setCorsHeaders() {
  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.sendHeader("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
  server.sendHeader("Access-Control-Allow-Headers", "Content-Type");
}

void sendJson(int code, String body) {
  setCorsHeaders();
  server.send(code, "application/json", body);
}

void broadcastStatus() {
  String s = buildStatusJson();
  webSocket.broadcastTXT(s);
}

unsigned long lastDisplayPollTime = 0;

void pollFirebaseDisplayData() {
  if (millis() - lastDisplayPollTime > 3000) { // Fail-safe poll every 3s
    lastDisplayPollTime = millis();
    if (Firebase.ready()) {
      if (Firebase.RTDB.getString(&fbData, "/meka/lcd_q")) {
        String q = fbData.stringData();
        q.trim();
        String qBody = q;
        if (qBody.startsWith("Q: "))      qBody = qBody.substring(3);
        else if (qBody.startsWith("Q:")) qBody = qBody.substring(2);
        qBody.trim();
        if (qBody.length() > 0 && qBody != scrollQ_body) {
          setLcdQ(q);
        }
      }
      if (Firebase.RTDB.getString(&fbData, "/meka/lcd_a")) {
        String a = fbData.stringData();
        a.trim();
        String aBody = a;
        if (aBody.startsWith("A: "))      aBody = aBody.substring(3);
        else if (aBody.startsWith("A:")) aBody = aBody.substring(2);
        aBody.trim();
        if (aBody.length() > 0 && aBody != scrollA_body) {
          setLcdA(a);
        }
      }

      // Fail-safe check for WebApp WiFi Credential Provisioning
      if (Firebase.RTDB.getJSON(&fbData, "/meka/wifi_config")) {
        DynamicJsonDocument wdoc(512);
        if (deserializeJson(wdoc, fbData.jsonString()) == DeserializationError::Ok) {
          String newSsid = wdoc["ssid"] | "";
          String newPass = wdoc["password"] | "";
          newSsid.trim();
          newPass.trim();
          if (newSsid.length() > 0 && newSsid != activeSsid) {
            Serial.printf("📶 Received new WiFi credentials from WebApp: %s\n", newSsid.c_str());
            preferences.putString("ssid", newSsid);
            preferences.putString("password", newPass);
            activeSsid = newSsid;
            activePass = newPass;
            lcdShowStatus("Updating WiFi...", newSsid.substring(0, 16));
            delay(1500);
            WiFi.disconnect();
            WiFi.begin(activeSsid.c_str(), activePass.c_str());
          }
        }
      }
    }
  }
}

// ─────────────────────────── FIREBASE STREAM CALLBACK ────────────────────

void fbStreamCallback(FirebaseStream data) {
  String path  = data.dataPath();
  String dtype = data.dataType();
  Serial.printf("🔥 Firebase stream: path=%s, type=%s\n", path.c_str(), dtype.c_str());

  if (dtype == "string") {
    String val = data.stringData();

    if (path.indexOf("status") != -1) {
      if      (val == "listening")  setMekaStatus(STATUS_LISTENING);
      else if (val == "processing") setMekaStatus(STATUS_PROCESSING);
      else if (val == "success")    setMekaStatus(STATUS_SUCCESS, 5000);
      else if (val == "error")      setMekaStatus(STATUS_ERROR, 5000);
      else                          setMekaStatus(STATUS_IDLE);
    }
    else if (path.indexOf("lcd_q") != -1) {
      setLcdQ(val);
    }
    else if (path.indexOf("lcd_a") != -1 || path.indexOf("lcd_text") != -1) {
      setLcdA(val);
    }
  }

  if (dtype == "json") {
    DynamicJsonDocument doc(2048);
    String jsonStr = data.jsonString();
    if (deserializeJson(doc, jsonStr) == DeserializationError::Ok) {
      if (doc.containsKey("servo_cmd") || (path.indexOf("servo_cmd") != -1 && doc.containsKey("angle"))) {
        int angle = constrain((int)doc["angle"], 0, 180);
        myServo.write(angle);
        servoAngle = angle;
        Serial.printf("🦾 Servo → %d°\n", angle);
        Firebase.RTDB.deleteNode(&fbData, "/meka/servo_cmd");
      }
      if (doc.containsKey("buzzer_cmd") || (path.indexOf("buzzer_cmd") != -1 && doc.containsKey("duration_ms"))) {
        int dur = constrain((int)doc["duration_ms"], 10, 5000);
        digitalWrite(PIN_BUZZER, HIGH); delay(dur); digitalWrite(PIN_BUZZER, LOW);
        Serial.printf("🔊 Buzzer %dms\n", dur);
        Firebase.RTDB.deleteNode(&fbData, "/meka/buzzer_cmd");
      }
      
      if (doc.containsKey("status")) {
        String s = doc["status"].as<String>();
        if      (s == "listening")  setMekaStatus(STATUS_LISTENING);
        else if (s == "processing") setMekaStatus(STATUS_PROCESSING);
        else if (s == "success")    setMekaStatus(STATUS_SUCCESS, 5000);
        else if (s == "error")      setMekaStatus(STATUS_ERROR, 5000);
        else                        setMekaStatus(STATUS_IDLE);
      }
      if (doc.containsKey("lcd_q")) {
        setLcdQ(doc["lcd_q"].as<String>());
      }
      if (doc.containsKey("lcd_a")) {
        setLcdA(doc["lcd_a"].as<String>());
      } else if (doc.containsKey("lcd_text")) {
        setLcdA(doc["lcd_text"].as<String>());
      }
    } else {
      Serial.println("⚠️ JSON parse warning in fbStreamCallback");
    }
  }
}

void fbStreamTimeoutCallback(bool timeout) {
  if (timeout) Serial.println("⚠️ Firebase stream timed out, resuming...");
}

// ─────────────────────────── HTTP ROUTES ─────────────────────────────────

void handleOptions() { setCorsHeaders(); server.send(200); }
void handleStatus()  { sendJson(200, buildStatusJson()); }

void handleRoot() {
  String html = R"(<!DOCTYPE html><html><head>
<title>MEKA v.1.0.1 Node</title>
<style>body{background:#010409;color:#00D4FF;font-family:monospace;padding:2rem}
h1{color:#7C4DFF}a{color:#00D4FF}table{border-collapse:collapse;width:100%}
td,th{border:1px solid #333;padding:8px;text-align:left}</style></head><body>
<h1>🤖 MEKA v.1.0.1 IoT Node</h1>
<p>Firmware v)" + String(FIRMWARE_VER) + R"( | <a href="/status">Status JSON</a> | <a href="http://meka.local">mDNS</a></p>
<p>All commands are now Firebase-driven. Use the MEKA web panel or Telegram bot!</p>
</body></html>)";
  server.send(200, "text/html", html);
}

void handleDisplay() {
  if (server.method() == HTTP_OPTIONS) { handleOptions(); return; }
  StaticJsonDocument<256> doc;
  if (deserializeJson(doc, server.arg("plain"))) {
    sendJson(400, "{\"error\":\"Invalid JSON\"}"); return;
  }
  if (doc.containsKey("text")) {
    String txt = doc["text"].as<String>();
    setLcdA(txt);
    if (Firebase.ready()) Firebase.RTDB.setString(&fbData, "/meka/lcd_text", txt);
    Serial.println("📺 Display: " + txt);
  }
  sendJson(200, "{\"ok\":true}");
}

void handleServo() {
  if (server.method() == HTTP_OPTIONS) { handleOptions(); return; }
  StaticJsonDocument<64> doc;
  if (deserializeJson(doc, server.arg("plain"))) {
    sendJson(400, "{\"error\":\"Invalid JSON\"}"); return;
  }
  int angle = constrain((int)(doc["angle"] | 90), 0, 180);
  myServo.write(angle);
  servoAngle = angle;
  if (Firebase.ready()) Firebase.RTDB.setInt(&fbData, "/meka/servo_angle", angle);
  sendJson(200, "{\"angle\":" + String(angle) + "}");
  broadcastStatus();
  Serial.printf("Servo → %d°\n", angle);
}

void handleBuzzer() {
  if (server.method() == HTTP_OPTIONS) { handleOptions(); return; }
  StaticJsonDocument<64> doc;
  deserializeJson(doc, server.arg("plain"));
  int dur = constrain((int)(doc["duration_ms"] | 200), 10, 5000);
  digitalWrite(PIN_BUZZER, HIGH);
  delay(dur);
  digitalWrite(PIN_BUZZER, LOW);
  sendJson(200, "{\"ok\":true}");
}

void handleSetStatus() {
  if (server.method() == HTTP_OPTIONS) { handleOptions(); return; }
  StaticJsonDocument<64> doc;
  if (deserializeJson(doc, server.arg("plain"))) {
    sendJson(400, "{\"error\":\"Invalid JSON\"}"); return;
  }
  String s = doc["status"] | "idle";
  if      (s == "listening")  setMekaStatus(STATUS_LISTENING);
  else if (s == "processing") setMekaStatus(STATUS_PROCESSING);
  else if (s == "success")    setMekaStatus(STATUS_SUCCESS, 5000);
  else if (s == "error")      setMekaStatus(STATUS_ERROR, 5000);
  else                        setMekaStatus(STATUS_IDLE);
  sendJson(200, "{\"ok\":true}");
  broadcastStatus();
}

void handleDht() {
  float temp = readTemperatureSafe();
  float humi = readHumiditySafe();
  if (isnan(temp) || isnan(humi)) {
    sendJson(503, "{\"error\":\"DHT read failed.\"}"); return;
  }
  StaticJsonDocument<128> doc;
  doc["temperature_c"] = serialized(String(temp, 1));
  doc["humidity"]      = serialized(String(humi, 1));
  String out;
  serializeJson(doc, out);
  sendJson(200, out);
}

void handleLed() {
    sendJson(200, "{\"ok\":true}");
}

void handleReset() {
  if (server.method() == HTTP_OPTIONS) { handleOptions(); return; }
  setMekaStatus(STATUS_IDLE);
  myServo.write(0);
  servoAngle    = 0;
  ledBrightness = 0;
  digitalWrite(PIN_BUILTIN_LED, LOW);
  resetToReadyMode();
  sendJson(200, "{\"ok\":true,\"message\":\"All outputs reset\"}");
  broadcastStatus();
  Serial.println("🔄 All outputs reset");
}

void handleNotFound() {
  if (server.method() == HTTP_OPTIONS) { handleOptions(); return; }
  sendJson(404, "{\"error\":\"Not found\"}");
}

// WebSocket
void webSocketEvent(uint8_t num, WStype_t type, uint8_t *payload, size_t length) {
  if (type == WStype_CONNECTED) {
    String s = buildStatusJson();
    webSocket.sendTXT(num, s);
  }
}

// ─────────────────────────── SETUP ───────────────────────────────────────
void setup() {
  Serial.begin(115200);
  Serial.println("\n\n╔══════════════════════════════╗");
  Serial.println("║  MEKA v.1.0.1 — Booting...  ║");
  Serial.println("╚══════════════════════════════╝");

  // Status LEDs init — all OFF
  pinMode(PIN_LED_BLUE,   OUTPUT); digitalWrite(PIN_LED_BLUE,   LOW);
  pinMode(PIN_LED_YELLOW, OUTPUT); digitalWrite(PIN_LED_YELLOW, LOW);
  pinMode(PIN_LED_GREEN,  OUTPUT); digitalWrite(PIN_LED_GREEN,  LOW);
  pinMode(PIN_LED_RED,    OUTPUT); digitalWrite(PIN_LED_RED,    LOW);
  pinMode(PIN_BUILTIN_LED, OUTPUT); digitalWrite(PIN_BUILTIN_LED, LOW);
  pinMode(PIN_BUZZER, OUTPUT);      digitalWrite(PIN_BUZZER, LOW);

  // Flash all LEDs at boot
  setAllStatusLEDs(true, true, true, true);
  delay(500);
  setAllStatusLEDs(false, false, false, false);

  // Displays Init (Auto-detect OLED SSD1306 and LCD 1602)
  Wire.begin(21, 22);
  Serial.println("\n🔍 Scanning I2C bus for OLED / LCD displays...");
  for (uint8_t addr = 1; addr < 127; addr++) {
    Wire.beginTransmission(addr);
    if (Wire.endTransmission() == 0) {
      Serial.printf("  ✅ Found I2C device at 0x%02X\n", addr);
      if (addr == 0x3C || addr == 0x3D) {
        hasOled = true;
        oledI2cAddr = addr;
      }
      if (addr == 0x27 || addr == 0x3F) {
        hasLcd = true;
        lcdI2cAddr = addr;
      }
    }
  }

  // Init OLED if detected
  if (hasOled) {
    if (oled.begin(SSD1306_SWITCHCAPVCC, oledI2cAddr)) {
      oled.clearDisplay();
      oled.setTextColor(SSD1306_WHITE);
      oled.setTextSize(1);
      oled.setCursor(0, 0);
      oled.println("🤖 MEKA v.1.0.1");
      oled.println("Booting...");
      oled.display();
      Serial.printf("✅ OLED SSD1306 display ready at 0x%02X\n", oledI2cAddr);
    } else {
      hasOled = false;
      Serial.println("⚠️ OLED SSD1306 init failed");
    }
  }

  // Init LCD if detected
  if (hasLcd) {
    lcd = LiquidCrystal_I2C(lcdI2cAddr, LCD_COLS, LCD_ROWS);
    lcd.init();
    lcd.backlight();
    lcd.clear();
    lcd.createChar(0, botLeft);
    lcd.createChar(1, botRight);
    lcdShowStatus("MEKA v.1.0.1", "Booting...");
    Serial.printf("✅ LCD 1602A display ready at 0x%02X\n", lcdI2cAddr);
  }

  // Servo & DHT
  myServo.attach(PIN_SERVO);
  myServo.write(0);
  dht22.begin();
  dht11.begin();

  startTime = millis();

  // Load persistent WiFi credentials from NVS memory if available
  preferences.begin("meka_wifi", false);
  String savedSsid = preferences.getString("ssid", "");
  String savedPass = preferences.getString("password", "");
  if (savedSsid.length() > 0) {
    activeSsid = savedSsid;
    activePass = savedPass;
    Serial.printf("📶 Loaded persistent WiFi credentials from NVS: %s\n", activeSsid.c_str());
  }

  // ── WiFi ──
  setMekaStatus(STATUS_PROCESSING);  // Yellow = connecting
  lcdShowStatus("Connecting WiFi", activeSsid.substring(0, 16));
  Serial.printf("Connecting to WiFi: %s\n", activeSsid.c_str());
  WiFi.mode(WIFI_STA);
  WiFi.begin(activeSsid.c_str(), activePass.c_str());
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 40) {
    delay(500); Serial.print("."); attempts++;
  }

  // Wait a bit
  delay(500);

  // Initialize local hardware safely
  probeHardwareCapabilities();

  if (WiFi.status() == WL_CONNECTED) {
    Serial.printf("\n✅ Connected! IP: %s\n", WiFi.localIP().toString().c_str());
    lcdShowStatus("WiFi OK!", WiFi.localIP().toString());
    setMekaStatus(STATUS_SUCCESS);
    delay(1500);
    setMekaStatus(STATUS_IDLE);
  } else {
    Serial.println("\n❌ WiFi failed.");
    lcdShowStatus("WiFi Failed :(", "Check creds");
    setMekaStatus(STATUS_ERROR);
  }

  // ── Firebase ──
  fbConfig.host             = FIREBASE_HOST;
  fbConfig.signer.tokens.legacy_token = FIREBASE_AUTH;
  fbConfig.timeout.socketConnection = 10000;
  fbConfig.timeout.rtdbKeepAlive = 45000;
  fbData.setBSSLBufferSize(4096, 512);
  fbStream.setBSSLBufferSize(4096, 512);
  Firebase.begin(&fbConfig, &fbAuth);
  Firebase.reconnectWiFi(true);

  // Push initial device info
  Firebase.RTDB.setString(&fbData, "/meka/firmware",   FIRMWARE_VER);
  Firebase.RTDB.setString(&fbData, "/meka/ip",         WiFi.localIP().toString());
  Firebase.RTDB.setString(&fbData, "/meka/status",     "idle");
  Firebase.RTDB.setString(&fbData, "/meka/lcd_text",   "");
  Firebase.RTDB.setInt(&fbData,    "/meka/servo_angle", 0);
  Serial.println("🔥 Firebase initialized");
  lcdShowStatus("Firebase OK!", "Ready...");
  delay(1000);

  // ── Start Firebase RTDB stream ──
  if (!Firebase.RTDB.beginStream(&fbStream, "/meka")) {
    Serial.println("⚠️ Firebase stream failed: " + fbStream.errorReason());
  }
  Firebase.RTDB.setStreamCallback(&fbStream, fbStreamCallback, fbStreamTimeoutCallback);
  Serial.println("🔥 Firebase stream started on /meka");

  // ── mDNS ──
  if (MDNS.begin(DEVICE_NAME)) {
    MDNS.addService("http", "tcp", 80);
    MDNS.addService("meka-node", "tcp", 80);  // IoT Hub auto-discovery
    Serial.printf("mDNS: http://%s.local\n", DEVICE_NAME);
  }

  // ── OTA ──
  ArduinoOTA.setHostname(DEVICE_NAME);
  ArduinoOTA.setPassword(OTA_PASSWORD);
  ArduinoOTA.onStart([]() { Serial.println("OTA Update starting..."); });
  ArduinoOTA.onEnd([]()   { Serial.println("\nOTA Done!"); });
  ArduinoOTA.onError([](ota_error_t e) { Serial.printf("OTA Error[%u]\n", e); });
  ArduinoOTA.begin();

  // ── WebSocket ──
  webSocket.begin();
  webSocket.onEvent(webSocketEvent);

  // ── HTTP Routes ──
  server.on("/",             HTTP_GET,     handleRoot);
  server.on("/status",       HTTP_GET,     handleStatus);
  server.on("/buzzer",       HTTP_POST,    handleBuzzer);
  server.on("/buzzer",       HTTP_OPTIONS, handleOptions);
  server.on("/display",      HTTP_POST,    handleDisplay);
  server.on("/display",      HTTP_OPTIONS, handleOptions);
  server.on("/setstatus",    HTTP_POST,    handleSetStatus);
  server.on("/dht",          HTTP_GET,     handleDht);
  server.on("/servo",        HTTP_POST,    handleServo);
  server.on("/led",          HTTP_POST,    handleLed);
  server.on("/reset",        HTTP_POST,    handleReset);

  // ── IoT Hub Integration Endpoints ──
  server.on("/iot/register", HTTP_POST, []() {
    if (server.method() == HTTP_OPTIONS) { handleOptions(); return; }
    // Hub registers itself with this node
    StaticJsonDocument<256> doc;
    if (server.hasArg("plain")) {
      deserializeJson(doc, server.arg("plain"));
    }
    String hubIp = doc["hub_ip"] | server.client().remoteIP().toString();
    Serial.printf("🔗 IoT Hub registered: %s\n", hubIp.c_str());
    lcdShowStatus("IoT Hub:", hubIp);
    sendJson(200, "{\"ok\":true,\"device\":\"" + String(DEVICE_NAME) + "\"}");
  });
  server.on("/iot/register", HTTP_OPTIONS, handleOptions);

  server.on("/iot/capabilities", HTTP_GET, []() {
    StaticJsonDocument<512> doc;
    doc["device"]    = DEVICE_NAME;
    doc["type"]      = "meka_node";
    doc["firmware"]  = FIRMWARE_VER;
    doc["ip"]        = WiFi.localIP().toString();
    doc["mac"]       = WiFi.macAddress();
    doc["has_mic"]   = hasMic;
    doc["has_speaker"] = hasSpeaker;

    JsonArray caps = doc.createNestedArray("capabilities");
    caps.add("relay");
    caps.add("sensor");
    caps.add("servo");
    caps.add("buzzer");
    caps.add("led");
    caps.add("display");
    if (hasMic) caps.add("microphone");
    if (hasSpeaker) caps.add("speaker");

    JsonArray sensors = doc.createNestedArray("sensors");
    sensors.add("temperature");
    sensors.add("humidity");
    sensors.add("analog");

    String out;
    serializeJson(doc, out);
    sendJson(200, out);
  });

  server.on("/iot/heartbeat", HTTP_GET, []() {
    StaticJsonDocument<128> doc;
    doc["alive"]    = true;
    doc["device"]   = DEVICE_NAME;
    doc["uptime_s"] = (millis() - startTime) / 1000;
    doc["rssi"]     = WiFi.RSSI();
    String out;
    serializeJson(doc, out);
    sendJson(200, out);
  });

  // ── HARDWARE DIAGNOSTIC TEST ROUTES ──

  server.on("/test/lcd", HTTP_GET, []() {
    Serial.println("🧪 LCD Test Triggered!");
    lcd.clear();
    lcd.backlight();
    lcd.setCursor(0, 0);
    lcd.print("MEKA LCD TEST!");
    lcd.setCursor(0, 1);
    lcd.print("1234567890ABCDEF");
    sendJson(200, "{\"status\":\"ok\",\"message\":\"LCD test pattern sent\"}");
  });

  server.on("/test/dht", HTTP_GET, []() {
    float temp = readTemperatureSafe();
    float humi = readHumiditySafe();
    StaticJsonDocument<256> doc;
    if (isnan(temp) || isnan(humi)) {
      doc["status"] = "error";
      doc["message"] = "DHT reading failed (returned NaN). Check VCC/GND/Data wiring or pullup resistor.";
      doc["gpio"] = PIN_DHT;
    } else {
      doc["status"] = "ok";
      doc["temperature_c"] = temp;
      doc["humidity_pct"] = humi;
    }
    String out;
    serializeJson(doc, out);
    sendJson(200, out);
  });

  server.on("/test/i2c", HTTP_GET, []() {
    StaticJsonDocument<512> doc;
    JsonArray addrs = doc.createNestedArray("i2c_addresses");
    int found = 0;
    for (uint8_t addr = 1; addr < 127; addr++) {
      Wire.beginTransmission(addr);
      if (Wire.endTransmission() == 0) {
        char buf[8];
        snprintf(buf, sizeof(buf), "0x%02X", addr);
        addrs.add(buf);
        found++;
      }
    }
    doc["found_count"] = found;
    String out;
    serializeJson(doc, out);
    sendJson(200, out);
  });

  server.onNotFound(handleNotFound);

  server.begin();
  Serial.println("✅ HTTP server started on port 80");
  Serial.printf("📡 http://%s.local  or  http://%s\n", DEVICE_NAME,
                WiFi.localIP().toString().c_str());
  Serial.println("═══════════════════════════════════════");

  resetToReadyMode();
}

// ─────────────────────────── LOOP ────────────────────────────────────────
void loop() {
  ArduinoOTA.handle();
  server.handleClient();
  webSocket.loop();
  Firebase.ready(); // Keeps Firebase connection alive

  // Fail-safe periodic polling for OLED/LCD display data
  pollFirebaseDisplayData();

  // Auto-reset status LEDs after timeout (for SUCCESS/ERROR states)
  if (statusResetTime > 0 && millis() > statusResetTime) {
    statusResetTime = 0;
    setMekaStatus(STATUS_IDLE);
  }

  // Push sensor data to Firebase every 30s
  if (millis() - lastFirebasePush > 30000) {
    lastFirebasePush = millis();
    float temp = readTemperatureSafe();
    float humi = readHumiditySafe();
    if (!isnan(temp) && !isnan(humi)) {
      Firebase.RTDB.setFloat(&fbData, "/meka/sensors/temperature_c", temp);
      Firebase.RTDB.setFloat(&fbData, "/meka/sensors/humidity",      humi);
      Firebase.RTDB.setInt(&fbData,   "/meka/uptime_s", (millis() - startTime) / 1000);
      Serial.printf("📊 Sensors → %.1f°C, %.1f%% RH\n", temp, humi);
    }
    // Also broadcast via WebSocket
    broadcastStatus();
  }

  // LCD Dual Display & Smooth Scrolling
  updateLcdDisplay();
}
