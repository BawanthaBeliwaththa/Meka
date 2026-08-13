import { useState, useEffect, useCallback, useRef } from "react";
import { ref, onValue, set, update } from "firebase/database";
import { ref as storageRef, uploadBytes } from "firebase/storage";
import { db, storage } from "../firebase";
import CommandLog from "../components/CommandLog";
import { llm } from "../lib/llmService";

const HUB_URL = import.meta.env.VITE_HUB_URL || "http://localhost:5000";
const IS_LOCAL = window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1';

function hubFetch(path, opts = {}) {
  const url = IS_LOCAL ? `${HUB_URL}${path}` : path;
  return fetch(url, { ...opts, mode: IS_LOCAL ? "cors" : "same-origin" });
}

function isBridge(mac) { return mac && mac.startsWith("bridge_"); }
function getBridgeEndpoint(mac) {
  const ip = mac.replace("bridge_", "").replace(/_/g, ".");
  return `/phone-bridge/frame?ip=${encodeURIComponent(ip)}`;
}

function BigStatusDisplay({ status }) {
  const configs = {
    listening:  { icon: "[MIC]",  label: "LISTENING...",  color: "var(--blue)",    glow: "var(--glow-blue)",   ledCls: "blue" },
    processing: { icon: "[SYS]",  label: "PROCESSING...", color: "var(--yellow)",  glow: "var(--glow-yellow)", ledCls: "yellow" },
    success:    { icon: "[RDY]",  label: "SYS_READY",     color: "var(--green)",   glow: "var(--glow-green)",  ledCls: "green" },
    error:      { icon: "[ERR]",  label: "SYS_FAULT",     color: "var(--red)",     glow: "var(--glow-red)",    ledCls: "red" },
    idle:       { icon: "[IDLE]", label: "SYS_IDLE",      color: "var(--text-dim)", glow: "none",              ledCls: "off" },
  };
  const cfg = configs[status] || configs.idle;
  return (
    <div className="card" style={{ textAlign: "center", padding: "1.75rem 1.25rem", borderColor: cfg.color, boxShadow: cfg.glow, transition: "all 0.4s" }}>
      <div style={{ fontSize: "2rem", marginBottom: "0.5rem", fontWeight: 700, letterSpacing: "2px", animation: status === "processing" ? "pulse 1.2s infinite" : "none" }}>
        {cfg.icon}
      </div>
      <div style={{ fontSize: "1.3rem", fontWeight: 800, color: cfg.color, marginBottom: 4 }}>{cfg.label}</div>
      <p style={{ color: "var(--text-dim)", fontSize: "0.78rem" }}>MEKA AI · {status === "idle" ? "awaiting command" : status}</p>
      <div style={{ display: "flex", justifyContent: "center", gap: 12, marginTop: "0.9rem" }}>
        {["blue", "yellow", "green", "red"].map(c => (
          <span key={c} className={`led ${cfg.ledCls === c ? c : "off"}`} />
        ))}
      </div>
    </div>
  );
}

function useVoiceInput(onResult) {
  const [isListening, setIsListening] = useState(false);
  const recognitionRef = useRef(null);
  const start = useCallback(() => {
    const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!SR) { alert("Voice input not supported. Use Chrome or Edge."); return; }
    const r = new SR();
    r.continuous = false; r.interimResults = false; r.lang = "en-US";
    r.onresult = (e) => { onResult(e.results[0][0].transcript); setIsListening(false); };
    r.onerror = () => setIsListening(false);
    r.onend = () => setIsListening(false);
    recognitionRef.current = r;
    r.start();
    setIsListening(true);
  }, [onResult]);
  const stop = useCallback(() => { recognitionRef.current?.stop(); setIsListening(false); }, []);
  return { isListening, start, stop };
}

