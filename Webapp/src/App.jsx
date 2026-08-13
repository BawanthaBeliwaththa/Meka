// src/App.jsx — MEKA v3 Super — Orb-First Layout with Full Panel System
import { useState, useEffect } from "react";
import { ref, onValue, set, get } from "firebase/database";
import { onAuthStateChanged } from "firebase/auth";
import { db, auth, googleProvider, signInWithPopup, signOut } from "./firebase";
import MekaOrb from "./components/MekaOrb";
import AdminPanel from "./pages/AdminPanel";
import UserPanel from "./pages/UserPanel";
import DevicesPanel from "./pages/DevicesPanel";
import logoImg from "./assets/logo.jpg";
import "./index.css";

const PRIMARY_ADMIN = "bawanthabeliwaththa@gmail.com";

// ── Login Screen ───────────────────────────────────────────────────────────────
function LoginScreen() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  const handleGoogleLogin = async () => {
    setLoading(true);
    setError("");
    try {
      await signInWithPopup(auth, googleProvider);
    } catch (err) {
      setError(err.message || "Failed to sign in with Google");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="login-screen">
      {/* Animated background orb glow */}
      <div className="login-bg-glow login-bg-glow-1" />
      <div className="login-bg-glow login-bg-glow-2" />
      <div className="login-bg-glow login-bg-glow-3" />
      <div className="overlay-grain" />
      <div className="overlay-scanlines" />

      <div className="login-card">
        {/* Logo */}
        <div className="login-logo-ring">
          <img src={logoImg} alt="MEKA" className="login-logo" />
          <div className="login-logo-ring-anim" />
        </div>

        <div className="login-title" data-text="M.E.K.A.">M.E.K.A.</div>
        <div className="login-subtitle">MASTER ELECTRONIC KINETIC ASSISTANT</div>
        <div className="login-version">v3.0 · SUPER EDITION</div>

        <div className="login-divider" />

        <p className="login-desc">
          Firebase IoT Intelligence Platform. Authenticate to access the neural interface.
        </p>

        {error && <div className="login-error">{error}</div>}

        <button
          id="google-signin-btn"
          onClick={handleGoogleLogin}
          disabled={loading}
          className="login-btn"
        >
          <svg width="20" height="20" viewBox="0 0 24 24" style={{ flexShrink: 0 }}>
            <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/>
            <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
            <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.06H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.94l2.85-2.22.81-.63z"/>
            <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.06l3.66 2.84c.87-2.6 3.3-4.52 6.16-4.52z"/>
          </svg>
          {loading ? "AUTHENTICATING..." : "SIGN IN WITH GOOGLE"}
        </button>

        <div className="login-footer">
          <span>SECURE · LOCAL NETWORK · FIREBASE AUTH</span>
        </div>
      </div>
    </div>
  );
}

