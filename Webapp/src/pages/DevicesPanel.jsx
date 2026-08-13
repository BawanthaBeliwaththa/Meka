// src/pages/DevicesPanel.jsx — Connected Device Management, ADB & ESP32 Nodes
import { useState, useEffect, useCallback } from "react";

const HUB_URL = import.meta.env.VITE_HUB_URL || "http://localhost:5000";

function hubFetch(path, opts = {}) {
  return fetch(`${HUB_URL}${path}`, { ...opts, mode: "cors" }).catch(() => null);
}

// ── ESP32 Node Card ────────────────────────────────────────────────────────
const LED_COLORS = [
  { key: "blue",   color: "#00D4FF", label: "B" },
  { key: "yellow", color: "#FFD600", label: "Y" },
  { key: "green",  color: "#00E676", label: "G" },
  { key: "red",    color: "#FF1744", label: "R" },
];

function Esp32NodeCard({ node }) {
  const [leds, setLeds] = useState({ blue: false, yellow: false, green: false, red: false });
  const [buzzing, setBuzzing] = useState(false);
  const [cmdStatus, setCmdStatus] = useState("");
  const mac = node.mac || "";
  const tel = node.telemetry || {};
  const online = node.online !== false;

  const sendCmd = async (action, extra = {}) => {
    const r = await hubFetch(`/api/esp32/${encodeURIComponent(mac)}/command`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action, ...extra }),
    });
    const ok = r?.ok;
    setCmdStatus(ok ? "✓ Sent" : "✗ Failed");
    setTimeout(() => setCmdStatus(""), 2000);
    return ok;
  };

  const toggleLed = async (key) => {
    const newState = !leds[key];
    setLeds((l) => ({ ...l, [key]: newState }));
    await sendCmd("led", { color: key, state: newState ? "on" : "off" });
  };

  const doBuzzer = async () => {
    setBuzzing(true);
    await sendCmd("buzzer", { pattern: "beep" });
    setTimeout(() => setBuzzing(false), 600);
  };

  return (
    <div
      className="device-card"
      id={`esp32-node-${mac}`}
      style={{
        borderColor: online ? "rgba(0,230,118,0.35)" : "rgba(255,23,68,0.25)",
        background: "linear-gradient(135deg, rgba(0,230,118,0.04) 0%, rgba(8,12,30,0.95) 100%)",
      }}
    >
      <div className="device-card-header">
        <span style={{ fontSize: "1.4rem" }}>🤖</span>
        <div className="device-card-info">
          <div className="device-name">{node.name || `MEKA Node (${mac.slice(-5)})`}</div>
          <div className="device-ip">
            {node.node_id && <span style={{ color: "#00D4FF", marginRight: 8 }}>{node.node_id}</span>}
            {node.ip}
          </div>
          <div style={{ display: "flex", gap: 6, alignItems: "center", marginTop: 4 }}>
            <span
              style={{
                width: 7, height: 7, borderRadius: "50%",
                background: online ? "#00E676" : "#FF1744",
                display: "inline-block",
                boxShadow: online ? "0 0 8px #00E676" : "none",
              }}
            />
            <span style={{ fontSize: "0.65rem", color: online ? "#00E676" : "#FF1744", letterSpacing: 2, fontFamily: "Orbitron" }}>
              {online ? "ONLINE" : "OFFLINE"}
            </span>
            {node.firmware && (
              <span style={{ fontSize: "0.6rem", color: "#ffffff30", marginLeft: 6 }}>fw {node.firmware}</span>
            )}
          </div>
        </div>
      </div>

      {/* Telemetry */}
      {(tel.temp !== undefined || tel.humidity !== undefined) && (
        <div style={{ display: "flex", gap: 16, margin: "10px 0", padding: "8px 12px",
          background: "rgba(0,212,255,0.05)", borderRadius: 8, border: "1px solid rgba(0,212,255,0.1)" }}>
          {tel.temp !== undefined && (
            <div style={{ textAlign: "center" }}>
              <div style={{ fontSize: "1.1rem", color: "#00D4FF", fontFamily: "Orbitron", fontWeight: 700 }}>
                {Number(tel.temp).toFixed(1)}°C
              </div>
              <div style={{ fontSize: "0.6rem", color: "#ffffff40", letterSpacing: 2 }}>TEMP</div>
            </div>
          )}
          {tel.humidity !== undefined && (
            <div style={{ textAlign: "center" }}>
              <div style={{ fontSize: "1.1rem", color: "#7C4DFF", fontFamily: "Orbitron", fontWeight: 700 }}>
                {Number(tel.humidity).toFixed(0)}%
              </div>
              <div style={{ fontSize: "0.6rem", color: "#ffffff40", letterSpacing: 2 }}>HUMIDITY</div>
            </div>
          )}
          {tel.ldr !== undefined && (
            <div style={{ textAlign: "center" }}>
              <div style={{ fontSize: "1.1rem", color: "#FFD600", fontFamily: "Orbitron", fontWeight: 700 }}>
                {tel.ldr}
              </div>
              <div style={{ fontSize: "0.6rem", color: "#ffffff40", letterSpacing: 2 }}>LDR</div>
            </div>
          )}
        </div>
      )}

      {/* LED Controls */}
      <div style={{ display: "flex", gap: 8, marginBottom: 8, alignItems: "center" }}>
        <span style={{ fontSize: "0.6rem", color: "#ffffff30", fontFamily: "Orbitron", letterSpacing: 2, minWidth: 24 }}>LED</span>
        {LED_COLORS.map(({ key, color, label }) => (
          <button
            key={key}
            id={`led-${mac}-${key}`}
            onClick={() => toggleLed(key)}
            disabled={!online}
            title={`Toggle ${key} LED`}
            style={{
              width: 32, height: 32, borderRadius: "50%",
              background: leds[key] ? `${color}30` : "transparent",
              border: `1.5px solid ${leds[key] ? color : color + "50"}`,
              color: leds[key] ? color : color + "70",
              cursor: online ? "pointer" : "not-allowed",
              fontSize: "0.65rem", fontWeight: 700, fontFamily: "Orbitron",
              boxShadow: leds[key] ? `0 0 10px ${color}80` : "none",
              transition: "all 0.2s",
            }}
          >
            {label}
          </button>
        ))}
        <button
          id={`buzzer-${mac}`}
          onClick={doBuzzer}
          disabled={!online || buzzing}
          title="Beep buzzer"
          style={{
            padding: "4px 10px", borderRadius: 6,
            background: "rgba(124,77,255,0.1)",
            border: "1px solid rgba(124,77,255,0.4)",
            color: "#7C4DFF", cursor: online ? "pointer" : "not-allowed",
            fontSize: "0.6rem", fontFamily: "Orbitron", letterSpacing: 1,
          }}
        >
          {buzzing ? "🔔" : "🔔 BEEP"}
        </button>
        {cmdStatus && (
          <span style={{
            fontSize: "0.6rem", color: cmdStatus.startsWith("✓") ? "#00E676" : "#FF1744",
            fontFamily: "Orbitron", letterSpacing: 1, marginLeft: "auto",
          }}>{cmdStatus}</span>
        )}
      </div>
    </div>
  );
}

