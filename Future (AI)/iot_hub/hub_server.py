#!/usr/bin/env python3
"""
Meka IoT Hub — Main Server
══════════════════════════════════════════════════════════════════════

Flask REST API + WebSocket server that orchestrates the entire
IoT hub: network scanning, device management, camera recording,
audio routing, and fallback management.

Run with: python hub_server.py
Access at: http://localhost:5000
"""

import os
import sys
import time
import threading
import logging
import ipaddress
from typing import Optional, Dict, Any, List, Set

# ── SSL Certificate Generator ─────────────────────────────────────────
def _ensure_ssl_cert(ssl_dir: str, local_ip: str) -> tuple:
    """
    Generate valid self-signed X.509 certificate with SubjectAltName extensions
    using python's standard cryptography library.
    """
    os.makedirs(ssl_dir, exist_ok=True)
    cert_file = os.path.join(ssl_dir, "meka_hub.crt")
    key_file = os.path.join(ssl_dir, "meka_hub.key")

    if os.path.exists(cert_file) and os.path.exists(key_file):
        return cert_file, key_file

    try:
        from cryptography import x509
        from cryptography.x509.oid import NameOID
        from cryptography.hazmat.primitives import hashes
        from cryptography.hazmat.primitives.asymmetric import rsa
        from cryptography.hazmat.primitives import serialization
        import ipaddress
        import datetime

        # Generate 2048-bit RSA key
        key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        subject = issuer = x509.Name([
            x509.NameAttribute(NameOID.COMMON_NAME, local_ip),
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, "MEKA IoT Hub"),
        ])

        # SAN extensions (both IPv4 and localhost DNS)
        san_items = [
            x509.DNSName("localhost"),
            x509.DNSName("meka.local"),
            x509.IPAddress(ipaddress.ip_address("127.0.0.1")),
        ]
        try:
            san_items.append(x509.IPAddress(ipaddress.ip_address(local_ip)))
        except Exception:
            san_items.append(x509.DNSName(local_ip))

        cert = (
            x509.CertificateBuilder()
            .subject_name(subject)
            .issuer_name(issuer)
            .public_key(key.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(datetime.datetime.now(datetime.timezone.utc))
            .not_valid_after(datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=3650))
            .add_extension(x509.SubjectAlternativeName(san_items), critical=False)
            .sign(key, hashes.SHA256())
        )

        with open(key_file, "wb") as f:
            f.write(key.private_bytes(
                encoding=serialization.Encoding.PEM,
                format=serialization.PrivateFormat.TraditionalOpenSSL,
                encryption_algorithm=serialization.NoEncryption()
            ))

        with open(cert_file, "wb") as f:
            f.write(cert.public_bytes(serialization.Encoding.PEM))

        logging.getLogger("meka.hub").info(f"🔒 Standard TLS cert generated → {cert_file}")
        return cert_file, key_file
    except Exception as e:
        logging.getLogger("meka.hub").error(f"TLS cert error: {e}")
        return "adhoc", None
    return cert_file, key_file

from flask import Flask, jsonify, request, Response, send_from_directory
from flask_cors import CORS
from flask_socketio import SocketIO

from config import (
    HUB_HOST, HUB_PORT, RECORDINGS_DIR, SNAPSHOTS_DIR,
    SCAN_INTERVAL_SECONDS, DATA_DIR,
    DEVICE_TYPE_PHONE, DEVICE_TYPE_CAMERA, DEVICE_TYPE_ESP32_NODE,
    CAP_CAMERA, CAP_SPEAKER, CAP_MIC,
    PERM_GRANTED, MEKA_PRODUCT_VERSION,
)
from scanner import NetworkScanner, get_local_ip
from device_registry import DeviceRegistry
from permissions import PermissionManager
from camera_controller import CameraController
from audio_controller import AudioController
from fallback_manager import FallbackManager
from bluetooth_manager import BluetoothManager

# ══════════════════════════════════════════════════════════════════════
# Logging Setup
# ══════════════════════════════════════════════════════════════════════

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s │ %(name)-18s │ %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger("meka.hub")

# ══════════════════════════════════════════════════════════════════════
# Flask App Setup
# ══════════════════════════════════════════════════════════════════════

app = Flask(__name__, static_folder="static")
CORS(app, resources={r"/*": {"origins": "*"}}, supports_credentials=True)
socketio = SocketIO(
    app,
    cors_allowed_origins="*",
    async_mode="threading",
    ping_timeout=30,
    ping_interval=10,
    allow_unsafe_werkzeug=True,
    transports=["websocket", "polling"]
)

@app.after_request
def add_cors_headers(response):
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization, X-Requested-With"
    response.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
    return response


# ══════════════════════════════════════════════════════════════════════
# Core Services
# ══════════════════════════════════════════════════════════════════════

scanner = NetworkScanner()
registry = DeviceRegistry()
permissions = PermissionManager(registry)
camera_ctrl = CameraController(registry)
audio_ctrl = AudioController(registry)
fallback_mgr = FallbackManager(registry, camera_ctrl, audio_ctrl)
bt_mgr = BluetoothManager()
from adb_controller import AdbController
import os
adb_path = r"C:\Users\Bawantha Beliwaththa\AppData\Local\Android\Sdk\platform-tools\adb.exe"
if not os.path.exists(adb_path):
    adb_path = "adb"
adb_ctrl = AdbController(adb_path)


# ══════════════════════════════════════════════════════════════════════
# Background Scanner
# ══════════════════════════════════════════════════════════════════════

_scan_thread: Optional[threading.Thread] = None
_scan_running = False

# ── Phone Bridge Frame Store ───────────────────────────────────────────
_phone_frames: Dict[str, bytes] = {}
_phone_frames_ts: Dict[str, float] = {}


def _background_scan_loop():
    """Periodic background network scanning."""
    global _scan_running
    while _scan_running:
        try:
            _do_scan()
        except Exception as e:
            logger.error(f"Background scan error: {e}")

        # Sleep in small intervals so we can stop quickly
        for _ in range(SCAN_INTERVAL_SECONDS * 2):
            if not _scan_running:
                break
            time.sleep(0.5)


def _do_scan():
    """Execute a full scan and update the registry."""
    devices = scanner.full_scan()

    # Update registry with discovered devices
    seen_macs = []
    for dev in devices:
        data = dev.to_dict()
        registry.upsert_device(data)
        if dev.mac != "unknown":
            seen_macs.append(dev.mac)

    # Update online/offline status
    registry.update_online_status(seen_macs)

    # Broadcast update via WebSocket
    stats = registry.get_stats()
    socketio.emit("scan_complete", {
        "device_count": len(devices),
        "stats": stats,
        "timestamp": time.time(),
    })

    logger.info(f"📡 Scan synced: {len(devices)} devices → registry")


def start_background_scanner():
    """Start the periodic background scan."""
    global _scan_thread, _scan_running
    if _scan_running:
        return

    _scan_running = True
    _scan_thread = threading.Thread(
        target=_background_scan_loop, daemon=True,
        name="bg-scanner"
    )
    _scan_thread.start()
    logger.info(
        f"🔄 Background scanner started "
        f"(interval: {SCAN_INTERVAL_SECONDS}s)"
    )