// ── Cameras Quick Panel ────────────────────────────────────────────────────────
function CamerasQuickPanel() {
  const [cameras, setCameras] = useState([]);
  const [loading, setLoading] = useState(true);
  const IS_LOCAL = window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1';
  const HUB = import.meta.env.VITE_HUB_URL || "http://localhost:5000";

  useEffect(() => {
    const apiUrl = IS_LOCAL ? `${HUB}/api/cameras` : '/api/cameras';
    fetch(apiUrl, { mode: IS_LOCAL ? "cors" : "same-origin" })
      .then((r) => r.ok ? r.json() : null)
      .then((j) => { if (j) setCameras(j.cameras || []); })
      .catch(() => {})
      .finally(() => setLoading(false));
  }, [IS_LOCAL, HUB]);

  if (loading) return <div style={{ color: "var(--text-dim)", padding: 24, fontFamily: "'Orbitron', monospace" }}>SCANNING CAMERA NETWORK...</div>;
  if (!cameras.length) return (
    <div style={{ color: "var(--text-dim)", padding: 24, textAlign: "center" }}>
      <div style={{ fontSize: "3rem", marginBottom: 12 }}>[ CAM ]</div>
      <div style={{ fontFamily: "'Orbitron', monospace", letterSpacing: 3 }}>NO CAMERAS ONLINE</div>
      <div style={{ fontSize: "0.8rem", marginTop: 8 }}>Ensure cameras are registered in the IoT Hub</div>
    </div>
  );

  return (
    <div className="page">
      <div className="panel-header">
        <div className="panel-title">CAMERA NETWORK</div>
        <span className="section-sub">{cameras.length} FEEDS</span>
      </div>
      <div className="cameras-grid">
        {cameras.map((cam) => (
          <div key={cam.mac} className="camera-feed-card">
            <div className="camera-feed-header">
              <span>{cam.name || cam.friendly_name || cam.vendor || "Camera"}</span>
              <span className={`badge ${cam.online ? "badge-success" : "badge-error"}`} style={{ fontSize: "0.6rem" }}>
                {cam.online ? "LIVE" : "OFFLINE"}
              </span>
            </div>
            {cam.online ? (
              <img
                src={cam.is_bridge
                  ? (IS_LOCAL ? `${HUB}/phone-bridge/frame?ip=${cam.ip}` : `/phone-bridge/frame?ip=${cam.ip}`)
                  : (IS_LOCAL ? `${HUB}/api/cameras/${cam.mac}/snapshot` : `/api/cameras/${cam.mac}/snapshot`)}
                alt={cam.name || cam.friendly_name || "Camera Feed"}
                className="camera-feed-img"
                onError={(e) => { e.target.style.display = "none"; }}
              />
            ) : (
              <div className="camera-feed-placeholder">[ FEED UNAVAILABLE ]</div>
            )}
            <div className="camera-feed-footer">{cam.ip}</div>
          </div>
        ))}
      </div>
    </div>
  );
}

// ── Panel Drawer ───────────────────────────────────────────────────────────────
function PanelDrawer({ panel, currentUser, isAdmin, onClose }) {
  if (!panel) return null;
  return (
    <>
      <div className="drawer-backdrop" onClick={onClose} />
      <div className="drawer" id="main-drawer">
        <div className="drawer-header">
          <button id="drawer-close-btn" className="drawer-close" onClick={onClose}>
            ✕ CLOSE
          </button>
          <div className="drawer-title">
            {panel === "user" ? "⬡ COMMAND CENTER"
              : panel === "admin" ? "⚙ ADMIN CONTROL"
              : panel === "devices" ? "⬡ DEVICE MATRIX"
              : "⊡ CAMERAS"}
          </div>
        </div>
        <div className="drawer-body">
          {panel === "user" && <UserPanel currentUser={currentUser} isAdmin={isAdmin} />}
          {panel === "admin" && isAdmin && <AdminPanel currentUser={currentUser} />}
          {panel === "devices" && <DevicesPanel />}
          {panel === "cameras" && <CamerasQuickPanel />}
        </div>
      </div>
    </>
  );
}


// ── Top Bar (minimal, over the orb) ───────────────────────────────────────────
function TopBar({ currentUser, isAdmin, online, onSignOut }) {
  return (
    <div className="topbar">
      <div className="topbar-left">
        <img src={logoImg} alt="MEKA" className="topbar-logo" />
        <div className="topbar-brand">
          <span className="topbar-name">M.E.K.A.</span>
          <span className="topbar-ver">v3.0 SUPER</span>
        </div>
      </div>
      <div className="topbar-right">
        <span className={`topbar-badge ${online ? "online" : "offline"}`}>
          {online ? "● LIVE" : "○ OFFLINE"}
        </span>
        {currentUser?.photoURL ? (
          <img src={currentUser.photoURL} alt={currentUser.displayName} className="topbar-avatar" />
        ) : (
          <div className="topbar-avatar-fallback">
            {(currentUser?.displayName || currentUser?.email || "M")[0].toUpperCase()}
          </div>
        )}
        <div className="topbar-user-info">
          <span className="topbar-user-name">{currentUser?.displayName || currentUser?.email?.split("@")[0]}</span>
          <span className="topbar-user-role" style={{ color: isAdmin ? "var(--cyan)" : "var(--green)" }}>
            {isAdmin ? "👑 ADMIN" : "◉ USER"}
          </span>
        </div>
        <button id="signout-btn" className="topbar-signout" onClick={onSignOut}>LOGOUT</button>
      </div>
    </div>
  );
}