// ── Device Type Icons ──────────────────────────────────────────────────
const DeviceIcon = ({ type }) => {
  const icons = {
    android: "📱", camera: "📷", speaker: "🔊", computer: "💻",
    phone_bridge: "📡", bluetooth: "🔵", router: "📶", unknown: "⬡",
  };
  return <span style={{ fontSize: "1.4rem" }}>{icons[type] || icons.unknown}</span>;
};

// ── ADB Terminal ───────────────────────────────────────────────────────
function AdbTerminal({ serial, onClose }) {
  const [cmd, setCmd] = useState("");
  const [log, setLog] = useState([
    { type: "sys", text: `> ADB SHELL CONNECTED: ${serial}` },
    { type: "sys", text: "> Type a shell command below. e.g: 'getprop ro.product.model'" },
  ]);
  const [running, setRunning] = useState(false);

  const runCmd = async () => {
    if (!cmd.trim() || running) return;
    const c = cmd.trim();
    setLog((l) => [...l, { type: "input", text: `$ ${c}` }]);
    setCmd("");
    setRunning(true);
    try {
      const r = await hubFetch(`/api/adb/${serial}/shell`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ command: c }),
      });
      if (r?.ok) {
        const j = await r.json();
        setLog((l) => [...l, { type: "output", text: j.output || "(no output)" }]);
      } else {
        setLog((l) => [...l, { type: "error", text: "ERR: Hub returned an error or is offline." }]);
      }
    } catch {
      setLog((l) => [...l, { type: "error", text: "ERR: Could not reach IoT Hub." }]);
    }
    setRunning(false);
  };

  return (
    <div className="adb-terminal-overlay" onClick={(e) => e.target === e.currentTarget && onClose()}>
      <div className="adb-terminal">
        <div className="adb-terminal-header">
          <span>ADB SHELL — {serial}</span>
          <button onClick={onClose} className="adb-close-btn" id="adb-close">✕</button>
        </div>
        <div className="adb-terminal-log">
          {log.map((l, i) => (
            <div key={i} className={`adb-log-line adb-log-${l.type}`}>{l.text}</div>
          ))}
          {running && <div className="adb-log-sys adb-blink">{">"} EXECUTING...</div>}
        </div>
        <div className="adb-terminal-input">
          <span className="adb-prompt">$</span>
          <input
            id="adb-shell-input"
            value={cmd}
            onChange={(e) => setCmd(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && runCmd()}
            placeholder="enter adb shell command..."
            className="adb-input-field"
            disabled={running}
            autoFocus
          />
          <button onClick={runCmd} disabled={running} className="adb-run-btn" id="adb-run">RUN</button>
        </div>
      </div>
    </div>
  );
}