def stop_background_scanner():
    """Stop the periodic background scan."""
    global _scan_running
    _scan_running = False


# ══════════════════════════════════════════════════════════════════════
# WebSocket Events
# ══════════════════════════════════════════════════════════════════════

# Track admin socket IDs and device socket IDs → real IPs
_admin_sids: set = set()
_device_sids: dict = {}   # sid → {ip, mac, caps}
_device_screen_frames: dict = {}  # ip → bytes


def _real_ip():
    """Get real client IP, respecting X-Forwarded-For from Nginx proxy."""
    xff = request.headers.get("X-Forwarded-For", "")
    if xff:
        ip = xff.split(",")[0].strip()
    else:
        ip = request.remote_addr or "0.0.0.0"
    # Normalize IPv6 loopback
    if ip in ("::1", "::ffff:127.0.0.1"):
        ip = "127.0.0.1"
    return ip


@socketio.on("connect")
def ws_connect():
    ip = _real_ip()
    logger.info(f"🔌 WebSocket connected from {ip}")
    from flask_socketio import emit
    emit("hub_status", {
        "stats": registry.get_stats(),
        "fallback": fallback_mgr.get_status(),
    })


@socketio.on("disconnect")
def ws_disconnect():
    # Remove device from active device sids
    sid = request.sid
    if sid in _device_sids:
        info = _device_sids.pop(sid)
        ip = info.get("ip")
        mac = info.get("mac")
        logger.info(f"📱 Device disconnected: {ip}")
        socketio.emit("device_disconnected", {"ip": ip, "mac": mac}, to="admin")
    _admin_sids.discard(sid)


@socketio.on("admin_join")
def ws_admin_join():
    """Admin panel joins the admin room to receive all device broadcasts."""
    from flask_socketio import join_room, emit
    join_room("admin")
    _admin_sids.add(request.sid)
    logger.info(f"👑 Admin joined room: {request.sid}")
    emit("device_list", {"devices": list(_device_sids.values())})


@socketio.on("admin_leave")
def ws_admin_leave():
    from flask_socketio import leave_room
    leave_room("admin")
    _admin_sids.discard(request.sid)


@socketio.on("request_scan")
def ws_request_scan():
    """Handle scan request from WebSocket client."""
    threading.Thread(target=_do_scan, daemon=True).start()
    socketio.emit("scan_started", {"timestamp": time.time()})


@socketio.on("message")
def ws_message(data):
    """Handle raw WebSocket messages — binary frames from phone bridge."""
    global _phone_frames, _phone_frames_ts
    ip = request.remote_addr
    if isinstance(data, (bytes, bytearray)) and data:
        _phone_frames[ip] = bytes(data)
        _phone_frames_ts[ip] = time.time()
        socketio.emit("phone_frame_broadcast", {"ip": ip, "frame": data})


@socketio.on("phone_register")
def ws_phone_register(data):
    """Phone bridge registration event."""
    ip = _real_ip()
    caps = data.get('capabilities', {})
    ua = data.get('device', 'Unknown')[:80]
    cameras = data.get('cameras', [])
    logger.info(f"📱 Phone registered: ip={ip} caps={caps}")
    
    # Store device session
    mac = f"bridge_{ip.replace('.', '_')}"
    _device_sids[request.sid] = {
        "ip": ip, "mac": mac, "ua": ua,
        "caps": caps, "cameras": cameras,
        "connected_at": time.time()
    }

    # Auto-upsert device into registry and grant permission
    registry.upsert_device({
        "mac": mac,
        "ip": ip,
        "device_type": DEVICE_TYPE_PHONE,
        "capabilities": [CAP_CAMERA, CAP_SPEAKER, CAP_MIC],
        "vendor": ua[:40],
        "permission": PERM_GRANTED,
        "online": True
    })
    permissions.grant(mac)
    
    _phone_frames_ts[ip] = time.time()
    # Notify admin of new device
    socketio.emit("device_connected", {"ip": ip, "mac": mac, "ua": ua, "caps": caps, "cameras": cameras}, to="admin")
    from flask_socketio import emit
    emit("status", {"type": "phone_registered", "ip": ip, "mac": mac})


@socketio.on("phone_audio")
def ws_phone_audio(data):
    """Receive PCM audio chunk from phone bridge and forward to admin."""
    ip = _real_ip()
    if data:
        socketio.emit("device_audio", {"ip": ip, "audio": data}, to="admin")


@socketio.on("phone_frame")
def ws_phone_frame(data):
    """Receive camera frame from phone bridge via WebSocket."""
    global _phone_frames, _phone_frames_ts
    ip = _real_ip()
    if data:
        _phone_frames[ip] = bytes(data)
        _phone_frames_ts[ip] = time.time()
        socketio.emit("phone_frame_broadcast", {"ip": ip, "frame": data})
        socketio.emit("device_camera_frame", {"ip": ip, "frame": data}, to="admin")


@socketio.on("phone_screen_frame")
def ws_phone_screen_frame(data):
    """Receive screen share frame from device and forward to admin."""
    ip = _real_ip()
    if data:
        _device_screen_frames[ip] = bytes(data)
        socketio.emit("device_screen_frame", {"ip": ip, "frame": data}, to="admin")


# ── WebRTC Signaling ────────────────────────────────────────────────────

@socketio.on("webrtc_offer")
def ws_webrtc_offer(data):
    """Device sends WebRTC offer — relay to admin room."""
    ip = _real_ip()
    mac = f"bridge_{ip.replace('.', '_')}"
    socketio.emit("webrtc_offer", {"ip": ip, "mac": mac, "sdp": data.get("sdp"), "stream_type": data.get("stream_type", "camera")}, to="admin")


@socketio.on("webrtc_answer")
def ws_webrtc_answer(data):
    """Admin sends WebRTC answer — relay to target device."""
    target_ip = data.get("target_ip")
    # Find the socket of the target device by IP
    for sid, info in _device_sids.items():
        if info.get("ip") == target_ip:
            socketio.emit("webrtc_answer", {"sdp": data.get("sdp")}, to=sid)
            break


@socketio.on("webrtc_ice")
def ws_webrtc_ice(data):
    """ICE candidate relay — can flow device↔admin in both directions."""
    target_ip = data.get("target_ip")
    if target_ip:
        for sid, info in _device_sids.items():
            if info.get("ip") == target_ip:
                socketio.emit("webrtc_ice", {"candidate": data.get("candidate")}, to=sid)
                break
    else:
        ip = _real_ip()
        mac = f"bridge_{ip.replace('.', '_')}"
        socketio.emit("webrtc_ice_from_device", {"ip": ip, "mac": mac, "candidate": data.get("candidate")}, to="admin")


@socketio.on("admin_command")
def ws_admin_command(data):
    """Admin sends command to a specific device."""
    target_ip = data.get("target_ip")
    cmd = data.get("command")
    payload = data.get("payload", {})
    logger.info(f"👑 Admin command → {target_ip}: {cmd}")
    for sid, info in _device_sids.items():
        if info.get("ip") == target_ip:
            socketio.emit("hub_command", {"type": cmd, **payload}, to=sid)
            break