// ── Main App ──────────────────────────────────────────────────────────────────
export default function App() {
  const [currentUser, setCurrentUser] = useState(null);
  const [isAdmin, setIsAdmin] = useState(false);
  const [authLoading, setAuthLoading] = useState(true);
  const [status, setStatus] = useState("idle");
  const [online, setOnline] = useState(false);
  const [activePanel, setActivePanel] = useState(null); // null = orb fullscreen

  useEffect(() => {
    const unsubAuth = onAuthStateChanged(auth, async (user) => {
      if (user?.email) {
        const emailKey = user.email.replace(/\./g, "_dot_");
        let adminState = user.email.toLowerCase() === PRIMARY_ADMIN.toLowerCase();
        if (!adminState) {
          const snap = await get(ref(db, `/meka/admins/${emailKey}`));
          if (snap.exists() && snap.val()) adminState = true;
        }
        setIsAdmin(adminState);

        const userRef = ref(db, `/meka/users/${emailKey}`);
        const userSnap = await get(userRef);
        await set(userRef, {
          uid: user.uid,
          name: user.displayName || user.email.split("@")[0],
          email: user.email,
          photoURL: user.photoURL || "",
          isAdmin: adminState,
          lastLogin: Date.now(),
          createdAt: userSnap.exists() ? (userSnap.val().createdAt || Date.now()) : Date.now(),
        });

        if (user.email.toLowerCase() === PRIMARY_ADMIN.toLowerCase()) {
          await set(ref(db, `/meka/admins/${emailKey}`), { email: user.email, addedAt: Date.now(), addedBy: "system" });
        }

        await set(ref(db, `/meka/login_events/${Date.now()}`), {
          name: user.displayName || user.email.split("@")[0],
          email: user.email,
          isNew: !userSnap.exists(),
          ts: Date.now(),
        });

        setCurrentUser(user);
      } else {
        setCurrentUser(null);
        setIsAdmin(false);
      }
      setAuthLoading(false);
    });

    const unsubStatus = onValue(ref(db, "/meka/status"), (snap) => {
      setStatus(snap.val() || "idle");
      setOnline(true);
    }, () => setOnline(false));

    return () => { unsubAuth(); unsubStatus(); };
  }, []);

  const handlePanelToggle = (panelId) => {
    // If not admin, block admin panel
    if (panelId === "admin" && !isAdmin) return;
    setActivePanel((prev) => (prev === panelId ? null : panelId));
  };

  if (authLoading) {
    return (
      <div className="boot-screen">
        <div className="boot-orb-glow" />
        <div className="boot-text">
          <span className="boot-meka">M.E.K.A.</span>
          <span className="boot-sub">INITIALIZING NEURAL CORE...</span>
          <div className="boot-bar"><div className="boot-bar-fill" /></div>
        </div>
      </div>
    );
  }

  if (!currentUser) return <LoginScreen />;

  return (
    <div className="meka-app">
      {/* Persistent top bar */}
      <TopBar currentUser={currentUser} isAdmin={isAdmin} online={online} onSignOut={() => signOut(auth)} />

      {/* The 3D Orb fills the entire background */}
      <MekaOrb
        onPanelToggle={handlePanelToggle}
        currentPanel={activePanel}
        status={status}
        online={online}
      />

      {/* Panel drawer slides in from the side */}
      <PanelDrawer
        panel={activePanel}
        currentUser={currentUser}
        isAdmin={isAdmin}
        onClose={() => setActivePanel(null)}
      />
    </div>
  );
}
