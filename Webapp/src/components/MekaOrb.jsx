// src/components/MekaOrb.jsx — The MEKA holographic orb UI
// Based on Ultron Orb by Sagar Builds, adapted for MEKA cyberpunk aesthetic
import { useCallback, useEffect, useRef, useState } from "react";
import { createOrbScene } from "../lib/orbScene";
import { HandTracker } from "../lib/handTracker";

const MODE_LABEL = { idle: "STANDBY", spin: "SPIN", zoom: "ZOOM" };

export default function MekaOrb({ onPanelToggle, currentPanel, status, online }) {
  const containerRef = useRef(null);
  const videoRef = useRef(null);
  const overlayRef = useRef(null);
  const sceneRef = useRef(null);
  const trackerRef = useRef(null);

  const [camera, setCamera] = useState("off"); // off | starting | on | error
  const [trackerStatus, setTrackerStatus] = useState({ hands: 0, mode: "idle" });
  const [error, setError] = useState(null);

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;
    const scene = createOrbScene(container);
    sceneRef.current = scene;
    return () => {
      trackerRef.current?.stop();
      trackerRef.current = null;
      scene.dispose();
      sceneRef.current = null;
    };
  }, []);

  const stopGestures = useCallback(() => {
    trackerRef.current?.stop();
    trackerRef.current = null;
    setCamera("off");
    setTrackerStatus({ hands: 0, mode: "idle" });
  }, []);

  const startGestures = useCallback(async () => {
    const video = videoRef.current;
    const overlay = overlayRef.current;
    if (!video || !overlay || trackerRef.current) return;
    setCamera("starting");
    setError(null);
    const tracker = new HandTracker(video, overlay, {
      onRotate: (dt, dp) => sceneRef.current?.rotateBy(dt, dp),
      onZoom: (factor) => sceneRef.current?.zoomBy(factor),
      onStatus: setTrackerStatus,
    });
    trackerRef.current = tracker;
    try {
      await tracker.start();
      setCamera("on");
    } catch (err) {
      trackerRef.current = null;
      tracker.stop();
      setCamera("error");
      setError(err instanceof DOMException && err.name === "NotAllowedError" ? "CAMERA DENIED" : "TRACKER INIT FAILED");
    }
  }, []);

  const toggleGestures = useCallback(() => {
    if (trackerRef.current) stopGestures();
    else void startGestures();
  }, [startGestures, stopGestures]);

  useEffect(() => {
    const onKey = (e) => {
      switch (e.key) {
        case "+": case "=": sceneRef.current?.zoomIn(); break;
        case "-": case "_": sceneRef.current?.zoomOut(); break;
        case "r": case "R": sceneRef.current?.resetView(); break;
        case "g": case "G": toggleGestures(); break;
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [toggleGestures]);

  const cameraOn = camera === "on";

  const statusColors = {
    listening:  "#00f0ff",
    processing: "#fcee0a",
    success:    "#00ff66",
    error:      "#ff0055",
    idle:       "rgba(255,255,255,0.3)",
  };
  const statusColor = statusColors[status] || statusColors.idle;

  const panels = [
    { id: "user",    icon: "◉", label: "COMMAND" },
    { id: "devices", icon: "⬡", label: "DEVICES" },
    { id: "cameras", icon: "⊡", label: "CAMERAS" },
    { id: "admin",   icon: "⚙", label: "ADMIN" },
  ];

  return (
    <>
      {/* Full-screen Three.js canvas */}
      <div ref={containerRef} className="orb-root" />

      {/* Cinematic overlays */}
      <div className="overlay-vignette" />
      <div className="overlay-grain" />
      <div className="overlay-scanlines" />

      {/* ── TOP LEFT: M.E.K.A. Title ── */}
      <div className="hud hud-title">
        <div className="hud-title-main">M.E.K.A.</div>
        <div className="hud-title-sub">MASTER ELECTRONIC KINETIC ASSISTANT</div>
        <div className="hud-title-line" />
        <div className="hud-status-row">
          <span className="hud-status-dot" style={{ background: statusColor, boxShadow: `0 0 8px ${statusColor}` }} />
          <span className="hud-status-text" style={{ color: statusColor }}>
            {status?.toUpperCase() || "IDLE"}
          </span>
          <span className="hud-online-tag" style={{ borderColor: online ? "#00ff66" : "#ff0055", color: online ? "#00ff66" : "#ff0055" }}>
            {online ? "[ LIVE ]" : "[ OFFLINE ]"}
          </span>
        </div>
      </div>

      {/* ── TOP RIGHT: System clock + stats ── */}
      <HudClock />

      {/* ── BOTTOM LEFT: Hints ── */}
      <div className="hud hud-hint">
        <div><span className="hud-key">DRAG</span> spin &nbsp; <span className="hud-key">SCROLL</span> zoom</div>
        {cameraOn ? (
          <div><span className="hud-key">PINCH + MOVE</span> spin &nbsp; <span className="hud-key">PINCH BOTH ± SPREAD</span> zoom</div>
        ) : (
          <div><span className="hud-key">G</span> gestures &nbsp; <span className="hud-key">R</span> reset &nbsp; <span className="hud-key">+/−</span> zoom</div>
        )}
        {cameraOn && trackerStatus.hands > 0 && (
          <div className="hud-gesture-status">
            🖐 {trackerStatus.hands} HAND{trackerStatus.hands > 1 ? "S" : ""} — {MODE_LABEL[trackerStatus.mode]}
          </div>
        )}
      </div>

      {/* ── BOTTOM RIGHT: Controls ── */}
      <div className="hud hud-controls">
        {/* Camera gesture panel */}
        <div className={`meka-camera-panel${cameraOn ? " visible" : ""}`}>
          <video ref={videoRef} muted playsInline className="meka-camera-video" />
          <canvas ref={overlayRef} width={208} height={156} className="meka-camera-overlay" />
          <div className="meka-camera-status">
            {trackerStatus.hands > 0 ? `${trackerStatus.hands} HAND${trackerStatus.hands > 1 ? "S" : ""} · ${MODE_LABEL[trackerStatus.mode]}` : "SHOW HANDS"}
          </div>
        </div>

        {error && <div className="hud-error">{error}</div>}

        <div className="hud-row">
          <button type="button" className="hud-btn" aria-pressed={cameraOn} onClick={toggleGestures} disabled={camera === "starting"} id="gesture-toggle-btn">
            {camera === "starting" ? "INITIALIZING…" : cameraOn ? "GESTURES ON" : "GESTURES OFF"}
          </button>
        </div>
        <div className="hud-row">
          <button type="button" className="hud-btn" onClick={() => sceneRef.current?.zoomIn()} aria-label="Zoom in" id="orb-zoom-in">+</button>
          <button type="button" className="hud-btn" onClick={() => sceneRef.current?.zoomOut()} aria-label="Zoom out" id="orb-zoom-out">−</button>
          <button type="button" className="hud-btn" onClick={() => sceneRef.current?.resetView()} id="orb-reset">RESET</button>
        </div>
      </div>

      {/* ── CENTER BOTTOM: Navigation Ring ── */}
      <nav className="orb-nav">
        {panels.map((p) => (
          <button
            key={p.id}
            id={`nav-${p.id}`}
            className={`orb-nav-btn${currentPanel === p.id ? " active" : ""}`}
            onClick={() => onPanelToggle(p.id)}
          >
            <span className="orb-nav-icon">{p.icon}</span>
            <span className="orb-nav-label">{p.label}</span>
          </button>
        ))}
      </nav>
    </>
  );
}

function HudClock() {
  const [time, setTime] = useState(new Date());
  useEffect(() => {
    const t = setInterval(() => setTime(new Date()), 1000);
    return () => clearInterval(t);
  }, []);
  const h = time.getHours().toString().padStart(2, "0");
  const m = time.getMinutes().toString().padStart(2, "0");
  const s = time.getSeconds().toString().padStart(2, "0");
  return (
    <div className="hud hud-clock">
      <div className="hud-clock-time">{h}:{m}<span className="hud-clock-sec">:{s}</span></div>
      <div className="hud-clock-date">{time.toLocaleDateString("en-US", { weekday: "short", month: "short", day: "numeric" }).toUpperCase()}</div>
      <div className="hud-clock-line" />
    </div>
  );
}