# Wire up fallback notifications to WebSocket
fallback_mgr.on_notification(
    lambda event: socketio.emit("fallback_event", event)
)


# ══════════════════════════════════════════════════════════════════════
# API Routes — Hub Status
# ══════════════════════════════════════════════════════════════════════

@app.route("/api/status", methods=["GET"])
def api_status():
    """Get hub status overview."""
    return jsonify({
        "hub": "meka-iot-hub",
        "version": "1.0.0",
        "uptime_s": int(time.time() - _start_time),
        "local_ip": get_local_ip(),
        "stats": registry.get_stats(),
        "scanner": {
            "is_scanning": scanner.is_scanning,
            "scan_count": scanner.scan_count,
            "interval_s": SCAN_INTERVAL_SECONDS,
        },
        "fallback": fallback_mgr.get_status(),
    })


# ══════════════════════════════════════════════════════════════════════
# API Routes — Device Management
# ══════════════════════════════════════════════════════════════════════

@app.route("/api/devices", methods=["GET"])
def api_list_devices():
    """List all discovered devices."""
    device_type = request.args.get("type")
    capability = request.args.get("capability")
    online_only = request.args.get("online") == "true"

    if device_type:
        devices = registry.get_devices_by_type(device_type)
    elif capability:
        devices = registry.get_devices_by_capability(capability)
    else:
        devices = registry.get_all_devices()

    if online_only:
        devices = [d for d in devices if d.get("online")]

    return jsonify({
        "count": len(devices),
        "devices": devices,
    })


@app.route("/api/devices/<mac>", methods=["GET"])
def api_get_device(mac):
    """Get a specific device by MAC address."""
    device = registry.get_device(mac)
    if not device:
        return jsonify({"error": "Device not found"}), 404
    return jsonify(device)


@app.route("/api/devices/<mac>/config", methods=["POST"])
def api_configure_device(mac):
    """Update device configuration (friendly name, RTSP URL, auth)."""
    data = request.get_json(silent=True) or {}
    success = registry.set_device_config(mac, **data)
    if success:
        return jsonify({"status": "updated", "mac": mac})
    return jsonify({"error": "Failed to update"}), 400


@app.route("/api/devices/scan", methods=["POST"])
def api_trigger_scan():
    """Trigger an immediate network scan."""
    threading.Thread(target=_do_scan, daemon=True).start()
    return jsonify({
        "status": "scan_started",
        "timestamp": time.time(),
    })


# ══════════════════════════════════════════════════════════════════════
# API Routes — Permissions
# ══════════════════════════════════════════════════════════════════════

@app.route("/api/devices/<mac>/permit", methods=["POST"])
def api_permit_device(mac):
    """Grant permission to a device."""
    result = permissions.grant(mac)
    if "error" in result:
        return jsonify(result), 400
    socketio.emit("permission_changed", {"mac": mac, "permission": "granted"})
    return jsonify(result)


@app.route("/api/devices/<mac>/revoke", methods=["POST"])
def api_revoke_device(mac):
    """Revoke permission from a device."""
    result = permissions.revoke(mac)
    if "error" in result:
        return jsonify(result), 400
    socketio.emit("permission_changed", {"mac": mac, "permission": "denied"})
    return jsonify(result)


@app.route("/api/permissions", methods=["GET"])
def api_permissions_summary():
    """Get permission summary."""
    return jsonify(permissions.get_summary())


@app.route("/api/permissions/grant-all", methods=["POST"])
def api_grant_all():
    """Grant permission to all pending devices."""
    results = permissions.grant_all_pending()
    return jsonify({"results": results, "count": len(results)})


# ══════════════════════════════════════════════════════════════════════
# API Routes — Cameras
# ══════════════════════════════════════════════════════════════════════

@app.route("/api/cameras", methods=["GET"])
def api_list_cameras():
    """List all available cameras including active phone bridges and PC webcams."""
    local_ip = get_local_ip()
    port = HUB_PORT
    proto = "https" if ("--ssl" in sys.argv or "--https" in sys.argv) else "http"

    cameras = camera_ctrl.get_available_cameras()
    result = []
    for cam in cameras:
        mac = cam.get("mac", "")
        result.append({
            **cam,
            "stream_url": f"{proto}://{local_ip}:{port}/api/cameras/{mac}/stream",
            "snapshot_url": f"{proto}://{local_ip}:{port}/api/cameras/{mac}/snapshot",
        })

    # Auto-detect PC USB webcam via OpenCV
    try:
        import cv2
        cap = cv2.VideoCapture(0)
        if cap.isOpened():
            ret, _ = cap.read()
            cap.release()
            if ret:
                result.append({
                    "mac": "local_pc_cam",
                    "ip": local_ip,
                    "name": "Local PC USB Webcam",
                    "device_type": "pc_webcam",
                    "online": True,
                    "is_bridge": True,
                    "stream_url": f"{proto}://{local_ip}:{port}/phone-bridge/frame?ip=127.0.0.1",
                    "snapshot_url": f"{proto}://{local_ip}:{port}/phone-bridge/frame?ip=127.0.0.1"
                })
    except Exception:
        pass

    # Inject active phone bridges
    now = time.time()
    for ip, ts in list(_phone_frames_ts.items()):
        if now - ts < 30.0:  # Active in the last 30 seconds
            result.append({
                "mac": f"bridge_{ip.replace('.', '_')}",
                "ip": ip,
                "name": f"Phone Bridge ({ip})",
                "device_type": "phone",
                "online": True,
                "is_bridge": True,
                "stream_url": f"{proto}://{local_ip}:{port}/phone-bridge/frame?ip={ip}",
                "snapshot_url": f"{proto}://{local_ip}:{port}/phone-bridge/frame?ip={ip}"
            })

    return jsonify({
        "count": len(result),
        "cameras": result,
    })


@app.route("/api/cameras/<mac>/stream", methods=["GET"])
def api_camera_stream(mac):
    """Get MJPEG stream from a camera (for web viewing)."""
    device = registry.get_device(mac)
    if not device:
        return jsonify({"error": "Camera not found"}), 404

    return Response(
        camera_ctrl.generate_mjpeg_frames(mac),
        mimetype="multipart/x-mixed-replace; boundary=frame",
    )


@app.route("/api/cameras/<mac>/record/start", methods=["POST"])
def api_start_recording(mac):
    """Start recording from a camera."""
    data = request.get_json(silent=True) or {}
    custom_url = data.get("stream_url")
    result = camera_ctrl.start_recording(mac, custom_url)

    if "error" in result:
        return jsonify(result), 400

    socketio.emit("recording_started", {
        "mac": mac,
        "ip": result.get("camera_ip"),
    })
    return jsonify(result)


@app.route("/api/cameras/<mac>/record/stop", methods=["POST"])
def api_stop_recording(mac):
    """Stop recording from a camera."""
    result = camera_ctrl.stop_recording(mac)
    socketio.emit("recording_stopped", {
        "mac": mac,
        "result": result,
    })
    return jsonify(result)