// ── Device Card ────────────────────────────────────────────────────────
function DeviceCard({ device, onUnlock, onScreenshot, onPermit, onRevoke, onShell }) {
  const [unlocking, setUnlocking] = useState(false);
  const [screenshotting, setScreenshotting] = useState(false);
  const [snap, setSnap] = useState(null);
  const [msg, setMsg] = useState("");

  const showMsg = (m, delay = 3000) => { setMsg(m); setTimeout(() => setMsg(""), delay); };

  const handleUnlock = async () => {
    setUnlocking(true);
    showMsg("🔓 Sending unlock command...", 8000);
    const ok = await onUnlock(device.serial || device.mac);
    showMsg(ok ? "✅ Device unlocked!" : "❌ Unlock failed. Check ADB connection.");
    setUnlocking(false);
  };

  const handleScreenshot = async () => {
    setScreenshotting(true);
    showMsg("📸 Taking screenshot...", 5000);
    const url = await onScreenshot(device.serial || device.mac);
    if (url) { setSnap(url); showMsg("✅ Screenshot captured!"); }
    else showMsg("❌ Screenshot failed.");
    setScreenshotting(false);
  };

  const isAndroid = device.device_type === "android" || device.adb_connected;
  const isOnline = device.online !== false;

  return (
    <div className="device-card" style={{ borderColor: isOnline ? "rgba(0,240,255,0.25)" : "rgba(255,0,85,0.25)" }}>
      <div className="device-card-header">
        <DeviceIcon type={device.device_type || (device.adb_connected ? "android" : "unknown")} />
        <div className="device-card-info">
          <div className="device-name">{device.friendly_name || device.name || device.vendor || "Unknown Device"}</div>
          <div className="device-ip">
            {device.ip || device.serial || device.mac || "–"}
            {device.adb_connected && <span className="device-tag adb-tag">ADB</span>}
            {device.bluetooth && <span className="device-tag bt-tag">BT</span>}
          </div>
        </div>
        <span className={`device-status-badge ${isOnline ? "online" : "offline"}`}>
          {isOnline ? "● ONLINE" : "○ OFFLINE"}
        </span>
      </div>

      {/* Screenshot preview */}
      {snap && (
        <div className="device-screenshot">
          <img src={snap} alt="Device screenshot" />
          <button onClick={() => setSnap(null)} className="snap-close" id={`snap-close-${device.mac}`}>✕</button>
        </div>
      )}

      {msg && <div className="device-msg">{msg}</div>}

      <div className="device-actions">
        {device.permission !== "granted" && (
          <button className="dev-btn dev-btn-permit" onClick={() => onPermit(device.mac)} id={`permit-${device.mac}`}>
            🔑 PERMIT
          </button>
        )}
        {device.permission === "granted" && (
          <button className="dev-btn dev-btn-revoke" onClick={() => onRevoke(device.mac)} id={`revoke-${device.mac}`}>
            🚫 REVOKE
          </button>
        )}
        {isAndroid && isOnline && (
          <>
            <button className="dev-btn dev-btn-unlock" onClick={handleUnlock} disabled={unlocking} id={`unlock-${device.serial || device.mac}`}>
              {unlocking ? "⏳ UNLOCKING..." : "🔓 UNLOCK"}
            </button>
            <button className="dev-btn dev-btn-screenshot" onClick={handleScreenshot} disabled={screenshotting} id={`screenshot-${device.serial || device.mac}`}>
              {screenshotting ? "⏳..." : "📸 SCREENSHOT"}
            </button>
            <button className="dev-btn dev-btn-shell" onClick={() => onShell(device.serial || device.mac)} id={`shell-${device.serial || device.mac}`}>
              💻 ADB SHELL
            </button>
          </>
        )}
      </div>
    </div>
  );
}

