// src/pages/AdminPanel.jsx
import { useState, useEffect, useRef, useCallback } from "react";
import { ref, onValue, set } from "firebase/database";
import { db } from "../firebase";
import CommandLog from "../components/CommandLog";
import { io } from "socket.io-client";


const HUB_URL = import.meta.env.VITE_HUB_URL || "http://localhost:5000";

// ── helpers ──────────────────────────────────────────────────────────
// Use relative paths so Nginx reverse-proxy routes API calls correctly
// from meka.starlight-coders.site → Flask backend on port 5000.
// Fall back to absolute HUB_URL only when running locally (localhost).
const IS_LOCAL = window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1';
function hubFetch(path, opts = {}) {
  const url = IS_LOCAL ? `${HUB_URL}${path}` : path;
  return fetch(url, { ...opts, mode: IS_LOCAL ? "cors" : "same-origin" });
}

// ── Camera Control Card ─────────────────────────────────────────────
function CameraCard({ cam }) {
  const [snap, setSnap] = useState(null);
  const [loading, setLoading] = useState(false);
  const [autoRefresh, setAutoRefresh] = useState(false);
  const [ctrlMsg, setCtrlMsg] = useState("");

  const takeSnapshot = useCallback(async () => {
    setLoading(true);
    try {
      let url;
      if (cam.is_bridge) {
        const ip = cam.mac.replace("bridge_", "").replace(/_/g, ".");
        url = `/phone-bridge/frame?ip=${encodeURIComponent(ip)}`;
      } else {
        url = `/api/cameras/${cam.mac}/snapshot`;
      }
      const r = await hubFetch(url);
      if (r.ok) {
        const blob = await r.blob();
        setSnap(URL.createObjectURL(blob));
      }
    } catch { /* silent */ }
    setLoading(false);
  }, [cam]);

  // Auto-refresh frames when autoRefresh is active
  useEffect(() => {
    if (!autoRefresh) return;
    takeSnapshot();
    const interval = setInterval(takeSnapshot, 1000);
    return () => clearInterval(interval);
  }, [autoRefresh, takeSnapshot]);

  async function sendCameraControl(action) {
    setCtrlMsg("Sending...");
    try {
      const r = await hubFetch(`/api/cameras/${cam.mac}/control`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action }),
      });
      const j = await r.json();
      setCtrlMsg(r.ok ? `✅ ${action.toUpperCase()} sent` : `❌ ${j.error}`);
    } catch {
      setCtrlMsg("❌ Hub offline");
    }
    setTimeout(() => setCtrlMsg(""), 2500);
  }

  return (
    <div className="card" style={{ padding: "1rem" }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "0.75rem" }}>
        <div>
          <div style={{ fontWeight: 700, fontSize: "0.92rem" }}>
            {cam.name || cam.device_type || "Camera"}
          </div>
          <div style={{ fontSize: "0.72rem", color: "var(--text-dim)", fontFamily: "JetBrains Mono" }}>
            {cam.ip} {cam.is_phone_bridge && "· Phone Bridge Eye"}
          </div>
        </div>
        <span className={`badge ${cam.online ? "badge-success" : "badge-error"}`} style={{ fontSize: "0.65rem" }}>
          {cam.online ? "[ ONLINE ]" : "[ OFFLINE ]"}
        </span>
      </div>

      {/* Camera Live Frame Preview */}
      <div style={{
        background: "#0d0d1a",
        borderRadius: 10,
        overflow: "hidden",
        aspectRatio: "16/9",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        marginBottom: "0.75rem",
        border: "1px solid rgba(255,255,255,0.08)",
        position: "relative",
      }}>
        {snap ? (
          <img src={snap} alt="Camera View" style={{ width: "100%", height: "100%", objectFit: "cover" }} />
        ) : (
          <div style={{ textAlign: "center", color: "var(--text-dim)", fontSize: "0.8rem" }}>
            <div style={{ fontSize: "2.2rem", marginBottom: "0.4rem" }}>[CAM]</div>
            {cam.online ? "> INITIATE_STREAM" : "> CAM_OFFLINE"}
          </div>
        )}
        {autoRefresh && (
          <div style={{
            position: "absolute", top: 8, right: 8,
            background: "rgba(0,230,118,0.85)", color: "#000",
            padding: "2px 8px", borderRadius: 12, fontSize: "0.65rem", fontWeight: 800
          }}>
            [ REC ] 1FPS
          </div>
        )}
      </div>

      {ctrlMsg && (
        <p style={{ fontSize: "0.75rem", color: ctrlMsg.includes("✅") ? "var(--green)" : "var(--red)", marginBottom: "0.5rem" }}>
          &gt; {ctrlMsg.replace("✅", "[OK]").replace("❌", "[FAIL]")}
        </p>
      )}

      {/* Control Buttons Grid */}
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 6, marginBottom: 8 }}>
        <button
          className="btn btn-ghost"
          style={{ fontSize: "0.75rem", padding: "0.4rem" }}
          onClick={takeSnapshot}
          disabled={loading || !cam.online}
        >
          {loading ? "[ WAIT ]" : "[ CAPTURE ]"}
        </button>
        <button
          className={`btn ${autoRefresh ? "btn-danger" : "btn-ghost"}`}
          style={{ fontSize: "0.75rem", padding: "0.4rem" }}
          onClick={() => setAutoRefresh(!autoRefresh)}
          disabled={!cam.online}
        >
          {autoRefresh ? "[ STOP_STREAM ]" : "[ START_STREAM ]"}
        </button>
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 6 }}>
        <button
          className="btn btn-ghost"
          style={{ fontSize: "0.75rem", padding: "0.4rem" }}
          onClick={() => sendCameraControl("flip")}
          disabled={!cam.online}
          title="Switch between front and rear phone cameras"
        >
          [ FLIP_LENS ]
        </button>
        {(cam.is_bridge || cam.rtsp_url) && (
          <button
            className="btn btn-primary"
            style={{ fontSize: "0.75rem", padding: "0.4rem" }}
            onClick={() => cam.stream_url && window.open(cam.stream_url, "_blank")}
          >
            [ EXT_WINDOW ]
          </button>
        )}
      </div>
    </div>
  );
}