@app.route("/api/cameras/record/start-all", methods=["POST"])
def api_start_recording_all():
    """Start recording from all cameras."""
    results = camera_ctrl.start_recording_all()
    socketio.emit("recording_all_started", {"count": len(results)})
    return jsonify({"results": results, "count": len(results)})


@app.route("/api/cameras/record/stop-all", methods=["POST"])
def api_stop_recording_all():
    """Stop all active recordings."""
    results = camera_ctrl.stop_recording_all()
    socketio.emit("recording_all_stopped", {"count": len(results)})
    return jsonify({"results": results, "count": len(results)})


@app.route("/api/cameras/<mac>/snapshot", methods=["GET"])
def api_camera_snapshot(mac):
    """Capture a snapshot from a camera."""
    result = camera_ctrl.take_snapshot(mac)
    if "error" in result:
        return jsonify(result), 400

    # Return the image file
    if "file_path" in result:
        directory = os.path.dirname(result["file_path"])
        filename = os.path.basename(result["file_path"])
        return send_from_directory(directory, filename, mimetype="image/jpeg")

    return jsonify(result)


@app.route("/api/cameras/recording-status", methods=["GET"])
def api_recording_status():
    """Get status of all active recordings."""
    return jsonify(camera_ctrl.get_recording_status())


# ══════════════════════════════════════════════════════════════════════
# API Routes — Recordings
# ══════════════════════════════════════════════════════════════════════

@app.route("/api/recordings", methods=["GET"])
def api_list_recordings():
    """List all saved recordings."""
    camera_mac = request.args.get("camera")
    limit = int(request.args.get("limit", 50))
    recordings = camera_ctrl.get_recordings_list(camera_mac)
    return jsonify({
        "count": len(recordings),
        "recordings": recordings[:limit],
    })


@app.route("/api/recordings/<int:recording_id>/download", methods=["GET"])
def api_download_recording(recording_id):
    """Download a recording file."""
    recordings = registry.get_recordings()
    for rec in recordings:
        if rec["id"] == recording_id:
            path = rec["file_path"]
            if os.path.exists(path):
                directory = os.path.dirname(path)
                filename = os.path.basename(path)
                return send_from_directory(
                    directory, filename,
                    as_attachment=True,
                    mimetype="video/mp4"
                )
    return jsonify({"error": "Recording not found"}), 404


# ══════════════════════════════════════════════════════════════════════
# API Routes — Audio Routing
# ══════════════════════════════════════════════════════════════════════

@app.route("/api/audio/microphones", methods=["GET"])
def api_list_microphones():
    """List available microphones."""
    return jsonify({
        "microphones": audio_ctrl.get_available_microphones(),
    })


@app.route("/api/speakers", methods=["GET"])
@app.route("/api/audio/speakers", methods=["GET"])
def api_list_speakers():
    """List available speakers."""
    return jsonify({
        "speakers": audio_ctrl.get_available_speakers(),
    })


@app.route("/api/audio/mic/select", methods=["POST"])
def api_select_mic():
    """Select active microphone."""
    data = request.get_json(silent=True) or {}
    mac = data.get("mac", "")
    if mac == "local":
        result = audio_ctrl.select_local_mic()
    else:
        result = audio_ctrl.select_mic(mac)

    if "error" in result:
        return jsonify(result), 400

    socketio.emit("mic_changed", result)
    return jsonify(result)


@app.route("/api/audio/speaker/select", methods=["POST"])
def api_select_speaker():
    """Select active speaker."""
    data = request.get_json(silent=True) or {}
    mac = data.get("mac", "")
    if mac == "local":
        result = audio_ctrl.select_local_speaker()
    else:
        result = audio_ctrl.select_speaker(mac)

    if "error" in result:
        return jsonify(result), 400

    socketio.emit("speaker_changed", result)
    return jsonify(result)


@app.route("/api/audio/fallback", methods=["GET"])
def api_audio_fallback():
    """Get fallback status."""
    return jsonify(audio_ctrl.get_fallback_status())


@app.route("/api/audio/play", methods=["POST"])
def api_audio_play():
    """
    Broadcast TTS or audio URL to connected phone bridge speakers.
    Body: { "text": "Hello", "mac": "optional-specific-speaker-mac" }
    """
    data = request.get_json(silent=True) or {}
    text = data.get("text", "").strip()
    audio_url = data.get("audio_url", "").strip()
    target_mac = data.get("mac", None)  # None = broadcast to all

    if not text and not audio_url:
        return jsonify({"error": "Provide 'text' or 'audio_url'"}), 400

    payload = {"type": "tts" if text else "play_audio"}
    if text:
        payload["text"] = text
    if audio_url:
        payload["audio_url"] = audio_url

    # Broadcast to all connected phone clients via WebSocket
    socketio.emit("hub_command", payload)
    logger.info(f"🔊 Audio broadcast: {payload}")

    return jsonify({"status": "broadcast", "payload": payload})


@app.route("/api/cameras/all-streams", methods=["GET"])
def api_all_camera_streams():
    """
    Return all discovered cameras with their live stream URLs.
    Used by the web admin panel camera grid.
    """
    local_ip = get_local_ip()
    port = HUB_PORT
    proto = "https" if ("--ssl" in sys.argv or "--https" in sys.argv) else "http"

    cameras = camera_ctrl.get_available_cameras()
    result = []
    for cam in cameras:
        mac = cam.get("mac", "")
        result.append({
            **cam,
            "stream_url": f"{proto}://{local_ip}:{port}/api/cameras/{mac}/stream",
            "snapshot_url": f"{proto}://{local_ip}:{port}/api/cameras/{mac}/snapshot",
        })

    # Inject active phone bridges
    now = time.time()
    for ip, ts in _phone_frames_ts.items():
        if now - ts < 10.0:  # Active in the last 10 seconds (generous for newly registered)
            result.append({
                "mac": f"bridge_{ip.replace('.', '_')}",
                "ip": ip,
                "name": f"Phone Bridge ({ip})",
                "device_type": "phone",
                "online": True,
                "is_bridge": True
            })

    return jsonify({"count": len(result), "cameras": result})


@app.route("/api/cameras/start-all", methods=["POST"])
def api_start_all_cameras():
    """
    Start all cameras on the Wi-Fi network.
    - IP Cameras & ESP32-CAMs: Automatically granted permission and connected.
    - Laptops & Mobile devices: Sends remote permission popup overlay request to device screens.
    """
    all_devices = registry.get_all_devices()
    auto_ip_cams = []
    prompted_devices = []

    for dev in all_devices:
        mac = dev.get("mac", "")
        ip = dev.get("ip", "")
        dev_type = dev.get("device_type", "").lower()
        vendor = dev.get("vendor", "").lower()

        # IP camera / ESP32-CAM check
        if dev_type == DEVICE_TYPE_CAMERA or "camera" in vendor or "esp32" in vendor:
            permissions.grant(mac)
            auto_ip_cams.append({"mac": mac, "ip": ip, "type": dev_type})
        else:
            # Laptop / Phone / PC -> Trigger permission popup on screen
            prompted_devices.append({"mac": mac, "ip": ip, "type": dev_type})

    # Broadcast remote permission popup to all laptops & phones on the Wi-Fi network
    payload = {
        "type": "show_permission_popup",
        "force_camera": True,
        "message": "MEKA requests camera access from all Wi-Fi network devices"
    }
    socketio.emit("hub_command", payload)
    logger.info(f"📡 Start All Cameras broadcasted: {len(prompted_devices)} popups, {len(auto_ip_cams)} IP cams")

    return jsonify({
        "status": "broadcast_complete",
        "auto_connected_ip_cameras": auto_ip_cams,
        "prompted_devices": prompted_devices,
        "message": f"Requested access from {len(prompted_devices)} devices; auto-connected {len(auto_ip_cams)} IP cameras."
    })