export default function UserPanel({ currentUser, isAdmin }) {
  // Keep LLM service in sync with the logged-in user's name
  useEffect(() => { llm.setUserName(currentUser?.displayName || currentUser?.email?.split('@')[0] || 'Sir'); }, [currentUser]);

  const [meka, setMeka]           = useState({});
  const [chatInput, setChatInput] = useState("");
  const [sending, setSending]     = useState(false);
  const [camSnap, setCamSnap]     = useState(null);
  const snapBlobUrl               = useRef(null);
  const [camLive, setCamLive]     = useState(false);
  const [cameras, setCameras]     = useState([]);
  const [selectedCam, setSelectedCam] = useState("");
  const [isRecording, setIsRecording] = useState(false);
  const [uploadMsg, setUploadMsg] = useState("");
  const [speakers, setSpeakers]   = useState([]);
  const [outputMac, setOutputMac] = useState(() => localStorage.getItem("meka_output_mac") || "all");
  const [outputSaved, setOutputSaved] = useState(false);
  const [hubOnline, setHubOnline] = useState(false);

  const setSnapBlob = useCallback((blob) => {
    if (snapBlobUrl.current) URL.revokeObjectURL(snapBlobUrl.current);
    const url = URL.createObjectURL(blob);
    snapBlobUrl.current = url;
    setCamSnap(url);
  }, []);

  useEffect(() => () => { if (snapBlobUrl.current) URL.revokeObjectURL(snapBlobUrl.current); }, []);

  useEffect(() => {
    const unsub = onValue(ref(db, "/meka"), snap => setMeka(snap.val() || {}));
    return () => unsub();
  }, []);

  const loadHubData = useCallback(async () => {
    try {
      const [spkRes, camRes] = await Promise.all([
        hubFetch("/api/speakers"),
        hubFetch("/api/cameras"),
      ]);
      if (spkRes.ok) { const d = await spkRes.json(); if (d?.speakers) setSpeakers(d.speakers); }
      if (camRes.ok) {
        const d = await camRes.json();
        if (d?.cameras) {
          setCameras(d.cameras);
          setHubOnline(true);
        }
      } else { setHubOnline(false); }
    } catch { setHubOnline(false); }
  }, []);

  useEffect(() => {
    loadHubData();
    const t = setInterval(loadHubData, 8000);
    return () => clearInterval(t);
  }, [loadHubData]);

  const fetchCamFrame = useCallback(async () => {
    if (!selectedCam) return;
    try {
      const endpoint = isBridge(selectedCam) ? getBridgeEndpoint(selectedCam) : `/api/cameras/${selectedCam}/snapshot`;
      const r = await hubFetch(endpoint);
      if (r.ok) setSnapBlob(await r.blob());
    } catch { /* silent */ }
  }, [selectedCam, setSnapBlob]);

  useEffect(() => {
    if (snapBlobUrl.current) { URL.revokeObjectURL(snapBlobUrl.current); snapBlobUrl.current = null; }
    setCamSnap(null);
    setCamLive(false);
  }, [selectedCam]);

  useEffect(() => {
    if (!camLive || !selectedCam) {
      if (!isBridge(selectedCam)) { if (snapBlobUrl.current) { URL.revokeObjectURL(snapBlobUrl.current); snapBlobUrl.current = null; } setCamSnap(null); }
      return;
    }
    if (isBridge(selectedCam)) {
      fetchCamFrame();
      const t = setInterval(fetchCamFrame, 500);
      return () => clearInterval(t);
    } else {
      // Use relative path so it works from any domain through Nginx
      const streamBase = IS_LOCAL ? HUB_URL : '';
      setCamSnap(`${streamBase}/api/cameras/${selectedCam}/stream?_=${Date.now()}`);
    }
  }, [camLive, selectedCam, fetchCamFrame]);

  const handleTakeSnapshot = async () => {
    if (!selectedCam) return;
    setUploadMsg("[CAM] Taking snapshot...");
    try {
      const endpoint = isBridge(selectedCam) ? getBridgeEndpoint(selectedCam) : `/api/cameras/${selectedCam}/snapshot`;
      const r = await hubFetch(endpoint);
      if (!r.ok) throw new Error("Hub returned error");
      const blob = await r.blob();
      await uploadBytes(storageRef(storage, `snapshots/snap_${Date.now()}.jpg`), blob);
      setUploadMsg("[OK] Snapshot saved to Firebase!");
    } catch (e) { setUploadMsg("[ERR] Snapshot failed: " + e.message); }
    setTimeout(() => setUploadMsg(""), 4000);
  };

  const handleToggleRecord = async () => {
    if (!selectedCam || isBridge(selectedCam)) { setUploadMsg("[WARN] Cannot record phone bridge."); setTimeout(() => setUploadMsg(""), 3000); return; }
    if (!isRecording) {
      setUploadMsg("[REC] Starting recording...");
      try {
        const r = await hubFetch(`/api/cameras/${selectedCam}/record/start`, { method: "POST" });
        if (r.ok) { setIsRecording(true); setUploadMsg("[REC] Recording active..."); }
        else setUploadMsg("[ERR] Failed to start recording.");
      } catch { setUploadMsg("[ERR] Error starting recording."); }
    } else {
      setUploadMsg("[STOP] Stopping recording...");
      try {
        const r = await hubFetch(`/api/cameras/${selectedCam}/record/stop`, { method: "POST" });
        if (r.ok) {
          setIsRecording(false);
          const data = await r.json();
          if (data.recording_id) {
            setUploadMsg("[UP] Uploading video...");
            const dl = await hubFetch(`/api/recordings/${data.recording_id}/download`);
            if (dl.ok) {
              await uploadBytes(storageRef(storage, `recordings/rec_${Date.now()}.mp4`), await dl.blob());
              setUploadMsg("[OK] Video saved to Firebase!");
            } else setUploadMsg("[ERR] Download failed.");
          }
        }
      } catch { setUploadMsg("[ERR] Error saving recording."); }
      setTimeout(() => setUploadMsg(""), 5000);
    }
  };

  const { isListening, start: startVoice, stop: stopVoice } = useVoiceInput((transcript) => {
    setChatInput(transcript);
    sendChat(transcript);
  });

  const speak = (text) => {
    if (!window.speechSynthesis) return;
    window.speechSynthesis.cancel();
    const u = new SpeechSynthesisUtterance(text);
    u.rate = 1.05; u.pitch = 0.9;
    const voices = window.speechSynthesis.getVoices();
    const v = voices.find(v => v.name.includes("Google UK English Male") || v.name.includes("Zira")) || voices[0];
    if (v) u.voice = v;
    window.speechSynthesis.speak(u);
  };

  async function sendChat(text) {
    if (!text.trim()) return;
    setSending(true); setChatInput("");
    try {
      await update(ref(db, "/meka"), { lcd_q: text, lcd_a: "Thinking..." });
      await set(ref(db, "/meka/command_input"), {
        command: text,
        source: "web_user",
        user_email: currentUser?.email || "anonymous",
        ts: Date.now()
      });

      // Log command for admin view with user email tracking
      const logRef = ref(db, `/meka/command_log/${Date.now()}`);
      
      const response = await llm.chat(text);
      speak(response);
      await update(ref(db, "/meka"), { lcd_a: response });

      await set(logRef, {
        command: text,
        response: response,
        source: "web_user",
        user_email: currentUser?.email || "anonymous",
        status: "success",
        ts: Date.now()
      });
    } catch (e) {
      console.error(e);
      const errorMsg = "Neural connection failed. Check API key.";
      speak(errorMsg);
      await update(ref(db, "/meka"), { lcd_a: "ERROR: " + errorMsg });
    }
    setSending(false);
  }

  function saveOutputDevice() {
    localStorage.setItem("meka_output_mac", outputMac);
    setOutputSaved(true);
    setTimeout(() => setOutputSaved(false), 2500);
  }

  const status     = meka.status   || "idle";
  const sensors    = meka.sensors  || {};
  const servoAngle = meka.servo_cmd?.angle ?? 90;
  const lcdQ       = meka.lcd_q || "MEKA v.1.0.1";
  const lcdA       = meka.lcd_a || "Idle...";
  const selectedCamInfo = cameras.find(c => c.mac === selectedCam);

  return (
    <div className="page">
      {/* Header */}
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "1.25rem", flexWrap: "wrap", gap: 10 }}>
        <div>
          <h1 className="glitch" data-text="MEKA_USER_CONSOLE" style={{ fontSize: "1.6rem", fontWeight: 800 }}>MEKA_USER_CONSOLE</h1>
          <p style={{ color: "var(--text-dim)", marginTop: 4, fontSize: "0.78rem" }}>&gt; REALTIME AI · SENSOR · DEVICE CONTROL</p>
        </div>
        <div className="card" style={{ padding: "8px 14px", display: "flex", alignItems: "center", gap: 10, borderRadius: 14, flexShrink: 0, maxWidth: "100%" }}>
          <span style={{ fontSize: "1.1rem" }}>{isAdmin ? "[ADMIN]" : "[USER]"}</span>
          <div style={{ display: "flex", flexDirection: "column", minWidth: 0 }}>
            <span style={{ fontSize: "0.78rem", fontWeight: 700, color: "#f8fafc", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", maxWidth: 160 }}>
              {currentUser?.displayName || currentUser?.email}
            </span>
            <span style={{ fontSize: "0.68rem", color: "var(--green)", fontWeight: 600 }}>[ VERIFIED_IDENTITY ]</span>
          </div>
        </div>
      </div>

      {/* Main Status Display & Visualizer */}
      <div className="grid-2" style={{ marginBottom: "1.25rem" }}>
        <BigStatusDisplay status={status} />

        {/* Real-time Telemetry & Screen Analyzer View */}
        <div className="card" style={{ display: "flex", flexDirection: "column", justifyContent: "space-between" }}>
          <div className="section-header">
            <span style={{ fontSize: "1rem", color: "var(--blue)" }}>[SYS]</span>
            <span className="section-title">TELEMETRY_ANALYZER</span>
            <span className="section-sub">LIVE</span>
          </div>

          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 10, margin: "10px 0" }}>
            <div style={{ background: "rgba(255,255,255,0.03)", padding: 10, borderRadius: 8, border: "1px solid var(--border)" }}>
              <div style={{ fontSize: "0.7rem", color: "var(--text-dim)" }}>THERMAL SENSOR</div>
              <div style={{ fontSize: "1.1rem", fontWeight: 700, color: "var(--yellow)", marginTop: 2 }}>
                {sensors.temperature_c ? `${sensors.temperature_c}°C` : "27.5°C"}
              </div>
            </div>

            <div style={{ background: "rgba(255,255,255,0.03)", padding: 10, borderRadius: 8, border: "1px solid var(--border)" }}>
              <div style={{ fontSize: "0.7rem", color: "var(--text-dim)" }}>HYGROMETER</div>
              <div style={{ fontSize: "1.1rem", fontWeight: 700, color: "var(--blue)", marginTop: 2 }}>
                {sensors.humidity ? `${sensors.humidity}%` : "58%"}
              </div>
            </div>

            <div style={{ background: "rgba(255,255,255,0.03)", padding: 10, borderRadius: 8, border: "1px solid var(--border)" }}>
              <div style={{ fontSize: "0.7rem", color: "var(--text-dim)" }}>SERVO ORIENTATION</div>
              <div style={{ fontSize: "1.1rem", fontWeight: 700, color: "var(--purple)", marginTop: 2 }}>
                {servoAngle}°
              </div>
            </div>

            <div style={{ background: "rgba(255,255,255,0.03)", padding: 10, borderRadius: 8, border: "1px solid var(--border)" }}>
              <div style={{ fontSize: "0.7rem", color: "var(--text-dim)" }}>ACTIVE NODES</div>
              <div style={{ fontSize: "1.1rem", fontWeight: 700, color: "var(--green)", marginTop: 2 }}>
                {cameras.length + speakers.length}
              </div>
            </div>
          </div>

          <div style={{ padding: "8px 12px", background: "rgba(0,212,255,0.05)", border: "1px solid rgba(0,212,255,0.2)", borderRadius: 8, fontSize: "0.72rem", color: "var(--blue)" }}>
            &gt; SYSTEM STATE: Normal Operation. Voice commands active via Terminal or Telegram.
          </div>
        </div>
      </div>

      {/* Camera Stream Monitor */}
      <div className="card" style={{ marginBottom: "1.25rem" }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "0.75rem", flexWrap: "wrap", gap: 8 }}>
          <div className="section-header" style={{ margin: 0 }}>
            <span style={{ fontSize: "1rem", color: "var(--green)" }}>[CAM]</span>
            <span className="section-title">CAMERA_FEED</span>
            <span className={`badge ${selectedCamInfo?.online ? "badge-success" : "badge-error"}`} style={{ fontSize: "0.6rem" }}>
              {selectedCamInfo?.online ? "[ ONLINE ]" : "[ OFFLINE ]"}
            </span>
            <span style={{
              fontSize: "0.58rem", fontFamily: "'Orbitron',monospace", padding: "2px 7px", borderRadius: 3,
              border: `1px solid ${hubOnline ? "var(--green)" : "var(--pink)"}`,
              color: hubOnline ? "var(--green)" : "var(--pink)",
            }}>{hubOnline ? "[ HUB LIVE ]" : "[ OFFLINE ]"}</span>
          </div>
          <select
            className="input"
            value={selectedCam}
            onChange={e => setSelectedCam(e.target.value)}
            style={{ width: "auto", minWidth: 180, padding: "0.3rem 0.6rem", fontSize: "0.82rem" }}
          >
            <option value="">&gt; Select Camera...</option>
            {cameras.map(c => (
              <option key={c.mac} value={c.mac}>
                {isBridge(c.mac) ? "[PHN]" : "[CAM]"} {c.name || c.ip}{isBridge(c.mac) ? " (Bridge)" : ""}
              </option>
            ))}
          </select>
        </div>

        {uploadMsg && (
          <div style={{ padding: "6px 12px", background: "rgba(124,77,255,0.12)", border: "1px solid var(--purple)", borderRadius: 6, fontSize: "0.78rem", color: "var(--purple)", marginBottom: 8 }}>
            &gt; {uploadMsg}
          </div>
        )}

        <div className="camera-feed" style={{ marginBottom: "0.75rem" }}>
          {selectedCam && camLive ? (
            <iframe
              src={isBridge(selectedCam)
                ? (IS_LOCAL ? `${HUB_URL}${getBridgeEndpoint(selectedCam)}` : getBridgeEndpoint(selectedCam))
                : (IS_LOCAL ? `${HUB_URL}/api/cameras/${selectedCam}/stream` : `/api/cameras/${selectedCam}/stream`)}
              style={{ width: "100%", height: "100%", border: "none" }}
              title="Camera Stream"
            />
          ) : (
            <div className="camera-placeholder">
              <div style={{ fontSize: "2rem", marginBottom: "0.5rem" }}>[ CAM ]</div>
              <div>{!selectedCam ? "> SELECT A CAMERA ABOVE" : camLive ? "> CONNECTING..." : "> PRESS START STREAM"}</div>
            </div>
          )}
          {camLive && <div style={{ position: "absolute", top: 10, right: 10, background: "rgba(0,230,118,0.9)", color: "#000", padding: "3px 10px", borderRadius: 12, fontSize: "0.68rem", fontWeight: 800 }}>[ LIVE ]</div>}
          {isRecording && <div style={{ position: "absolute", top: 10, left: 10, background: "rgba(255,61,113,0.9)", color: "#fff", padding: "3px 10px", borderRadius: 12, fontSize: "0.68rem", fontWeight: 800, animation: "pulse 1s infinite" }}>[ REC ]</div>}
          {selectedCamInfo && (
            <div style={{ position: "absolute", bottom: 0, left: 0, right: 0, padding: "5px 10px", background: "rgba(0,0,0,0.6)", fontSize: "0.65rem", fontFamily: "'Share Tech Mono',monospace", color: "rgba(255,255,255,0.45)", display: "flex", justifyContent: "space-between" }}>
              <span>{selectedCamInfo.name || selectedCamInfo.ip}</span>
              <span>{selectedCamInfo.vendor || "IP Camera"}</span>
            </div>
          )}
        </div>

        <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
          <button className={`btn ${camLive ? "btn-danger" : "btn-primary"}`} style={{ flex: "1 1 120px" }} onClick={() => setCamLive(v => !v)} disabled={!selectedCam}>
            {camLive ? <>[ STOP STREAM ]</> : <>[ START STREAM ]</>}
          </button>
          {isAdmin && (
            <>
              <button className="btn btn-ghost" style={{ flex: "1 1 100px" }} onClick={handleTakeSnapshot} disabled={!selectedCam}>
                [CAM] SNAPSHOT
              </button>
              <button className={`btn ${isRecording ? "btn-danger" : "btn-ghost"}`} style={{ flex: "1 1 100px" }} onClick={handleToggleRecord} disabled={!selectedCam || isBridge(selectedCam)}>
                [VID] {isRecording ? "STOP REC" : "RECORD"}
              </button>
            </>
          )}
        </div>
      </div>

      {/* Voice Output Device Selection */}
      <div className="card" style={{ marginBottom: "1.25rem" }}>
        <div className="section-header">
          <span style={{ fontSize: "1rem", color: "var(--green)" }}>[OUT]</span>
          <span className="section-title">VOICE_OUTPUT</span>
          <span className="section-sub">ROUTING</span>
        </div>
        <div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}>
          <select className="input" value={outputMac} onChange={e => setOutputMac(e.target.value)} style={{ flex: 1, minWidth: 160 }}>
            <option value="all">[ ALL_NODES_BROADCAST ]</option>
            {speakers.map(s => (
              <option key={s.mac} value={s.mac}>&gt; {s.name || s.hostname || s.ip} ({s.mac?.slice(-5)})</option>
            ))}
          </select>
          <button className="btn btn-primary" onClick={saveOutputDevice} style={{ minWidth: 80, flexShrink: 0 }}>
            {outputSaved ? "[ SAVED ]" : "[ SAVE ]"}
          </button>
        </div>
        <p style={{ color: "var(--text-dim)", fontSize: "0.7rem", marginTop: 8 }}>
          &gt; {speakers.length === 0 ? "No speaker nodes detected. Connect a device via Phone Bridge." : `${speakers.length} speaker node(s) online.`}
        </p>
      </div>

      {/* Voice & Text Terminal Console */}
      <div className="card">
        <div className="section-header">
          <span style={{ fontSize: "1rem", color: "var(--green)" }}>[CMD]</span>
          <span className="section-title">VOICE & TEXT TERMINAL</span>
          <span className="section-sub">INTERACTIVE</span>
        </div>
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
          <input className="input" value={chatInput} onChange={e => setChatInput(e.target.value)} placeholder="> ENTER COMMAND OR SAY 'UNLOCK DEVICE', 'TURN SERVO 90'..." onKeyDown={e => e.key === "Enter" && !sending && sendChat(chatInput)} style={{ flex: 1, minWidth: 160 }} />
          <button id="btn-voice-input" className={`btn ${isListening ? "btn-danger" : "btn-ghost"}`} onClick={isListening ? stopVoice : startVoice} title="Voice Input" style={{ padding: "0 14px", flexShrink: 0 }}>
            {isListening ? "[ STOP ]" : "[ MIC ]"}
          </button>
          <button className="btn btn-primary" onClick={() => sendChat(chatInput)} disabled={sending || !chatInput.trim()} style={{ flexShrink: 0 }}>
            {sending ? "TX..." : "SEND"}
          </button>
        </div>
        {isListening && (
          <div style={{ marginTop: 10, padding: "8px 14px", background: "rgba(255,61,113,0.08)", border: "1px solid rgba(255,61,113,0.3)", borderRadius: 8, color: "var(--red)", fontSize: "0.82rem", animation: "pulse 1s infinite" }}>
            [ MIC ON ] Listening... speak now
          </div>
        )}
      </div>
    </div>
  );
}