// ── Main Panel ─────────────────────────────────────────────────────────
export default function DevicesPanel() {
  const [devices, setDevices] = useState([]);
  const [adbDevices, setAdbDevices] = useState([]);
  const [btDevices, setBtDevices] = useState([]);
  const [esp32Nodes, setEsp32Nodes] = useState([]);
  const [scanning, setScanning] = useState(false);
  const [btScanning, setBtScanning] = useState(false);
  const [shellTarget, setShellTarget] = useState(null);
  const [tab, setTab] = useState("network"); // network | adb | bluetooth | esp32
  const [hubOnline, setHubOnline] = useState(false);

  const loadNetworkDevices = useCallback(async () => {
    const r = await hubFetch("/api/devices?online=true");
    if (r?.ok) {
      const j = await r.json();
      setDevices(j.devices || []);
      setHubOnline(true);
    } else {
      setHubOnline(false);
    }
  }, []);

  const loadAdbDevices = useCallback(async () => {
    const r = await hubFetch("/api/adb/devices");
    if (r?.ok) {
      const j = await r.json();
      setAdbDevices(j.devices || []);
    }
  }, []);

  const loadBtDevices = useCallback(async () => {
    const r = await hubFetch("/api/bluetooth/devices");
    if (r?.ok) {
      const j = await r.json();
      setBtDevices(j.devices || []);
    }
  }, []);

  const loadEsp32Nodes = useCallback(async () => {
    const r = await hubFetch("/api/esp32/nodes");
    if (r?.ok) {
      const j = await r.json();
      setEsp32Nodes(j.nodes || []);
    }
  }, []);

  useEffect(() => {
    loadNetworkDevices();
    loadAdbDevices();
    loadBtDevices();
    loadEsp32Nodes();
    const t = setInterval(() => { loadNetworkDevices(); loadAdbDevices(); loadEsp32Nodes(); }, 10000);
    return () => clearInterval(t);
  }, [loadNetworkDevices, loadAdbDevices, loadBtDevices, loadEsp32Nodes]);

  const handleScan = async () => {
    setScanning(true);
    await hubFetch("/api/devices/scan", { method: "POST" });
    setTimeout(() => { loadNetworkDevices(); setScanning(false); }, 3000);
  };

  const handleBtScan = async () => {
    setBtScanning(true);
    const r = await hubFetch("/api/bluetooth/scan");
    if (r?.ok) { const j = await r.json(); setBtDevices(j.devices || []); }
    setBtScanning(false);
  };

  const handleUnlock = async (serialOrMac) => {
    const r = await hubFetch(`/api/adb/${encodeURIComponent(serialOrMac)}/unlock`, { method: "POST" });
    return r?.ok;
  };

  const handleScreenshot = async (serialOrMac) => {
    const r = await hubFetch(`/api/adb/${encodeURIComponent(serialOrMac)}/screenshot`);
    if (r?.ok) {
      const blob = await r.blob();
      return URL.createObjectURL(blob);
    }
    return null;
  };

  const handlePermit = async (mac) => {
    await hubFetch("/api/permissions/grant", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ mac }),
    });
    loadNetworkDevices();
  };

  const handleRevoke = async (mac) => {
    await hubFetch("/api/permissions/deny", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ mac }),
    });
    loadNetworkDevices();
  };

  const _handleBtConnect = async (mac) => {
    await hubFetch("/api/bluetooth/connect", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ mac }) });
    loadBtDevices();
  };

  // For bluetooth tab, merge both standard btDevices and any network devices detected as bt
  const displayDevices = tab === "network" 
    ? devices 
    : tab === "adb" 
      ? adbDevices 
      : btDevices;

  return (
    <div className="panel-content page" id="devices-panel">
      {/* Header */}
      <div className="panel-header">
        <div>
          <div className="panel-title">DEVICE MATRIX</div>
          <div className="panel-subtitle">Connected · Controlled · Secured</div>
        </div>
        <div style={{ display: "flex", gap: 10, alignItems: "center" }}>
          <span className={`hub-status-badge ${hubOnline ? "online" : "offline"}`}>
            {hubOnline ? "● HUB LIVE" : "○ HUB OFFLINE"}
          </span>
          <button id="scan-network-btn" className="btn" onClick={handleScan} disabled={scanning}>
            {scanning ? "⏳ SCANNING..." : "⊕ SCAN NETWORK"}
          </button>
        </div>
      </div>

      {/* Stats row */}
      <div className="devices-stats-row">
        <div className="stat-chip" style={{ borderColor: "rgba(0,240,255,0.3)" }}>
          <span className="stat-chip-num" style={{ color: "var(--cyan)" }}>{devices.length}</span>
          <span className="stat-chip-label">NETWORK</span>
        </div>
        <div className="stat-chip" style={{ borderColor: "rgba(0,255,102,0.3)" }}>
          <span className="stat-chip-num" style={{ color: "var(--green)" }}>{adbDevices.length}</span>
          <span className="stat-chip-label">ADB/ANDROID</span>
        </div>
        <div className="stat-chip" style={{ borderColor: "rgba(181,55,242,0.3)" }}>
          <span className="stat-chip-num" style={{ color: "var(--purple)" }}>{btDevices.length}</span>
          <span className="stat-chip-label">BLUETOOTH</span>
        </div>
        <div className="stat-chip" style={{ borderColor: "rgba(0,230,118,0.35)" }}>
          <span className="stat-chip-num" style={{ color: "#00E676" }}>{esp32Nodes.length}</span>
          <span className="stat-chip-label">ESP32 NODES</span>
        </div>
        <div className="stat-chip" style={{ borderColor: "rgba(252,238,10,0.3)" }}>
          <span className="stat-chip-num" style={{ color: "var(--yellow)" }}>
            {[...devices, ...adbDevices].filter((d) => d.permission === "granted" || d.adb_connected).length}
          </span>
          <span className="stat-chip-label">PERMITTED</span>
        </div>
      </div>

      {/* Tab switcher */}
      <div className="device-tabs">
        {["network", "adb", "bluetooth", "esp32"].map((t) => (
          <button
            key={t}
            id={`tab-${t}`}
            className={`device-tab-btn${tab === t ? " active" : ""}`}
            onClick={() => setTab(t)}
          >
            {t === "network" ? "⬡ NETWORK"
              : t === "adb" ? "📱 ADB"
              : t === "bluetooth" ? "🔵 BLUETOOTH"
              : `🤖 ESP32 NODES (${esp32Nodes.length})`}
          </button>
        ))}
        {tab === "bluetooth" && (
          <button id="bt-scan-btn" className="btn" onClick={handleBtScan} disabled={btScanning} style={{ marginLeft: "auto" }}>
            {btScanning ? "⏳ SCANNING..." : "⊕ BT SCAN"}
          </button>
        )}
        {tab === "esp32" && (
          <button id="esp32-refresh-btn" className="btn" onClick={loadEsp32Nodes} style={{ marginLeft: "auto" }}>
            ⟳ REFRESH
          </button>
        )}
      </div>

      {/* Device grid — network/adb/bluetooth */}
      {tab !== "esp32" && (
        (tab === "network" ? devices : tab === "adb" ? adbDevices : btDevices).length === 0 ? (
          <div className="devices-empty">
            <div style={{ fontSize: "3rem", opacity: 0.4, marginBottom: 12 }}>⬡</div>
            <div style={{ color: "var(--text-dim)", fontFamily: "'Orbitron', monospace", letterSpacing: 3 }}>
              NO {tab.toUpperCase()} DEVICES DETECTED
            </div>
            <div style={{ color: "var(--text-dim)", fontSize: "0.8rem", marginTop: 8 }}>
              {tab === "network" ? "Click SCAN NETWORK to discover devices on your local network"
               : tab === "adb" ? "Connect Android device via USB or WiFi ADB, then enable developer mode"
               : "Click BT SCAN to find nearby Bluetooth devices"}
            </div>
          </div>
        ) : (
          <div className="devices-grid">
            {(tab === "network" ? devices : tab === "adb" ? adbDevices : btDevices).map((d, i) => (
              <DeviceCard
                key={d.serial || d.mac || d.ip || i}
                device={{ ...d, adb_connected: tab === "adb" }}
                onUnlock={handleUnlock}
                onScreenshot={handleScreenshot}
                onPermit={handlePermit}
                onRevoke={handleRevoke}
                onShell={(serial) => setShellTarget(serial)}
              />
            ))}
          </div>
        )
      )}

      {/* ESP32 NODES tab */}
      {tab === "esp32" && (
        esp32Nodes.length === 0 ? (
          <div className="devices-empty">
            <div style={{ fontSize: "3rem", opacity: 0.4, marginBottom: 12 }}>🤖</div>
            <div style={{ color: "var(--text-dim)", fontFamily: "'Orbitron', monospace", letterSpacing: 3 }}>
              NO ESP32 NODES REGISTERED
            </div>
            <div style={{ color: "var(--text-dim)", fontSize: "0.8rem", marginTop: 8 }}>
              Power on your MEKA ESP32 node — it will self-register with the hub on boot
            </div>
          </div>
        ) : (
          <div className="devices-grid">
            {esp32Nodes.map((node, i) => (
              <Esp32NodeCard key={node.mac || i} node={node} />
            ))}
          </div>
        )
      )}

      {/* ADB Shell terminal overlay */}
      {shellTarget && (
        <AdbTerminal serial={shellTarget} onClose={() => setShellTarget(null)} />
      )}
    </div>
  );
}