@app.route("/api/cameras/<mac>/control", methods=["POST"])
def api_camera_control(mac):

    """
    Control a camera node (e.g. flip camera front/rear, toggle stream).
    Body: { "action": "flip" | "toggle" }
    """
    data = request.get_json(silent=True) or {}
    action = data.get("action", "").lower()
    if not action:
        return jsonify({"error": "Action required ('flip' or 'toggle')"}), 400

    payload = {"type": "camera_control", "action": action, "mac": mac}
    socketio.emit("hub_command", payload)
    logger.info(f"📷 Camera control command: {payload}")
    return jsonify({"status": "command_sent", "mac": mac, "action": action})


@app.route("/api/audio/speaker/<mac>/control", methods=["POST"])
def api_speaker_control(mac):
    """
    Control a speaker node (e.g. test beep tone, set volume, speak text).
    Body: { "action": "beep" | "volume" | "speak", "volume": 0.8, "text": "..." }
    """
    data = request.get_json(silent=True) or {}
    action = data.get("action", "").lower()
    if not action:
        return jsonify({"error": "Action required ('beep', 'volume', or 'speak')"}), 400

    payload = {
        "type": "speaker_control" if action in ["beep", "volume"] else "tts",
        "action": action,
        "mac": mac,
        "volume": data.get("volume"),
        "text": data.get("text"),
    }
    socketio.emit("hub_command", payload)
    logger.info(f"🔊 Speaker control command: {payload}")
    return jsonify({"status": "command_sent", "mac": mac, "action": action})


@app.route("/api/audio/tts", methods=["POST"])
def api_audio_tts():
    """
    Broadcast TTS (Text-To-Speech) to connected phone bridges and speaker nodes.
    Body: { "text": "...", "output_mac": "all" | "<specific_mac>", "volume": 0.8 }
    The phone bridge will receive this as a 'tts' socket event and speak it using Web Speech API.
    """
    data = request.get_json(silent=True) or {}
    text = data.get("text", "").strip()
    output_mac = data.get("output_mac", "all")
    volume = data.get("volume", 1.0)

    if not text:
        return jsonify({"error": "text required"}), 400

    payload = {
        "type": "tts",
        "text": text,
        "volume": volume,
        "output_mac": output_mac,
    }
    socketio.emit("hub_command", payload)
    logger.info(f"🔊 TTS broadcast: '{text[:60]}...' → output_mac={output_mac}")
    return jsonify({"status": "tts_broadcast", "text_length": len(text), "output_mac": output_mac})


# ══════════════════════════════════════════════════════════════════════
# API Routes — Permission System
# ══════════════════════════════════════════════════════════════════════


@app.route("/api/permissions", methods=["GET"])
def api_get_permissions():
    """Get overall device permission summary & pending devices."""
    summary = permissions.get_summary()
    all_devices = registry.get_all_devices()
    return jsonify({
        "summary": summary,
        "devices": all_devices,
    })


@app.route("/api/permissions/grant", methods=["POST"])
def api_grant_permission():
    """
    Grant permission to a device.
    Body: { "mac": "..." } or auto-detects requesting IP.
    """
    data = request.get_json(silent=True) or {}
    mac = data.get("mac")

    # If MAC not passed, lookup device by remote IP address
    if not mac:
        client_ip = request.remote_addr
        dev = registry.get_device_by_ip(client_ip)
        if dev:
            mac = dev["mac"]
        else:
            # Register a temporary device for this IP
            mac = f"ip_{client_ip.replace('.', '_')}"
            registry.upsert_device(
                mac=mac, ip=client_ip,
                device_type=DEVICE_TYPE_PHONE,
                capabilities=data.get("capabilities", [CAP_CAMERA, CAP_SPEAKER]),
                vendor="Web Wi-Fi Client",
                permission=PERM_GRANTED,
                online=True
            )

    if mac:
        res = permissions.grant(mac)
        socketio.emit("permission_updated", {"mac": mac, "status": "granted"})
        return jsonify(res)

    return jsonify({"error": "Could not identify device MAC or IP"}), 400


@app.route("/api/permissions/deny", methods=["POST"])
def api_deny_permission():
    """
    Deny / Revoke permission for a device.
    Body: { "mac": "..." }
    """
    data = request.get_json(silent=True) or {}
    mac = data.get("mac")
    if not mac:
        client_ip = request.remote_addr
        dev = registry.get_device_by_ip(client_ip)
        if dev:
            mac = dev["mac"]

    if mac:
        res = permissions.revoke(mac)
        socketio.emit("permission_updated", {"mac": mac, "status": "denied"})
        return jsonify(res)

    return jsonify({"error": "MAC required"}), 400


@app.route("/api/permissions/prompt/<mac>", methods=["POST"])
def api_prompt_permission(mac):
    """
    Remotely trigger the Permission Request Popup on a specific device screen via WebSocket.
    """
    payload = {"type": "show_permission_popup", "mac": mac}
    socketio.emit("hub_command", payload)
    logger.info(f"📲 Permission popup request sent to {mac}")
    return jsonify({"status": "prompt_sent", "mac": mac})


# ══════════════════════════════════════════════════════════════════════
# API Routes — Fallback & Events
# ══════════════════════════════════════════════════════════════════════



@app.route("/api/fallback/status", methods=["GET"])
def api_fallback_status():
    """Get comprehensive fallback status."""
    return jsonify(fallback_mgr.get_status())


@app.route("/api/fallback/events", methods=["GET"])
def api_fallback_events():
    """Get fallback event log."""
    return jsonify({
        "events": fallback_mgr.get_event_log(),
    })


# ══════════════════════════════════════════════════════════════════════
# API Routes — Bluetooth Management
# ══════════════════════════════════════════════════════════════════════

@app.route("/api/bluetooth/scan", methods=["GET", "POST"])
def api_bluetooth_scan():
    """Scan for nearby Bluetooth devices."""
    devices = bt_mgr.scan_devices()
    return jsonify({
        "count": len(devices),
        "devices": devices,
    })


@app.route("/api/bluetooth/connect", methods=["POST"])
def api_bluetooth_connect():
    """Connect to a Bluetooth device."""
    data = request.get_json(silent=True) or {}
    mac_or_id = data.get("mac", "") or data.get("id", "")
    if not mac_or_id:
        return jsonify({"error": "Device MAC or ID required"}), 400

    res = bt_mgr.connect_device(mac_or_id)
    socketio.emit("bluetooth_device_connected", res)
    return jsonify(res)