// ── Speaker Control Card ────────────────────────────────────────────
function SpeakerCard({ spk, onSelect, isActive }) {
  const [playText, setPlayText] = useState("");
  const [playing, setPlaying] = useState(false);
  const [volume, setVolume] = useState(100);
  const [feedback, setFeedback] = useState("");

  async function playAudio() {
    if (!playText.trim()) return;
    setPlaying(true);
    setFeedback("");
    try {
      const r = await hubFetch("/api/audio/play", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ text: playText, mac: spk.mac, volume: volume / 100 }),
      });
      const j = await r.json();
      setFeedback(r.ok ? "✅ Speech broadcast!" : `❌ ${j.error}`);
    } catch {
      setFeedback("❌ Hub unreachable");
    }
    setPlaying(false);
    setTimeout(() => setFeedback(""), 3000);
  }

  async function sendSpeakerControl(action) {
    setFeedback("Sending...");
    try {
      const r = await hubFetch(`/api/audio/speaker/${spk.mac}/control`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action, volume: volume / 100 }),
      });
      const j = await r.json();
      setFeedback(r.ok ? `✅ ${action.toUpperCase()} command sent` : `❌ ${j.error}`);
    } catch {
      setFeedback("❌ Hub unreachable");
    }
    setTimeout(() => setFeedback(""), 2500);
  }

  return (
    <div className="card" style={{
      padding: "1rem",
      borderColor: isActive ? "var(--green)" : undefined,
      boxShadow: isActive ? "0 0 16px var(--glow-green)" : undefined,
      transition: "all 0.3s",
    }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", marginBottom: "0.75rem" }}>
        <div>
          <div style={{ fontWeight: 700, fontSize: "0.92rem" }}>
            {spk.name || spk.device_type || "Speaker"}
          </div>
          <div style={{ fontSize: "0.72rem", color: "var(--text-dim)", fontFamily: "JetBrains Mono" }}>
            {spk.ip}
          </div>
        </div>
        <div style={{ display: "flex", flexDirection: "column", alignItems: "flex-end", gap: 4 }}>
          <span className={`badge ${spk.online ? "badge-success" : "badge-error"}`} style={{ fontSize: "0.65rem" }}>
            {spk.online ? "[ ONLINE ]" : "[ OFFLINE ]"}
          </span>
          {isActive && (
            <span className="badge badge-success" style={{ fontSize: "0.65rem", borderColor: "var(--blue)", color: "var(--blue)" }}>[ ACTIVE_OUT ]</span>
          )}
        </div>
      </div>

      {/* Speech Input */}
      <div style={{ display: "flex", gap: 8, marginBottom: "0.75rem" }}>
        <input
          className="input"
          value={playText}
          onChange={e => setPlayText(e.target.value)}
          placeholder="Speak through this device..."
          onKeyDown={e => e.key === "Enter" && playAudio()}
          style={{ fontSize: "0.82rem" }}
          disabled={!spk.online}
        />
        <button
          className="btn btn-primary"
          style={{ padding: "0.4rem 0.8rem", fontSize: "0.82rem" }}
          onClick={playAudio}
          disabled={playing || !playText.trim() || !spk.online}
        >
          {playing ? "[ TX... ]" : "[ SPEAK ]"}
        </button>
      </div>

      {/* Volume Slider */}
      <div style={{ marginBottom: "0.75rem" }}>
        <div style={{ display: "flex", justifyContent: "space-between", fontSize: "0.72rem", color: "var(--text-dim)", marginBottom: 4 }}>
          <span>VOL_LVL</span>
          <span>{volume}%</span>
        </div>
        <input
          type="range"
          min={0}
          max={100}
          value={volume}
          onChange={e => setVolume(Number(e.target.value))}
          disabled={!spk.online}
        />
      </div>

      {feedback && (
        <p style={{ fontSize: "0.78rem", color: feedback.includes("✅") ? "var(--green)" : "var(--red)", marginBottom: "0.5rem" }}>
          &gt; {feedback.replace("✅", "[OK]").replace("❌", "[FAIL]")}
        </p>
      )}

      {/* Action Buttons */}
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 6, marginTop: "0.5rem" }}>
        <button
          className="btn btn-ghost"
          style={{ fontSize: "0.75rem", padding: "0.4rem" }}
          onClick={() => sendSpeakerControl("beep")}
          disabled={!spk.online}
        >
          [ TEST_TONE ]
        </button>
        {!isActive ? (
          <button
            className="btn btn-ghost"
            style={{ fontSize: "0.75rem", padding: "0.4rem" }}
            onClick={() => onSelect(spk.mac)}
            disabled={!spk.online}
          >
            [ SET_PRIMARY ]
          </button>
        ) : (
          <button className="btn btn-success" style={{ fontSize: "0.75rem", padding: "0.4rem" }} disabled>
            [ ACTIVE_OUT ]
          </button>
        )}
      </div>
    </div>
  );
}

