import { GoogleGenerativeAI } from "@google/generative-ai";

const API_KEY = import.meta.env.VITE_GEMINI_API_KEY;
const HUB_URL = import.meta.env.VITE_HUB_URL || "http://localhost:5000";

let genAI = null;
let model = null;

if (API_KEY) {
  genAI = new GoogleGenerativeAI(API_KEY);
  model = genAI.getGenerativeModel({ model: "gemini-2.5-flash" });
}

export class LlmService {
  constructor(userName = "Sir") {
    this.userName = userName;
    this.history = [];
  }

  /** Call after auth so MEKA addresses the user by name */
  setUserName(name) {
    if (name) this.userName = name;
  }

  get systemInstruction() {
    const now = new Date().toLocaleString();
    return `You are MEKA — an advanced AI personal assistant. You serve exclusively ${this.userName}.

PERSONALITY:
- Sophisticated, intelligent, slightly witty
- Speak in short, confident, actionable sentences. Maximum 2-3 sentences.
- Never say "I'm just an AI" — find creative ways to help.

Current time: ${now}

CAPABILITIES (use JSON commands for device actions embedded anywhere in your response):
- Unlock device/phone: {"action":"unlock_device","ip":"192.168.1.x"}
- Take screenshot: {"action":"device_screenshot","ip":"192.168.1.x"}
- Execute ADB shell command: {"action":"adb_shell","ip":"192.168.1.x","cmd":"input keyevent 26"}

IOT HUB / ESP32 HARDWARE CONTROL:
- Scan WiFi network: {"action":"iot_scan"}
- List cameras: {"action":"iot_list_cameras"}
- Control relay: {"action":"esp32_relay","channel":1,"state":"on"}
- Set NeoPixel color: {"action":"esp32_led","color":"cyan"}

Always output standard conversational text. If you want to trigger an action, embed the raw JSON object inside your reply.
Example: "Right away ${this.userName}, scanning network. {"action":"iot_scan"}"`;
  }

  async chat(text) {
    if (!model) {
      throw new Error("Gemini API key is not configured in .env (VITE_GEMINI_API_KEY)");
    }

    // Build history for this chat session (all previous turns)
    const chatHistory = [...this.history];

    try {
      const chat = model.startChat({
        systemInstruction: { role: "system", parts: [{ text: this.systemInstruction }] },
        history: chatHistory, // Previous turns only — sendMessage adds the new user turn
      });

      // Send the new user message
      const result = await chat.sendMessage(text);
      const responseText = result.response.text() || "";

      // Store the full turn in history AFTER success
      this.history.push({ role: "user",  parts: [{ text }] });
      this.history.push({ role: "model", parts: [{ text: responseText }] });

      // Keep history bounded to last 20 turns (40 entries) to avoid token overflow
      if (this.history.length > 40) {
        this.history = this.history.slice(this.history.length - 40);
      }

      // Parse out JSON commands and execute them via the IoT Hub
      const cleanText = await this.executeExtractedCommands(responseText);
      return cleanText.trim() || "Command acknowledged.";
    } catch (err) {
      console.error("LLM Error:", err);
      throw err;
    }
  }

  async executeExtractedCommands(responseText) {
    let cleanText = responseText;
    const jsonRegex = /\{[^{}]*\}/g;  // Non-nested JSON objects
    const matches = responseText.match(jsonRegex);

    if (matches) {
      for (const match of matches) {
        try {
          const cmd = JSON.parse(match);
          if (cmd.action) {
            cleanText = cleanText.replace(match, "").trim();
            console.log("MEKA Executing Action:", cmd.action, cmd);
            await this.proxyToHub(cmd);
          }
        } catch {
          // Not a valid JSON command — ignore
        }
      }
    }
    return cleanText;
  }

  async proxyToHub(cmd) {
    try {
      let endpoint = "/api/execute";
      let method = "POST";
      let body = cmd;

      if (cmd.action === "iot_scan") {
        endpoint = "/api/devices/scan";
      } else if (cmd.action === "iot_list_cameras") {
        endpoint = "/api/cameras";
        method = "GET";
        body = null;
      } else if (cmd.action.startsWith("esp32_")) {
        endpoint = "/api/esp32/control";
      } else if (cmd.action.startsWith("adb_") || ["unlock_device", "device_screenshot"].includes(cmd.action)) {
        endpoint = "/api/adb/execute";
      }

      const options = {
        method,
        headers: { "Content-Type": "application/json" },
        mode: "cors",
      };
      if (body) options.body = JSON.stringify(body);

      const res = await fetch(`${HUB_URL}${endpoint}`, options);
      const data = await res.json();
      console.log("Hub Response:", data);
      return data;
    } catch (e) {
      console.error("Failed to execute hub command:", e);
    }
  }

  clearHistory() {
    this.history = [];
  }
}

export const llm = new LlmService();