@app.route("/api/bluetooth/devices", methods=["GET"])
def api_bluetooth_devices():
    """Get list of Bluetooth devices."""
    return jsonify({
        "devices": bt_mgr.get_devices(),
    })


# ══════════════════════════════════════════════════════════════════════
# API Routes — Audit Log
# ══════════════════════════════════════════════════════════════════════

@app.route("/api/audit", methods=["GET"])
def api_audit_log():
    """Get audit log."""
    limit = int(request.args.get("limit", 100))
    return jsonify({
        "log": registry.get_audit_log(limit),
    })


# ══════════════════════════════════════════════════════════════════════
# API Routes — ESP32 Node Management (MEKA Product Nodes)
# ══════════════════════════════════════════════════════════════════════

# In-memory store for latest telemetry from each ESP32 node
_esp32_telemetry: Dict[str, Dict] = {}    # mac → {temp, humidity, ldr, ts}
_esp32_nodes: Dict[str, Dict] = {}        # mac → node metadata


@app.route("/api/esp32/register", methods=["POST"])
def api_esp32_register():
    """
    ESP32 firmware calls this on boot to self-register with the hub.
    Body: {
        "mac": "AA:BB:CC:DD:EE:FF",
        "name": "Living Room Node",
        "node_id": "MEKA-001",
        "firmware": "3.0.1",
        "capabilities": ["led", "servo", "buzzer", "sensor", "display"],
        "ip": "192.168.1.xx"   (optional, hub detects from request)
    }
    """
    data = request.get_json(silent=True) or {}
    mac = data.get("mac", "").strip().upper()
    node_name = data.get("name", f"MEKA Node ({mac[-5:]})")
    node_id = data.get("node_id", mac)
    firmware = data.get("firmware", "unknown")
    capabilities = data.get("capabilities", ["led", "sensor", "display"])
    ip = data.get("ip") or request.remote_addr

    if not mac:
        return jsonify({"error": "mac required"}), 400

    node_info = {
        "mac": mac,
        "ip": ip,
        "name": node_name,
        "node_id": node_id,
        "firmware": firmware,
        "capabilities": capabilities,
        "device_type": DEVICE_TYPE_ESP32_NODE,
        "online": True,
        "permission": PERM_GRANTED,
        "registered_at": time.time(),
        "last_seen": time.time(),
    }

    # Upsert into registry and auto-grant permission (it's a MEKA product)
    registry.upsert_device(node_info)
    permissions.grant(mac)

    # Cache in memory for quick access
    _esp32_nodes[mac] = node_info

    logger.info(f"🤖 ESP32 Node registered: {node_name} ({mac}) @ {ip} fw={firmware}")
    socketio.emit("esp32_node_registered", node_info)

    return jsonify({
        "status": "registered",
        "mac": mac,
        "name": node_name,
        "hub_time": time.time(),
        "product_version": MEKA_PRODUCT_VERSION,
    })


@app.route("/api/esp32/nodes", methods=["GET"])
def api_esp32_list_nodes():
    """List all registered ESP32 MEKA product nodes with their status and latest telemetry."""
    nodes = registry.get_devices_by_type(DEVICE_TYPE_ESP32_NODE)

    # Enrich with latest telemetry and online status from in-memory cache
    for node in nodes:
        mac = node.get("mac", "")
        tel = _esp32_telemetry.get(mac, {})
        node["telemetry"] = tel
        # Mark offline if no heartbeat in 90 seconds
        if mac in _esp32_nodes:
            last_seen = _esp32_nodes[mac].get("last_seen", 0)
            node["online"] = (time.time() - last_seen) < 90

    return jsonify({
        "count": len(nodes),
        "nodes": nodes,
    })


@app.route("/api/esp32/<mac>/telemetry", methods=["GET", "POST"])
def api_esp32_telemetry(mac):
    """
    GET  — Return latest telemetry (temp, humidity, ldr, uptime) from an ESP32 node.
    POST — ESP32 pushes telemetry to hub.
           Body: { "temp": 24.5, "humidity": 65.2, "ldr": 512, "uptime_ms": 120000 }
    """
    mac = mac.upper()
    if request.method == "POST":
        data = request.get_json(silent=True) or {}
        _esp32_telemetry[mac] = {
            **data,
            "mac": mac,
            "ts": time.time(),
        }
        # Update last_seen
        if mac in _esp32_nodes:
            _esp32_nodes[mac]["last_seen"] = time.time()
        # Broadcast to connected admin/web clients
        socketio.emit("esp32_telemetry", _esp32_telemetry[mac])
        return jsonify({"status": "received"})
    else:
        tel = _esp32_telemetry.get(mac)
        if not tel:
            return jsonify({"error": "No telemetry received yet from this node"}), 404
        return jsonify(tel)


@app.route("/api/esp32/<mac>/command", methods=["POST"])
def api_esp32_command(mac):
    """
    Send a hardware command to a specific ESP32 node via Firebase state mutation.
    The ESP32 firmware listens to Firebase and reacts within ~50ms.

    Body examples:
        { "action": "led", "color": "yellow", "state": "on" }
        { "action": "led", "color": "all", "state": "off" }
        { "action": "servo", "angle": 90 }
        { "action": "buzzer", "pattern": "beep" }
        { "action": "buzzer", "pattern": "alert" }
        { "action": "lcd", "line1": "Hello", "line2": "World" }
    """
    mac = mac.upper()
    data = request.get_json(silent=True) or {}
    action = data.get("action", "").lower()

    if not action:
        return jsonify({"error": "action required (led/servo/buzzer/lcd)"}), 400

    valid_actions = {"led", "servo", "buzzer", "lcd", "restart", "reset"}
    if action not in valid_actions:
        return jsonify({"error": f"Unknown action '{action}'. Valid: {valid_actions}"}), 400

    command_payload = {
        "type": "esp32_command",
        "mac": mac,
        "action": action,
        **{k: v for k, v in data.items() if k != "action"},
        "ts": time.time(),
    }

    # Emit via WebSocket to any connected ESP32 bridge agent, AND broadcast to all admin panels
    socketio.emit("esp32_command", command_payload)
    socketio.emit("esp32_command", command_payload, to="admin")

    logger.info(f"🤖 ESP32 command → {mac}: {action} {data}")
    return jsonify({
        "status": "command_sent",
        "mac": mac,
        "action": action,
        "payload": command_payload,
    })


@app.route("/api/esp32/<mac>/heartbeat", methods=["POST"])
def api_esp32_heartbeat(mac):
    """
    ESP32 sends a heartbeat every 30s to indicate it is online.
    Body: { "uptime_ms": 120000, "free_heap": 240000 }
    """
    mac = mac.upper()
    data = request.get_json(silent=True) or {}
    now = time.time()

    if mac in _esp32_nodes:
        _esp32_nodes[mac]["last_seen"] = now
    else:
        # Node not registered yet, create minimal entry
        ip = request.remote_addr
        _esp32_nodes[mac] = {
            "mac": mac, "ip": ip, "name": f"MEKA Node ({mac[-5:]})",
            "device_type": DEVICE_TYPE_ESP32_NODE,
            "online": True, "last_seen": now,
        }

    # Update registry online flag
    registry.upsert_device({"mac": mac, "online": True, "last_seen": now})

    socketio.emit("esp32_heartbeat", {
        "mac": mac,
        "uptime_ms": data.get("uptime_ms"),
        "free_heap": data.get("free_heap"),
        "ts": now,
    })

    return jsonify({"status": "ok", "hub_time": now})