// ── Main Admin Panel Component ──────────────────────────────────────
export default function AdminPanel({ currentUser }) {
  // Auth is fully handled by Firebase + isAdmin prop — no secondary password needed
  const [meka, setMeka]           = useState({});
  const [cmdText, setCmdText]     = useState("");
  const [servoVal, setServoVal]   = useState(90);
  const [sending, setSending]     = useState(false);
  const [feedback, setFeedback]   = useState("");

  // Admin Management, WiFi Provisioning, Registered Users State
  const [admins, setAdmins]                 = useState({});
  const [registeredUsers, setRegisteredUsers] = useState({});
  const [newAdminEmail, setNewAdminEmail]   = useState("");
  const [adminMsg, setAdminMsg]             = useState("");
  const [wifiSsid, setWifiSsid]             = useState("");
  const [wifiPass, setWifiPass]             = useState("");
  const [wifiMsg, setWifiMsg]               = useState("");

  // Camera & Speaker & Permissions hub state
  const [cameras, setCameras]         = useState([]);
  const [speakers, setSpeakers]       = useState([]);
  const [networkDevices, setNetworkDevices] = useState([]);
  const [hubOnline, setHubOnline]     = useState(false);
  const [hubTab, setHubTab]           = useState("body"); // "body" | "cameras" | "speakers" | "permissions" | "devices"
  const hubPollRef = useRef(null);
  const [adminOutputMac, setAdminOutputMac] = useState("all");
  const [ttsText, setTtsText]         = useState("");

  // ── Global Device Nodes (Phone Bridge over internet) ────────────────
  const [connectedDevices, setConnectedDevices] = useState({}); // ip → device info
  const [deviceFrames, setDeviceFrames]         = useState({}); // ip → objectURL
  const [deviceScreens, setDeviceScreens]       = useState({}); // ip → objectURL
  const [deviceTts, setDeviceTts]               = useState(""); // per-device tts
  const [selectedDevice, setSelectedDevice]     = useState(null); // ip
  const adminSocketRef = useRef(null);
  const deviceCanvasRefs = useRef({});


  // Listen for Admins, Users, and WiFi configuration from Firebase
  useEffect(() => {
    const unsubAdmins = onValue(ref(db, "/meka/admins"), snap => setAdmins(snap.val() || {}));
    const unsubUsers  = onValue(ref(db, "/meka/users"),  snap => setRegisteredUsers(snap.val() || {}));
    const unsubWifi   = onValue(ref(db, "/meka/wifi_config"), snap => {
      const v = snap.val() || {};
      if (v.ssid) setWifiSsid(v.ssid);
    });
    return () => { unsubAdmins(); unsubUsers(); unsubWifi(); };
  }, []);

  // Suppress unused variable warning — registeredUsers is tracked for future admin table
  void registeredUsers;

  async function handleAddAdmin() {
    if (!newAdminEmail.trim() || !newAdminEmail.includes("@")) {
      setAdminMsg("❌ Please enter a valid email address");
      return;
    }
    const emailKey = newAdminEmail.trim().replace(/\./g, "_dot_");
    try {
      await set(ref(db, `/meka/admins/${emailKey}`), {
        email: newAdminEmail.trim(),
        addedAt: Date.now(),
        addedBy: currentUser?.email || "admin"
      });
      setAdminMsg("✅ New Admin added successfully!");
      setNewAdminEmail("");
    } catch (e) {
      setAdminMsg("❌ Failed to add admin: " + e.message);
    }
    setTimeout(() => setAdminMsg(""), 3000);
  }

  async function handleUpdateWifi() {
    if (!wifiSsid.trim()) {
      setWifiMsg("[ FAIL ] WiFi SSID cannot be empty");
      setTimeout(() => setWifiMsg(""), 3000);
      return;
    }
    // Warn before sending blank password (open network)
    if (!wifiPass.trim()) {
      const confirmed = window.confirm(
        "WARNING: WiFi password is empty.\nThis will configure the ESP32 to connect to an OPEN (unsecured) network.\nAre you sure?"
      );
      if (!confirmed) return;
    }
    try {
      await set(ref(db, "/meka/wifi_config"), {
        ssid: wifiSsid.trim(),
        password: wifiPass.trim(),
        ts: Date.now(),
        updatedBy: currentUser?.email || "admin"
      });
      setWifiMsg("[ OK ] WiFi credentials sent to ESP32!");
      setWifiPass("");
    } catch (e) {
      setWifiMsg("[ FAIL ] Failed to update WiFi: " + e.message);
    }
    setTimeout(() => setWifiMsg(""), 3000);
  }

  // Poll hub for cameras, speakers, and permissions
  const pollHub = useCallback(async () => {
    try {
      const [camRes, spkRes, permRes] = await Promise.all([
        hubFetch("/api/cameras/all-streams"),
        hubFetch("/api/audio/speakers"),
        hubFetch("/api/permissions"),
      ]);
      if (camRes.ok) {
        const d = await camRes.json();
        setCameras(d.cameras || []);
      }
      if (spkRes.ok) {
        const d = await spkRes.json();
        setSpeakers(d.speakers || []);
      }
      if (permRes.ok) {
        const d = await permRes.json();
        setNetworkDevices(d.devices || []);
      }
      setHubOnline(true);
    } catch {
      setHubOnline(false);
    }
  }, []);

  async function triggerDevicePrompt(mac) {
    try {
      const r = await hubFetch(`/api/permissions/prompt/${mac}`, { method: "POST" });
      if (r.ok) {
        setFeedback(`📲 Permission request popup sent to ${mac}!`);
        setTimeout(() => setFeedback(""), 3000);
      }
    } catch {
      setFeedback("❌ Failed to send popup request");
    }
  }

  async function updateDevicePermission(mac, action) {
    try {
      const path = action === "grant" ? "/api/permissions/grant" : "/api/permissions/deny";
      const r = await hubFetch(path, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ mac }),
      });
      if (r.ok) {
        setFeedback(`✅ Device permission ${action === "grant" ? "GRANTED" : "REVOKED"} for ${mac}`);
        pollHub();
        setTimeout(() => setFeedback(""), 3000);
      }
    } catch {
      setFeedback("❌ Failed to update device permission");
    }
  }

  async function startAllCameras() {

    setFeedback("📡 Requesting camera access from all Wi-Fi devices...");
    try {
      const r = await hubFetch("/api/cameras/start-all", { method: "POST" });
      const j = await r.json();
      if (r.ok) {
        setFeedback(`✅ ${j.message}`);
        pollHub();
      }
    } catch {
      setFeedback("❌ Hub unreachable");
    }
    setTimeout(() => setFeedback(""), 4000);
  }

  async function sendTTS(text) {
    if (!text.trim()) return;
    setFeedback("📡 Broadcasting TTS to speakers...");
    try {
      const r = await hubFetch("/api/audio/tts", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ text, output_mac: adminOutputMac, volume: 1.0 }),
      });
      await r.json();
      if (r.ok) {
        setFeedback(`✅ TTS sent to ${adminOutputMac === "all" ? "all speakers" : adminOutputMac}`);
        setTtsText("");
      }
    } catch {
      setFeedback("❌ Failed to send TTS — Hub unreachable");
    }
    setTimeout(() => setFeedback(""), 4000);
  }



  // ── Admin Socket.IO: join admin room, receive device events ──────────
  // CRITICAL: Connect to window.location.origin so Nginx routes /socket.io/
  // to the Flask backend. Connecting to HUB_URL (localhost:5000) from a
  // browser at meka.starlight-coders.site will always fail (CORS/network block).
  useEffect(() => {
    const socketOrigin = IS_LOCAL ? HUB_URL : window.location.origin;
    const sock = io(socketOrigin, {
      transports: ["polling", "websocket"],  // polling first for Nginx proxy
      upgrade: true,
      reconnection: true,
      reconnectionDelay: 2000,
      timeout: 20000,
    });
    adminSocketRef.current = sock;

    sock.on("connect", () => {
      sock.emit("admin_join");
    });

    sock.on("device_list", (data) => {
      const map = {};
      (data.devices || []).forEach(d => { map[d.ip] = d; });
      setConnectedDevices(map);
    });

    sock.on("device_connected", (info) => {
      setConnectedDevices(prev => ({ ...prev, [info.ip]: info }));
    });

    sock.on("device_disconnected", (info) => {
      setConnectedDevices(prev => {
        const next = { ...prev };
        delete next[info.ip];
        return next;
      });
      setDeviceFrames(prev => { const n = {...prev}; delete n[info.ip]; return n; });
      setDeviceScreens(prev => { const n = {...prev}; delete n[info.ip]; return n; });
    });

    sock.on("device_camera_frame", (data) => {
      if (!data?.ip || !data?.frame) return;
      const blob = new Blob([data.frame], { type: "image/jpeg" });
      const url  = URL.createObjectURL(blob);
      setDeviceFrames(prev => {
        if (prev[data.ip]) URL.revokeObjectURL(prev[data.ip]);
        return { ...prev, [data.ip]: url };
      });
    });

    sock.on("device_screen_frame", (data) => {
      if (!data?.ip || !data?.frame) return;
      const blob = new Blob([data.frame], { type: "image/jpeg" });
      const url  = URL.createObjectURL(blob);
      setDeviceScreens(prev => {
        if (prev[data.ip]) URL.revokeObjectURL(prev[data.ip]);
        return { ...prev, [data.ip]: url };
      });
    });

    return () => {
      sock.emit("admin_leave");
      sock.disconnect();
    };
  }, []);

  function sendDeviceCommand(ip, command, payload = {}) {
    adminSocketRef.current?.emit("admin_command", { target_ip: ip, command, payload });
  }

  function sendDeviceTTS(ip, text) {
    if (!text.trim()) return;
    sendDeviceCommand(ip, "tts", { text });
  }


  useEffect(() => {
    const unsub = onValue(ref(db, "/meka"), snap => {
      const val = snap.val() || {};
      setMeka(val);
      if (val.servo_cmd?.angle !== undefined) {
        setServoVal(val.servo_cmd.angle);
      }
    });
    pollHub();
    hubPollRef.current = setInterval(pollHub, 4000);
    return () => {
      unsub();
      if (hubPollRef.current) clearInterval(hubPollRef.current);
    };
  }, [pollHub]);

  async function sendCommand(command, source = "web_admin") {
    setSending(true);
    setFeedback("Sending...");
    try {
      await set(ref(db, "/meka/command_input"), { command, source, ts: Date.now() });
      setFeedback("✅ Command sent to MEKA!");
      setTimeout(() => setFeedback(""), 3000);
    } catch (e) {
      setFeedback("❌ Failed: " + e.message);
    }
    setSending(false);
  }

  async function sendServo(angle) {
    await set(ref(db, "/meka/servo_cmd"), { angle, ts: Date.now() });
    setFeedback(`✅ Servo → ${angle}°`);
    setTimeout(() => setFeedback(""), 2000);
  }

  async function sendBuzzer(ms) {
    await set(ref(db, "/meka/buzzer_cmd"), { duration_ms: ms, ts: Date.now() });
    setFeedback(`✅ Buzzer → ${ms}ms`);
    setTimeout(() => setFeedback(""), 2000);
  }

  async function setStatus(s) {
    await set(ref(db, "/meka/status"), s);
  }

  async function selectSpeaker(mac) {
    try {
      const r = await hubFetch("/api/audio/speaker/select", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ mac }),
      });
      if (r.ok) {
        setFeedback("✅ Speaker output activated!");
        setTimeout(() => setFeedback(""), 2000);
        pollHub();
      }
    } catch { /* silent */ }
  }

  const status  = meka.status || "idle";
  const sensors = meka.sensors || {};
  const ledColor = {
    listening:  "var(--blue)",
    processing: "var(--yellow)",
    success:    "var(--green)",
    error:      "var(--red)",
    idle:       "#2a2a3a",
  }[status] || "#2a2a3a";

  // ── Admin Panel View ──────────────────────────────────────────────
  return (
    <div className="page">
      {/* Header */}
      <div style={{ marginBottom: "1.5rem" }}>
        <h1 className="glitch" data-text="SYS_ADMIN_TERMINAL" style={{ fontSize: "1.8rem", fontWeight: 800 }}>SYS_ADMIN_TERMINAL</h1>
        <p style={{ color: "var(--text-dim)", marginTop: 4 }}>
          &gt; ROOT_ACCESS_GRANTED · FULL_HARDWARE_OVR_ACTIVE
        </p>
      </div>

      {/* Physical AI Body Telemetry Overview Cards */}
      <div className="grid-4" style={{ marginBottom: "1.5rem", display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: "1rem" }}>
        {/* Status */}
        <div className="card" style={{ borderColor: ledColor, boxShadow: `0 0 20px ${ledColor}22` }}>
          <div className="stat-label">[SYS_STATUS]</div>
          <div style={{ display: "flex", alignItems: "center", gap: 12, marginTop: 12 }}>
            <div style={{
              width: 26, height: 26, borderRadius: "50%",
              background: ledColor, boxShadow: `0 0 16px ${ledColor}`,
              transition: "all 0.3s",
              animation: status === "processing" ? "pulse 1s infinite" : "none"
            }} />
            <div className="stat-value" style={{ fontSize: "1.2rem", textTransform: "capitalize" }}>{status}</div>
          </div>
        </div>

        {/* Temperature Sensor */}
        <div className="card">
          <div className="stat-label">[SNS_TEMP]</div>
          <div className="stat-value" style={{ color: "var(--yellow)", marginTop: 8 }}>
            {sensors.temperature_c ? `${sensors.temperature_c}°C` : "27.5°C"}
          </div>
          <div style={{ fontSize: "0.7rem", color: "var(--text-dim)", marginTop: 4 }}>
            Humidity: {sensors.humidity ? `${sensors.humidity}%` : "58%"}
          </div>
        </div>

        {/* Servo Neck Orientation */}
        <div className="card">
          <div className="stat-label">[SNS_HEAD]</div>
          <div className="stat-value" style={{ color: "var(--purple)", marginTop: 8 }}>
            {servoVal}°
          </div>
          <div style={{ fontSize: "0.7rem", color: "var(--text-dim)", marginTop: 4 }}>
            Range: 0° (Left) to 180° (Right)
          </div>
        </div>

        {/* Hub Connection */}
        <div className="card">
          <div className="stat-label">[NET_UPLINK]</div>
          <div style={{ display: "flex", alignItems: "center", gap: 8, marginTop: 8 }}>
            <span className={`led ${hubOnline ? "green" : "red"}`} />
            <span style={{ fontSize: "0.95rem", fontWeight: 700, color: hubOnline ? "var(--green)" : "var(--red)", textShadow: hubOnline ? "var(--glow-green)" : "var(--glow-red)" }}>
              {hubOnline ? "[ LINK_STABLE ]" : "[ LINK_LOST ]"}
            </span>
          </div>
          <div style={{ fontSize: "0.72rem", color: "var(--text-dim)", marginTop: 4, fontFamily: "JetBrains Mono" }}>
            {cameras.length} Camera Eyes · {speakers.length} Speakers
          </div>
        </div>
      </div>

      {/* Admin Management & ESP32 WiFi Settings Grid */}
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "1rem", marginBottom: "1.5rem" }}>
        {/* Admin Management Card */}
        <div className="card">
          <div style={{ fontWeight: 700, fontSize: "1rem", color: "#38bdf8", marginBottom: 12, display: "flex", alignItems: "center", gap: 8 }}>
            👑 Admin User Management
          </div>
          <p style={{ fontSize: "0.8rem", color: "var(--text-dim)", marginBottom: 14 }}>
            Authorized admins have unlimited Telegram bot commands and full system access.
          </p>

          <div style={{ display: "flex", gap: 8, marginBottom: 14 }}>
            <input
              type="email"
              className="input"
              placeholder="admin.email@gmail.com"
              value={newAdminEmail}
              onChange={e => setNewAdminEmail(e.target.value)}
              style={{ flex: 1, fontSize: "0.85rem" }}
            />
            <button className="btn btn-primary" onClick={handleAddAdmin} style={{ padding: "8px 16px", fontSize: "0.85rem" }}>
              + Add Admin
            </button>
          </div>
          {adminMsg && <div style={{ fontSize: "0.8rem", marginBottom: 10, fontWeight: 600 }}>{adminMsg}</div>}

          <div style={{ fontSize: "0.75rem", color: "var(--text-dim)", fontWeight: 700, textTransform: "uppercase", marginBottom: 6 }}>
            Current Admins ({Object.keys(admins).length})
          </div>
          <div style={{ maxHeight: 120, overflowY: "auto", background: "rgba(0,0,0,0.3)", borderRadius: 8, padding: 8 }}>
            {Object.values(admins).map((adm, idx) => (
              <div key={idx} style={{ display: "flex", justifyContent: "space-between", fontSize: "0.8rem", padding: "4px 0", borderBottom: "1px solid rgba(255,255,255,0.05)" }}>
                <span style={{ color: "#f8fafc" }}>{adm.email}</span>
                <span style={{ color: "#10b981", fontSize: "0.7rem", fontWeight: 600 }}>[ Active Admin ]</span>
              </div>
            ))}
          </div>
        </div>

        {/* ESP32 WiFi Provisioning Card */}
        <div className="card">
          <div style={{ fontWeight: 700, fontSize: "1rem", color: "#10b981", marginBottom: 12, display: "flex", alignItems: "center", gap: 8 }}>
            📶 ESP32 WiFi Configuration
          </div>
          <p style={{ fontSize: "0.8rem", color: "var(--text-dim)", marginBottom: 14 }}>
            Remotely update ESP32 network credentials over Firebase. The device will save to NVS & reconnect.
          </p>

          <div style={{ display: "flex", flexDirection: "column", gap: 8, marginBottom: 14 }}>
            <input
              type="text"
              className="input"
              placeholder="WiFi SSID (Network Name)"
              value={wifiSsid}
              onChange={e => setWifiSsid(e.target.value)}
              style={{ fontSize: "0.85rem" }}
            />
            <input
              type="password"
              className="input"
              placeholder="WiFi Password"
              value={wifiPass}
              onChange={e => setWifiPass(e.target.value)}
              style={{ fontSize: "0.85rem" }}
            />
          </div>

          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
            <button className="btn btn-primary" onClick={handleUpdateWifi} style={{ padding: "8px 16px", fontSize: "0.85rem" }}>
              📡 Apply New WiFi Settings
            </button>
            {wifiMsg && <span style={{ fontSize: "0.8rem", fontWeight: 600 }}>{wifiMsg}</span>}
          </div>
        </div>
      </div>

      {/* ── Main Tabbed Section: Body Overview / Camera Grid / Speaker Controls ── */}
      <div className="card" style={{ marginBottom: "1.5rem" }}>
        <div className="section-header" style={{ marginBottom: "1rem" }}>
          <div style={{ display: "flex", gap: 8, flex: 1, flexWrap: "wrap" }}>
            <button
              onClick={() => setHubTab("body")}
              style={{
                background: hubTab === "body" ? "var(--bg-card2)" : "none",
                border: "1px solid var(--border)", cursor: "pointer", padding: "0.4rem 1rem",
                borderRadius: 8, fontWeight: 700, fontSize: "0.88rem",
                color: hubTab === "body" ? "var(--blue)" : "var(--text-dim)",
              }}
            >
              <i className="fa-solid fa-robot"></i> SYS_CORE_BODY
            </button>
            <button
              onClick={() => setHubTab("cameras")}
              style={{
                background: hubTab === "cameras" ? "var(--bg-card2)" : "none",
                border: "1px solid var(--border)", cursor: "pointer", padding: "0.4rem 1rem",
                borderRadius: 8, fontWeight: 700, fontSize: "0.88rem",
                color: hubTab === "cameras" ? "var(--green)" : "var(--text-dim)",
              }}
            >
              <i className="fa-solid fa-camera-retro"></i> VISUAL_OPTICS
            </button>
            <button
              onClick={() => setHubTab("speakers")}
              style={{
                background: hubTab === "speakers" ? "var(--bg-card2)" : "none",
                border: "1px solid var(--border)", cursor: "pointer", padding: "0.4rem 1rem",
                borderRadius: 8, fontWeight: 700, fontSize: "0.88rem",
                color: hubTab === "speakers" ? "var(--yellow)" : "var(--text-dim)",
              }}
            >
              <i className="fa-solid fa-volume-high"></i> AUDIO_EMITTERS
            </button>
            <button
              onClick={() => setHubTab("permissions")}
              style={{
                background: hubTab === "permissions" ? "var(--bg-card2)" : "none",
                border: "1px solid var(--border)", cursor: "pointer", padding: "0.4rem 1rem",
                borderRadius: 8, fontWeight: 700, fontSize: "0.88rem",
                color: hubTab === "permissions" ? "var(--purple)" : "var(--text-dim)",
              }}
            >
              <i className="fa-solid fa-shield-halved"></i> NET_SEC_CONFIG ({networkDevices.length})
            </button>
            <button
              onClick={() => setHubTab("adb_mirror")}
              style={{
                background: hubTab === "adb_mirror" ? "var(--bg-card2)" : "none",
                border: "1px solid var(--border)", cursor: "pointer", padding: "0.4rem 1rem",
                borderRadius: 8, fontWeight: 700, fontSize: "0.88rem",
                color: hubTab === "adb_mirror" ? "#00E676" : "var(--text-dim)",
              }}
            >
              <i className="fa-solid fa-mobile-screen"></i> ADB_MIRROR
            </button>
            <button
              onClick={() => setHubTab("devices")}
              style={{
                background: hubTab === "devices" ? "var(--bg-card2)" : "none",
                border: "1px solid var(--border)", cursor: "pointer", padding: "0.4rem 1rem",
                borderRadius: 8, fontWeight: 700, fontSize: "0.88rem",
                color: hubTab === "devices" ? "#00d4ff" : "var(--text-dim)",
                position: "relative",
              }}
            >
              🌐 GLOBAL_NODES {Object.keys(connectedDevices).length > 0 && (
                <span style={{ background: "#00d4ff", color: "#000", borderRadius: 20, fontSize: "0.65rem", padding: "1px 6px", marginLeft: 4, fontWeight: 900 }}>
                  {Object.keys(connectedDevices).length}
                </span>
              )}
            </button>
          </div>

          <button
            className="btn btn-ghost"
            style={{ fontSize: "0.75rem", padding: "0.3rem 0.75rem" }}
            onClick={pollHub}
          >
            🔄 Refresh Hub
          </button>
        </div>

        {/* Tab 1: Body Perception Monitor */}
        {hubTab === "body" && (
          <div className="grid-2">
            <div style={{ background: "rgba(255,255,255,0.02)", padding: "1rem", borderRadius: 10, border: "1px solid var(--border)" }}>
              <h3 style={{ fontSize: "1rem", fontWeight: 700, marginBottom: "0.75rem", color: "var(--blue)" }}>
                👁️ Visual Perception (Cameras)
              </h3>
              {cameras.length > 0 ? (
                cameras.map(c => (
                  <div key={c.mac} style={{ display: "flex", justifyContent: "space-between", padding: "6px 0", borderBottom: "1px solid var(--border)", fontSize: "0.84rem" }}>
                    <span>{c.name || "Camera"} ({c.ip})</span>
                    <span style={{ color: c.online ? "var(--green)" : "var(--red)" }}>{c.online ? "● Active Eye" : "Offline"}</span>
                  </div>
                ))
              ) : (
                <p style={{ fontSize: "0.82rem", color: "var(--text-dim)" }}>No active camera eyes connected.</p>
              )}
            </div>

            <div style={{ background: "rgba(255,255,255,0.02)", padding: "1rem", borderRadius: 10, border: "1px solid var(--border)" }}>
              <h3 style={{ fontSize: "1rem", fontWeight: 700, marginBottom: "0.75rem", color: "var(--yellow)" }}>
                🗣️ Vocal Audio Organs (Speakers)
              </h3>
              {speakers.length > 0 ? (
                speakers.map(s => (
                  <div key={s.mac} style={{ display: "flex", justifyContent: "space-between", padding: "6px 0", borderBottom: "1px solid var(--border)", fontSize: "0.84rem" }}>
                    <span>{s.name || "Speaker"} {s.is_active && "⭐ Active"}</span>
                    <span style={{ color: s.online ? "var(--green)" : "var(--red)" }}>{s.online ? "● Ready" : "Offline"}</span>
                  </div>
                ))
              ) : (
                <p style={{ fontSize: "0.82rem", color: "var(--text-dim)" }}>No audio speaker nodes connected.</p>
              )}
            </div>
          </div>
        )}

        {/* Tab 2: Camera Grid */}
        {hubTab === "cameras" && (
          <>
            {/* Master Camera Activation Bar */}
            <div style={{ background: "rgba(0,230,118,0.06)", border: "1px solid rgba(0,230,118,0.2)", borderRadius: 10, padding: "0.88rem", marginBottom: "1rem", display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: 10 }}>
              <div>
                <div style={{ fontWeight: 700, fontSize: "0.88rem", color: "var(--green)" }}>
                  📡 Master Camera Activation Broadcast
                </div>
                <div style={{ fontSize: "0.74rem", color: "var(--text-dim)", marginTop: 2 }}>
                  Pushes permission popups to all laptops/mobiles on Wi-Fi and auto-connects IP cameras.
                </div>
              </div>
              <button className="btn btn-success" style={{ fontSize: "0.82rem" }} onClick={startAllCameras}>
                🎥 Start All Cameras on Wi-Fi
              </button>
            </div>

            {cameras.length === 0 ? (
              <div style={{ textAlign: "center", padding: "2.5rem 1rem", color: "var(--text-dim)" }}>
                <div style={{ fontSize: "3rem", marginBottom: "1rem" }}>📷</div>
                <div style={{ fontWeight: 700, marginBottom: "0.5rem" }}>
                  {hubOnline ? "No camera eyes registered" : "IoT Hub Offline"}
                </div>

                <p style={{ fontSize: "0.82rem", marginBottom: "1rem" }}>
                  Connect your phone camera via the Phone Bridge link to provide MEKA with visual sight.
                </p>
                {hubOnline && (
                  <a href={`${HUB_URL}/phone-bridge`} target="_blank" rel="noreferrer" className="btn btn-primary" style={{ textDecoration: "none" }}>
                    📱 Open Phone Bridge Camera
                  </a>
                )}
              </div>
            ) : (
              <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(280px, 1fr))", gap: "1rem" }}>
                {cameras.map(cam => (
                  <CameraCard key={cam.mac} cam={cam} />
                ))}
              </div>
            )}
          </>
        )}

        {/* Tab 3: Speaker Controls */}
        {hubTab === "speakers" && (
          <>
            {/* Targetted TTS Audio Broadcast Bar */}
            <div style={{ background: "rgba(0,180,255,0.06)", border: "1px solid rgba(0,180,255,0.2)", borderRadius: 10, padding: "0.88rem", marginBottom: "1rem" }}>
              <div style={{ fontWeight: 700, fontSize: "0.88rem", marginBottom: 6, color: "var(--blue)", display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                <span>📢 Text-to-Speech Broadcast</span>
                <select 
                  className="input" 
                  value={adminOutputMac} 
                  onChange={e => setAdminOutputMac(e.target.value)}
                  style={{ width: "250px", fontSize: "0.8rem", padding: "4px 8px" }}
                >
                  <option value="all">🔊 All Speakers</option>
                  {speakers.map(s => (
                    <option key={s.mac} value={s.mac}>
                      🔵 {s.name || s.hostname || s.ip}
                    </option>
                  ))}
                </select>
              </div>
              <div style={{ display: "flex", gap: 8 }}>
                <input
                  className="input"
                  value={ttsText}
                  onChange={e => setTtsText(e.target.value)}
                  placeholder={`Send voice message to ${adminOutputMac === 'all' ? 'ALL speakers' : 'selected speaker'}...`}
                  onKeyDown={e => e.key === "Enter" && sendTTS(ttsText)}
                  style={{ fontSize: "0.82rem", flex: 1 }}
                />
                <button className="btn btn-primary" onClick={() => sendTTS(ttsText)} disabled={!ttsText.trim()}>
                  📢 Send TTS
                </button>
              </div>
            </div>

            {speakers.length === 0 ? (
              <div style={{ textAlign: "center", padding: "3rem 1rem", color: "var(--text-dim)" }}>
                <div style={{ fontSize: "3rem", marginBottom: "1rem" }}>🔊</div>
                <div style={{ fontWeight: 700 }}>No speaker nodes registered</div>
              </div>
            ) : (
              <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(280px, 1fr))", gap: "1rem" }}>
                {speakers.map(spk => (
                  <SpeakerCard
                    key={spk.mac}
                    spk={spk}
                    isActive={spk.is_active}
                    onSelect={selectSpeaker}
                  />
                ))}
              </div>
            )}
          </>
        )}


        {/* Tab 4: Device Permissions Gate & Manager */}
        {hubTab === "permissions" && (
          <div>
            <p style={{ fontSize: "0.85rem", color: "var(--text-dim)", marginBottom: "1rem" }}>
              One-time permission gate for Wi-Fi & Hotspot devices. Devices must be granted permission before MEKA can access their Camera, Microphone, or Speaker.
            </p>
            {networkDevices.length === 0 ? (
              <div style={{ textAlign: "center", padding: "3rem 1rem", color: "var(--text-dim)" }}>
                <div style={{ fontSize: "3rem", marginBottom: "0.5rem" }}>🛡️</div>
                <div>No devices found on network scan</div>
              </div>
            ) : (
              <div style={{ display: "flex", flexDirection: "column", gap: "0.75rem" }}>
                {networkDevices.map(dev => {
                  const perm = dev.permission || "pending";
                  const permCls = perm === "granted" ? "tag-green" : perm === "denied" ? "tag-red" : "tag-yellow";
                  return (
                    <div
                      key={dev.mac}
                      style={{
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "space-between",
                        background: "rgba(255,255,255,0.02)",
                        padding: "0.88rem 1.25rem",
                        borderRadius: 10,
                        border: "1px solid var(--border)",
                        flexWrap: "wrap",
                        gap: 12,
                      }}
                    >
                      <div>
                        <div style={{ fontWeight: 700, fontSize: "0.92rem" }}>
                          {dev.friendly_name || dev.vendor || dev.device_type || "Wi-Fi Device"}
                        </div>
                        <div style={{ fontSize: "0.74rem", color: "var(--text-dim)", fontFamily: "JetBrains Mono", marginTop: 2 }}>
                          IP: {dev.ip} · MAC: {dev.mac}
                        </div>
                        <div style={{ fontSize: "0.7rem", color: "var(--text-dim)", marginTop: 2 }}>
                          Capabilities: {(dev.capabilities || []).join(", ") || "camera, speaker, mic"}
                        </div>
                      </div>

                      <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
                        <span className={`tag ${permCls}`} style={{ fontSize: "0.7rem" }}>
                          {perm.toUpperCase()}
                        </span>
                        <button
                          className="btn btn-primary"
                          style={{ fontSize: "0.75rem", padding: "0.4rem 0.75rem" }}
                          onClick={() => triggerDevicePrompt(dev.mac)}
                          title="Send popup modal to device screen requesting camera/mic/speaker permissions"
                        >
                          📲 Trigger Popup
                        </button>
                        {perm !== "granted" ? (
                          <button
                            className="btn btn-success"
                            style={{ fontSize: "0.75rem", padding: "0.4rem 0.75rem" }}
                            onClick={() => updateDevicePermission(dev.mac, "grant")}
                          >
                            🟢 Grant
                          </button>
                        ) : (
                          <button
                            className="btn btn-danger"
                            style={{ fontSize: "0.75rem", padding: "0.4rem 0.75rem" }}
                            onClick={() => updateDevicePermission(dev.mac, "deny")}
                          >
                            🚫 Revoke
                          </button>
                        )}
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        )}
        {/* Tab 5.5: Global Device Nodes — World-Wide Phone Bridge Control */}
        {hubTab === "devices" && (() => {
          const deviceList = Object.values(connectedDevices);
          const phoneBridgeUrl = IS_LOCAL ? `${HUB_URL}/phone-bridge` : `${window.location.origin}/phone-bridge`;
          return (
            <div>
              {/* Header bar */}
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", marginBottom: "1rem", flexWrap: "wrap", gap: 10 }}>
                <div>
                  <div style={{ fontWeight: 700, fontSize: "1.1rem", color: "#00d4ff" }}>🌐 Global Neural Nodes — Live Device Control</div>
                  <p style={{ fontSize: "0.78rem", color: "var(--text-dim)", marginTop: 2 }}>
                    Any device visiting <a href={phoneBridgeUrl} target="_blank" rel="noreferrer" style={{ color: "#00d4ff" }}>meka.starlight-coders.site/phone-bridge</a> appears here in real-time.
                  </p>
                </div>
                <div style={{ display: "flex", gap: 8 }}>
                  <a href={phoneBridgeUrl} target="_blank" rel="noreferrer" className="btn btn-primary" style={{ fontSize: "0.78rem", textDecoration: "none" }}>
                    📱 Open Phone Bridge
                  </a>
                </div>
              </div>

              {deviceList.length === 0 ? (
                <div style={{ textAlign: "center", padding: "4rem 1rem", color: "var(--text-dim)" }}>
                  <div style={{ fontSize: "4rem", marginBottom: "1rem" }}>🌐</div>
                  <div style={{ fontWeight: 700, fontSize: "1rem", marginBottom: "0.5rem", color: "#00d4ff" }}>NO GLOBAL NODES ONLINE</div>
                  <p style={{ fontSize: "0.84rem", marginBottom: "1.5rem", maxWidth: 360, margin: "0 auto 1.5rem" }}>
                    Share the Phone Bridge URL with any device on Earth. Once they open it and grant access, they will appear here instantly.
                  </p>
                  <div style={{ fontFamily: "monospace", fontSize: "0.9rem", background: "rgba(0,212,255,0.08)", border: "1px solid rgba(0,212,255,0.2)", borderRadius: 10, padding: "10px 20px", display: "inline-block", color: "#00d4ff" }}>
                    meka.starlight-coders.site/phone-bridge
                  </div>
                </div>
              ) : (
                <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(320px, 1fr))", gap: "1rem" }}>
                  {deviceList.map((dev) => {
                    const ip = dev.ip;
                    const camUrl = deviceFrames[ip];
                    const screenUrl = deviceScreens[ip];
                    const isSelected = selectedDevice === ip;
                    const [localTts, setLocalTts] = [deviceTts, setDeviceTts]; // simplified per-device TTS
                    return (
                      <div key={ip} className="card" style={{
                        padding: "1rem",
                        borderColor: isSelected ? "#00d4ff" : undefined,
                        boxShadow: isSelected ? "0 0 20px rgba(0,212,255,0.25)" : undefined,
                      }}
                        onClick={() => setSelectedDevice(isSelected ? null : ip)}
                      >
                        {/* Device Header */}
                        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", marginBottom: "0.75rem" }}>
                          <div>
                            <div style={{ fontWeight: 700, fontSize: "0.88rem", color: "#00d4ff" }}>🌐 {ip}</div>
                            <div style={{ fontSize: "0.7rem", color: "var(--text-dim)", fontFamily: "monospace" }}>
                              {dev.ua?.substring(0, 45) || "Unknown Device"}
                            </div>
                          </div>
                          <span className="badge badge-success" style={{ fontSize: "0.65rem" }}>● LIVE</span>
                        </div>

                        {/* Capabilities chips */}
                        <div style={{ display: "flex", gap: 5, flexWrap: "wrap", marginBottom: "0.75rem" }}>
                          {dev.caps?.camera    && <span style={{ background: "rgba(0,212,255,0.1)", border: "1px solid rgba(0,212,255,0.3)", color: "#00d4ff", borderRadius: 20, padding: "2px 8px", fontSize: "0.7rem" }}>📷 Camera</span>}
                          {dev.caps?.microphone && <span style={{ background: "rgba(0,255,136,0.08)", border: "1px solid rgba(0,255,136,0.3)", color: "#00ff88", borderRadius: 20, padding: "2px 8px", fontSize: "0.7rem" }}>🎤 Mic</span>}
                          {dev.caps?.screen    && <span style={{ background: "rgba(124,77,255,0.1)", border: "1px solid rgba(124,77,255,0.3)", color: "#bb88ff", borderRadius: 20, padding: "2px 8px", fontSize: "0.7rem" }}>🖥️ Screen</span>}
                          {dev.caps?.speaker   && <span style={{ background: "rgba(255,193,7,0.08)", border: "1px solid rgba(255,193,7,0.3)", color: "#ffc107", borderRadius: 20, padding: "2px 8px", fontSize: "0.7rem" }}>🔊 Speaker</span>}
                          {(dev.cameras?.length > 0) && <span style={{ background: "rgba(0,212,255,0.06)", border: "1px solid rgba(0,212,255,0.2)", color: "var(--text-dim)", borderRadius: 20, padding: "2px 8px", fontSize: "0.7rem" }}>{dev.cameras.length} cam{dev.cameras.length > 1 ? "s" : ""}</span>}
                        </div>

                        {/* Camera live view */}
                        <div style={{ background: "#000", borderRadius: 10, overflow: "hidden", aspectRatio: "16/9", marginBottom: "0.75rem", border: "1px solid rgba(0,212,255,0.15)", position: "relative" }}>
                          {camUrl ? (
                            <img src={camUrl} alt="Camera" style={{ width: "100%", height: "100%", objectFit: "cover" }} />
                          ) : (
                            <div style={{ display: "flex", alignItems: "center", justifyContent: "center", height: "100%", color: "var(--text-dim)", fontSize: "0.8rem", flexDirection: "column", gap: 6 }}>
                              <span style={{ fontSize: "2rem" }}>📷</span>
                              <span>AWAITING FEED...</span>
                            </div>
                          )}
                          {camUrl && <div style={{ position: "absolute", top: 6, left: 6, background: "rgba(0,0,0,0.6)", color: "#ff4444", fontSize: "0.6rem", padding: "2px 6px", borderRadius: 4, fontFamily: "monospace" }}>● LIVE CAMERA</div>}
                        </div>

                        {/* Screen share view */}
                        {screenUrl && (
                          <div style={{ background: "#000", borderRadius: 10, overflow: "hidden", marginBottom: "0.75rem", border: "1px solid rgba(124,77,255,0.3)" }}>
                            <div style={{ fontSize: "0.68rem", color: "#bb88ff", padding: "4px 8px", background: "rgba(124,77,255,0.1)", display: "flex", alignItems: "center", gap: 5 }}>
                              <span style={{ width: 6, height: 6, borderRadius: "50%", background: "#bb88ff", display: "inline-block" }}></span>
                              LIVE SCREEN SHARE
                            </div>
                            <img src={screenUrl} alt="Screen" style={{ width: "100%", objectFit: "contain" }} />
                          </div>
                        )}

                        {/* Controls */}
                        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 6, marginBottom: 8 }}>
                          <button className="btn btn-ghost" style={{ fontSize: "0.75rem", padding: "0.4rem" }}
                            onClick={(e) => { e.stopPropagation(); sendDeviceCommand(ip, "camera_flip"); }}>
                            🔄 Flip Cam
                          </button>
                          <button className="btn btn-ghost" style={{ fontSize: "0.75rem", padding: "0.4rem" }}
                            onClick={(e) => { e.stopPropagation(); sendDeviceCommand(ip, screenUrl ? "screen_stop" : "screen_start"); }}>
                            {screenUrl ? "⏹️ Stop Screen" : "🖥️ Start Screen"}
                          </button>
                        </div>

                        {/* Camera switch */}
                        {dev.cameras?.length > 1 && (
                          <select
                            className="input"
                            style={{ fontSize: "0.78rem", marginBottom: 8, width: "100%" }}
                            onClick={e => e.stopPropagation()}
                            onChange={e => sendDeviceCommand(ip, "camera_switch", { device_id: e.target.value })}
                          >
                            {dev.cameras.map((c, i) => <option key={c.id} value={c.id}>{c.label || "Camera " + (i+1)}</option>)}
                          </select>
                        )}

                        {/* TTS */}
                        <div style={{ display: "flex", gap: 6 }} onClick={e => e.stopPropagation()}>
                          <input className="input" placeholder="Speak through device speaker..." style={{ flex: 1, fontSize: "0.78rem" }}
                            onKeyDown={e => { if (e.key === "Enter") { sendDeviceTTS(ip, e.target.value); e.target.value = ""; } }}
                          />
                          <button className="btn btn-primary" style={{ fontSize: "0.75rem", padding: "0.4rem 0.7rem" }}
                            onClick={(e) => { const input = e.target.previousSibling; sendDeviceTTS(ip, input.value); input.value = ""; }}>
                            📢
                          </button>
                        </div>

                        {/* Disconnect */}
                        <button className="btn btn-danger" style={{ fontSize: "0.75rem", marginTop: 8, width: "100%" }}
                          onClick={(e) => { e.stopPropagation(); sendDeviceCommand(ip, "disconnect"); }}>
                          ⏹️ Disconnect Node
                        </button>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          );
        })()}

        {/* Tab 6: ADB Wireless Mirror & Remote Control */}
        {hubTab === "adb_mirror" && (

          <div>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "1rem" }}>
              <div>
                <div style={{ fontWeight: 700, fontSize: "1.1rem" }}>📱 ADB Wireless Remote & Screen Mirror</div>
                <p style={{ fontSize: "0.78rem", color: "var(--text-dim)", marginTop: 2 }}>
                  Full control over connected Android devices via Wireless Debugging (scrcpy, unlock, shell).
                </p>
              </div>
              <button className="btn btn-ghost" onClick={pollHub} style={{ fontSize: "0.78rem" }}>
                🔄 Refresh Devices
              </button>
            </div>

            <div className="grid-2" style={{ gap: "1rem" }}>
              {/* Left Column: Device Control */}
              <div className="card">
                <div style={{ fontWeight: 700, fontSize: "0.9rem", color: "#00E676", marginBottom: 10 }}>
                  ⚡ Connected ADB Devices ({networkDevices.filter(d => d.device_type === "phone").length})
                </div>

                <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
                  <input
                    type="text"
                    className="input"
                    placeholder="Unlock PIN (optional for screen unlock)"
                    id="adbUnlockPinInput"
                    style={{ fontSize: "0.8rem" }}
                  />
                  {networkDevices.filter(d => d.device_type === "phone" || d.ip).map((dev, i) => (
                    <div key={i} style={{ padding: 10, borderRadius: 8, background: "rgba(255,255,255,0.03)", border: "1px solid var(--border)" }}>
                      <div style={{ fontWeight: 700, fontSize: "0.85rem" }}>{dev.friendly_name || dev.vendor || "Android Device"}</div>
                      <div style={{ fontSize: "0.72rem", color: "var(--text-dim)", fontFamily: "monospace" }}>{dev.ip}</div>
                      
                      <div style={{ display: "flex", gap: 6, marginTop: 8, flexWrap: "wrap" }}>
                        <button
                          className="btn btn-primary"
                          style={{ fontSize: "0.7rem", padding: "3px 8px" }}
                          onClick={async () => {
                            const pin = document.getElementById("adbUnlockPinInput")?.value;
                            setFeedback("🔓 Unlocking device screen...");
                            try {
                              const r = await hubFetch(`/api/adb/${encodeURIComponent(dev.ip + ":5555")}/unlock`, {
                                method: "POST",
                                headers: { "Content-Type": "application/json" },
                                body: JSON.stringify({ pin })
                              });
                              const j = await r.json();
                              setFeedback(r.ok ? "✅ Device Unlocked!" : `❌ ${j.error}`);
                            } catch { setFeedback("❌ Failed to send unlock"); }
                            setTimeout(() => setFeedback(""), 3000);
                          }}
                        >
                          🔓 Unlock Screen
                        </button>
                        
                        <button
                          className="btn btn-secondary"
                          style={{ fontSize: "0.7rem", padding: "3px 8px" }}
                          onClick={async () => {
                            setFeedback("🖥️ Starting scrcpy desktop mirror...");
                            try {
                              const r = await hubFetch(`/api/adb/${encodeURIComponent(dev.ip + ":5555")}/mirror/start`, { method: "POST" });
                              const j = await r.json();
                              setFeedback(r.ok ? "✅ scrcpy mirror window opened on Hub!" : `❌ ${j.error}`);
                            } catch { setFeedback("❌ Failed to start scrcpy"); }
                            setTimeout(() => setFeedback(""), 3000);
                          }}
                        >
                          🖥️ Launch scrcpy
                        </button>
                      </div>
                    </div>
                  ))}

                  {networkDevices.filter(d => d.device_type === "phone" || d.ip).length === 0 && (
                    <div style={{ textAlign: "center", padding: 20, color: "var(--text-dim)", fontSize: "0.82rem" }}>
                      No Android ADB devices detected. Open <b>/phone-bridge</b> on your phone and tap <b>Pair Wireless ADB</b>.
                    </div>
                  )}
                </div>
              </div>

              {/* Right Column: Web Screen Stream */}
              <div className="card" style={{ textAlign: "center" }}>
                <div style={{ fontWeight: 700, fontSize: "0.9rem", color: "var(--blue)", marginBottom: 10 }}>
                  📱 Web Screen Live Feed
                </div>
                <div style={{ position: "relative", minHeight: 240, background: "#000", borderRadius: 12, display: "flex", alignItems: "center", justifyCenter: "center", border: "1px solid var(--border)", overflow: "hidden" }}>
                  <iframe
                    src={`${HUB_URL}/camera-viewer`}
                    style={{ width: "100%", height: 320, border: "none" }}
                    title="Live Phone Bridge Stream"
                  />
                </div>
                <div style={{ fontSize: "0.72rem", color: "var(--text-dim)", marginTop: 8 }}>
                  Live webcam / camera feed streamed via Phone Bridge WebSockets
                </div>
              </div>
            </div>
          </div>
        )}
      </div>


      {/* Command Console + Servo & Hardware Controls */}
      <div className="grid-2" style={{ marginBottom: "1.5rem" }}>
        {/* Command Console */}
        <div className="card">
          <div className="section-header">
            <span style={{ fontSize: "1.3rem" }}>⌨️</span>
            <span className="section-title">MEKA Mind Command Input</span>
          </div>
          <div style={{ display: "flex", gap: 8, marginBottom: "0.75rem" }}>
            <input
              className="input"
              value={cmdText}
              onChange={e => setCmdText(e.target.value)}
              placeholder='e.g. "What is your body temperature?" or "Look left"'
              onKeyDown={e => e.key === "Enter" && cmdText && sendCommand(cmdText)}
            />
            <button
              className="btn btn-primary"
              onClick={() => cmdText && sendCommand(cmdText)}
              disabled={sending || !cmdText}
            >
              Send
            </button>
          </div>
          {feedback && (
            <p style={{ fontSize: "0.83rem", color: feedback.startsWith("✅") || feedback.startsWith("📢") ? "var(--green)" : feedback.startsWith("❌") ? "var(--red)" : "var(--text-dim)" }}>
              {feedback}
            </p>
          )}
          <div style={{ marginTop: "0.75rem" }}>
            <div className="stat-label" style={{ marginBottom: 8 }}>LCD Forehead Display Text</div>
            <div className="lcd-mockup" style={{ whiteSpace: "pre" }}>
              {meka.lcd_text ? meka.lcd_text.substring(0, 32) : "MEKA AI Active  [O_O]"}
            </div>
          </div>
        </div>

        {/* Hardware & Servo Body Axis Controls */}
        <div className="card">
          <div className="section-header">
            <span style={{ fontSize: "1.3rem" }}>🎛️</span>
            <span className="section-title">Servo Neck & Hardware Controls</span>
          </div>

          {/* Status LED Aura */}
          <div style={{ marginBottom: "1.25rem" }}>
            <div className="stat-label" style={{ marginBottom: 10 }}>Nervous Aura Status</div>
            <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
              {[
                { s: "listening",  label: "🔵 Listening",  cls: "tag-blue"   },
                { s: "processing", label: "🟡 Processing", cls: "tag-yellow" },
                { s: "success",    label: "🟢 Success",    cls: "tag-green"  },
                { s: "error",      label: "🔴 Error",      cls: "tag-red"    },
                { s: "idle",       label: "⚫ Idle",       cls: ""           },
              ].map(({ s, label, cls }) => (
                <button key={s} className={`tag ${cls}`} style={{ cursor: "pointer", border: "1px solid currentColor", background: "transparent" }}
                  onClick={() => setStatus(s)}>{label}</button>
              ))}
            </div>
          </div>

          {/* Servo Neck Orientation */}
          <div style={{ marginBottom: "1.25rem" }}>
            <div className="stat-label" style={{ marginBottom: 8 }}>
              Servo Neck Angle — <strong style={{ color: "var(--text)" }}>{servoVal}°</strong>
            </div>
            <input type="range" min={0} max={180} value={servoVal}
              onChange={e => setServoVal(Number(e.target.value))} />
            <div style={{ display: "flex", gap: 8, marginTop: 8 }}>
              <button className="btn btn-ghost" style={{ flex: 1 }} onClick={() => sendServo(0)}>0° (Left)</button>
              <button className="btn btn-ghost" style={{ flex: 1 }} onClick={() => sendServo(90)}>90° (Center)</button>
              <button className="btn btn-ghost" style={{ flex: 1 }} onClick={() => sendServo(180)}>180° (Right)</button>
            </div>
          </div>

          {/* Buzzer Sound */}
          <div>
            <div className="stat-label" style={{ marginBottom: 8 }}>Reflex Buzzer Sound</div>
            <div style={{ display: "flex", gap: 8 }}>
              {[200, 500, 1000].map(ms => (
                <button key={ms} className="btn btn-ghost" onClick={() => sendBuzzer(ms)}>
                  🔔 {ms}ms
                </button>
              ))}
            </div>
          </div>
        </div>
      </div>

      {/* History Log */}
      <div className="card">
        <div className="section-header">
          <span style={{ fontSize: "1.3rem" }}>📋</span>
          <span className="section-title">Command History</span>
          <span className="section-sub">Live Firebase Telemetry</span>
        </div>
        <CommandLog />
      </div>
    </div>
  );
}