# ══════════════════════════════════════════════════════════════════════
# Root Page
# ══════════════════════════════════════════════════════════════════════

@app.route("/")
def index():
    """Hub landing page."""
    html = """<!DOCTYPE html>
<html>
<head>
    <title>MEKA IoT Hub</title>
    <style>
        body {
            background: #010409;
            color: #00D4FF;
            font-family: 'Courier New', monospace;
            padding: 2rem;
            max-width: 800px;
            margin: 0 auto;
        }
        h1 { color: #7C4DFF; }
        a { color: #00D4FF; }
        .endpoint {
            background: rgba(255,255,255,0.05);
            padding: 8px 16px;
            margin: 4px 0;
            border-radius: 4px;
            border-left: 3px solid #7C4DFF;
        }
        .method { color: #00E676; font-weight: bold; }
    </style>
</head>
<body>
    <h1>🤖 MEKA IoT Hub v1.0</h1>
    <p>Network device management, camera recording, and audio routing.</p>

    <h2>📡 API Endpoints</h2>

    <h3>Hub</h3>
    <div class="endpoint"><span class="method">GET</span> <a href="/api/status">/api/status</a></div>

    <h3>Devices</h3>
    <div class="endpoint"><span class="method">GET</span> <a href="/api/devices">/api/devices</a></div>
    <div class="endpoint"><span class="method">POST</span> /api/devices/scan</div>
    <div class="endpoint"><span class="method">POST</span> /api/devices/{mac}/permit</div>
    <div class="endpoint"><span class="method">POST</span> /api/devices/{mac}/revoke</div>

    <h3>Cameras</h3>
    <div class="endpoint"><span class="method">GET</span> <a href="/api/cameras">/api/cameras</a></div>
    <div class="endpoint"><span class="method">GET</span> /api/cameras/{mac}/stream</div>
    <div class="endpoint"><span class="method">POST</span> /api/cameras/{mac}/record/start</div>
    <div class="endpoint"><span class="method">POST</span> /api/cameras/{mac}/record/stop</div>
    <div class="endpoint"><span class="method">POST</span> /api/cameras/record/start-all</div>
    <div class="endpoint"><span class="method">POST</span> /api/cameras/record/stop-all</div>
    <div class="endpoint"><span class="method">GET</span> /api/cameras/{mac}/snapshot</div>

    <h3>Audio</h3>
    <div class="endpoint"><span class="method">GET</span> <a href="/api/audio/microphones">/api/audio/microphones</a></div>
    <div class="endpoint"><span class="method">GET</span> <a href="/api/audio/speakers">/api/audio/speakers</a></div>
    <div class="endpoint"><span class="method">POST</span> /api/audio/mic/select</div>
    <div class="endpoint"><span class="method">POST</span> /api/audio/speaker/select</div>
    <div class="endpoint"><span class="method">GET</span> <a href="/api/audio/fallback">/api/audio/fallback</a></div>

    <h3>Recordings</h3>
    <div class="endpoint"><span class="method">GET</span> <a href="/api/recordings">/api/recordings</a></div>

    <h3>Phone Bridge</h3>
    <div class="endpoint"><span class="method">GET</span> <a href="/phone-bridge">/phone-bridge</a></div>

    <h3>System</h3>
    <div class="endpoint"><span class="method">GET</span> <a href="/api/permissions">/api/permissions</a></div>
    <div class="endpoint"><span class="method">GET</span> <a href="/api/fallback/status">/api/fallback/status</a></div>
    <div class="endpoint"><span class="method">GET</span> <a href="/api/audit">/api/audit</a></div>
</body>
</html>"""
    return html


@app.route("/phone-bridge")
@app.route("/static/phone_bridge.html")
def phone_bridge_page():
    """Serve the Phone Bridge web app."""
    static_dir = os.path.join(os.path.dirname(__file__), "static")
    return send_from_directory(static_dir, "phone_bridge.html")


@app.route("/camera-viewer")
@app.route("/static/camera_viewer.html")
def camera_viewer_page():
    """Serve the dedicated Telegram MiniApp Camera Viewer."""
    static_dir = os.path.join(os.path.dirname(__file__), "static")
    return send_from_directory(static_dir, "camera_viewer.html")



@app.route("/api/phone/frame", methods=["POST"])
def api_phone_frame():
    """Receive frame uploads from Phone Bridge HTTP fallback."""
    global _phone_frames, _phone_frames_ts
    ip = request.remote_addr
    frame_bytes = request.data
    if frame_bytes:
        _phone_frames[ip] = frame_bytes
        _phone_frames_ts[ip] = time.time()
        return jsonify({"status": "received", "size": len(frame_bytes)})
    return jsonify({"error": "No frame data"}), 400



# ══════════════════════════════════════════════════════════════════════
# API Routes — ADB (Android Debug Bridge)
# ══════════════════════════════════════════════════════════════════════

import urllib.parse

@app.route("/api/adb/devices", methods=["GET"])
def api_adb_devices():
    """List all connected ADB devices."""
    devices = adb_ctrl.list_devices()
    return jsonify({
        "count": len(devices),
        "devices": devices,
        "paired": adb_ctrl.get_paired_devices()
    })

@app.route("/api/adb/pair", methods=["POST"])
def api_adb_pair():
    """Pair with an Android 11+ device using wireless debugging pairing code."""
    data = request.get_json(silent=True) or {}
    ip = data.get("ip")
    pair_port = int(data.get("pair_port", 0))
    code = str(data.get("code", "")).strip()

    if not ip or not pair_port or not code:
        return jsonify({"error": "Missing required fields: ip, pair_port, code"}), 400

    res = adb_ctrl.pair(ip, pair_port, code)
    if "error" in res:
        return jsonify(res), 400
    return jsonify(res)

@app.route("/api/adb/connect", methods=["POST"])
def api_adb_connect():
    """Connect to an ADB device over WiFi."""
    data = request.get_json(silent=True) or {}
    host = data.get("host")
    if not host:
        return jsonify({"error": "Host required (e.g. 192.168.1.100:5555)"}), 400
    
    parts = host.split(":")
    ip = parts[0]
    port = int(parts[1]) if len(parts) > 1 else 5555
    
    success = adb_ctrl.connect(ip, port)
    if success:
        return jsonify({"status": "connected", "host": host})
    return jsonify({"error": f"Failed to connect to {host}"}), 400

@app.route("/api/adb/auto-reconnect", methods=["POST"])
def api_adb_auto_reconnect():
    """Auto-reconnect all previously paired WiFi devices."""
    reconnected = adb_ctrl.auto_reconnect()
    return jsonify({"status": "complete", "reconnected": reconnected})

@app.route("/api/adb/<path:serial>/info", methods=["GET"])
def api_adb_info(serial):
    """Get detailed hardware & OS information for an ADB device."""
    serial = urllib.parse.unquote(serial)
    info = adb_ctrl.get_device_info(serial)
    return jsonify(info)

@app.route("/api/adb/<path:serial>/shell", methods=["POST"])
def api_adb_shell(serial):
    """Execute a shell command on an ADB device."""
    serial = urllib.parse.unquote(serial)
    data = request.get_json(silent=True) or {}
    command = data.get("command")
    if not command:
        return jsonify({"error": "Command required"}), 400
        
    output = adb_ctrl.execute_shell(serial, command)
    return jsonify({"serial": serial, "command": command, "output": output})

@app.route("/api/adb/<path:serial>/screenshot", methods=["GET"])
def api_adb_screenshot(serial):
    """Take a screenshot of an ADB device."""
    serial = urllib.parse.unquote(serial)
    b64_image = adb_ctrl.screenshot(serial)
    if not b64_image:
        return jsonify({"error": "Failed to capture screenshot"}), 500
        
    import base64
    img_data = base64.b64decode(b64_image)
    return Response(img_data, mimetype="image/png")

@app.route("/api/adb/<path:serial>/unlock", methods=["POST"])
def api_adb_unlock(serial):
    """Wake up and unlock an ADB device (with optional PIN bypass)."""
    serial = urllib.parse.unquote(serial)
    data = request.get_json(silent=True) or {}
    pin = data.get("pin")
    success = adb_ctrl.unlock(serial, pin=pin)
    if success:
        return jsonify({"status": "unlocked", "serial": serial})
    return jsonify({"error": "Failed to unlock device"}), 500

@app.route("/api/adb/<path:serial>/install", methods=["POST"])
def api_adb_install(serial):
    """Install an APK on an ADB device."""
    serial = urllib.parse.unquote(serial)
    data = request.get_json(silent=True) or {}
    apk_path = data.get("apk_path")
    if not apk_path:
        return jsonify({"error": "apk_path required"}), 400
    res = adb_ctrl.install_apk(serial, apk_path)
    if "error" in res:
        return jsonify(res), 400
    return jsonify(res)

@app.route("/api/adb/<path:serial>/mirror/start", methods=["POST"])
def api_adb_mirror_start(serial):
    """Start scrcpy desktop screen mirror or web stream."""
    serial = urllib.parse.unquote(serial)
    data = request.get_json(silent=True) or {}
    web_mode = data.get("web", False)
    if web_mode:
        adb_ctrl.start_screenshot_stream(serial)
        return jsonify({"status": "web_mirror_started", "serial": serial})
    res = adb_ctrl.start_mirror(serial)
    if "error" in res:
        return jsonify(res), 400
    return jsonify(res)

@app.route("/api/adb/<path:serial>/mirror/stop", methods=["POST"])
def api_adb_mirror_stop(serial):
    """Stop scrcpy desktop screen mirror or web stream."""
    serial = urllib.parse.unquote(serial)
    adb_ctrl.stop_screenshot_stream(serial)
    res = adb_ctrl.stop_mirror(serial)
    return jsonify(res)

@app.route("/api/adb/<path:serial>/disconnect", methods=["POST"])
def api_adb_disconnect(serial):
    """Disconnect an ADB device."""
    serial = urllib.parse.unquote(serial)
    success = adb_ctrl.disconnect(serial)
    if success:
        return jsonify({"status": "disconnected", "serial": serial})
    return jsonify({"error": "Failed to disconnect"}), 500





@app.route("/phone-bridge/frame", methods=["GET"])
def api_phone_latest_frame():
    """Return the latest frame received from the phone bridge as a JPEG image."""
    ip = request.args.get("ip")
    if not ip:
        # Fallback to the most recently active bridge if no IP provided
        if not _phone_frames_ts:
            return jsonify({"error": "No bridge active"}), 404
        ip = max(_phone_frames_ts.items(), key=lambda x: x[1])[0]

    frame = _phone_frames.get(ip)
    ts = _phone_frames_ts.get(ip, 0)
    
    if not frame:
        return jsonify({"error": f"No frame available for {ip}. Open /phone-bridge on that device."}), 404
        
    return Response(
        frame,
        mimetype="image/jpeg",
        headers={"X-Frame-Age": str(int(time.time() - ts))}
    )


# ══════════════════════════════════════════════════════════════════════
# Main Entry Point
# ══════════════════════════════════════════════════════════════════════

_start_time = time.time()


def main():
    """Start the Meka IoT Hub."""
    if hasattr(sys.stdout, 'reconfigure'):
        try:
            sys.stdout.reconfigure(encoding='utf-8', errors='replace')
        except Exception:
            pass

    print()
    print("======================================================")
    print("           MEKA IoT Hub v1.0 — Starting...           ")
    print("======================================================")
    print()

    local_ip = get_local_ip()
    logger.info(f"🌐 Local IP: {local_ip}")
    logger.info(f"📂 Data dir: {DATA_DIR}")
    logger.info(f"🎥 Recordings: {RECORDINGS_DIR}")
    logger.info(f"📸 Snapshots: {SNAPSHOTS_DIR}")

    # Start background services
    start_background_scanner()
    fallback_mgr.start()
    
    # Auto-reconnect all previously paired WiFi ADB devices
    logger.info("🔄 Auto-reconnecting paired ADB WiFi devices...")
    threading.Thread(target=adb_ctrl.auto_reconnect, daemon=True).start()

    # Run initial scan
    logger.info("Running initial network scan...")
    threading.Thread(target=_do_scan, daemon=True).start()

    use_ssl = "--ssl" in sys.argv or "--https" in sys.argv
    proto = "https" if use_ssl else "http"
    ws_proto = "wss" if use_ssl else "ws"

    print()
    print(f"  🚀 Hub API:   {proto}://{local_ip}:{HUB_PORT}")
    print(f"  🚀 Local:     {proto}://localhost:{HUB_PORT}")
    print(f"  📡 WebSocket: {ws_proto}://{local_ip}:{HUB_PORT}")
    print(f"  📱 Phone:     {proto}://{local_ip}:{HUB_PORT}/phone-bridge")
    print()

    run_kwargs = {
        "host": HUB_HOST,
        "port": HUB_PORT,
        "debug": False,
        "allow_unsafe_werkzeug": True,
    }
    if use_ssl:
        cert_file, key_file = _ensure_ssl_cert(DATA_DIR, local_ip)
        if cert_file == "adhoc" or key_file is None:
            run_kwargs["ssl_context"] = "adhoc"
            logger.info("🔒 HTTPS SSL Mode ENABLED (adhoc cert — install pyopenssl for better cert)")
        else:
            run_kwargs["ssl_context"] = (cert_file, key_file)
            logger.info(f"🔒 HTTPS SSL Mode ENABLED — cert: {cert_file}")

    try:
        socketio.run(app, **run_kwargs)
    except KeyboardInterrupt:
        print("\n\n🛑 Shutting down Meka IoT Hub...")
    finally:
        stop_background_scanner()
        fallback_mgr.stop()
        # Stop any active recordings
        camera_ctrl.stop_recording_all()
        logger.info("✅ Hub shutdown complete")


if __name__ == "__main__":
    main()
