#!/usr/bin/env python3
"""
Meka IoT Hub — Fallback Manager
══════════════════════════════════════════════════════════════════════

Monitors device availability and automatically switches between
network devices and local hardware. Ensures Meka always has
access to a camera, mic, and speaker — even if all network
devices go offline.

Priority order:
  1. Dedicated network devices (IP cameras, smart speakers)
  2. Meka ESP32 nodes with hardware
  3. Phone devices (via companion app/WebRTC)
  4. PC/Laptop devices (via companion agent)
  5. Local device hardware (built-in camera/mic/speaker) — LAST RESORT
"""

import time
import threading
import logging
from typing import Dict, Optional, List, Callable

from device_registry import DeviceRegistry
from camera_controller import CameraController
from audio_controller import AudioController
from config import (
    CAP_CAMERA, CAP_MICROPHONE, CAP_SPEAKER,
    FALLBACK_PRIORITY,
)

logger = logging.getLogger("meka.fallback")


class FallbackManager:
    """
    Continuously monitors device availability and handles
    automatic fallback/recovery for cameras, mics, and speakers.
    """

    def __init__(
        self,
        registry: DeviceRegistry,
        camera_ctrl: CameraController,
        audio_ctrl: AudioController,
    ):
        self._registry = registry
        self._camera = camera_ctrl
        self._audio = audio_ctrl
        self._running = False
        self._thread: Optional[threading.Thread] = None
        self._check_interval = 10  # seconds
        self._event_log: List[dict] = []
        self._max_log = 100
        self._notification_callbacks: List[Callable] = []

        # Current state tracking
        self._last_camera_state: Optional[str] = None    # mac or "local"
        self._last_mic_state: Optional[str] = None
        self._last_speaker_state: Optional[str] = None

    def on_notification(self, callback: Callable):
        """Register callback for fallback notifications."""
        self._notification_callbacks.append(callback)

    def _notify(self, message: str, severity: str = "info"):
        """Send notification about fallback change."""
        event = {
            "timestamp": time.time(),
            "message": message,
            "severity": severity,
        }
        self._event_log.append(event)
        if len(self._event_log) > self._max_log:
            self._event_log.pop(0)

        log_fn = getattr(logger, severity, logger.info)
        log_fn(f"🔄 Fallback: {message}")

        for cb in self._notification_callbacks:
            try:
                cb(event)
            except Exception:
                pass

    # ── Lifecycle ───────────────────────────────────────────────────

    def start(self):
        """Start the fallback monitoring loop."""
        if self._running:
            return

        self._running = True
        self._thread = threading.Thread(
            target=self._monitor_loop, daemon=True,
            name="fallback-monitor"
        )
        self._thread.start()
        logger.info("🔄 Fallback manager started")

    def stop(self):
        """Stop the fallback monitoring loop."""
        self._running = False
        if self._thread:
            self._thread.join(timeout=5)
        logger.info("🔄 Fallback manager stopped")

    def _monitor_loop(self):
        """Main monitoring loop — checks device availability and ESP32 hardware capability flags."""
        while self._running:
            try:
                self._sync_esp32_capabilities()
                self._check_camera_fallback()
                self._check_mic_fallback()
                self._check_speaker_fallback()
            except Exception as e:
                logger.error(f"Fallback monitor error: {e}")

            time.sleep(self._check_interval)

    def _sync_esp32_capabilities(self):
        """Inspect ESP32 nodes to see if physical mic/speaker/camera modules are attached."""
        esp_nodes = self._registry.get_devices_by_type("meka_node")
        for node in esp_nodes:
            if not node.get("online"):
                continue
            ip = node.get("ip")
            try:
                import requests
                resp = requests.get(f"http://{ip}/iot/capabilities", timeout=2)
                if resp.status_code == 200:
                    caps = resp.json()
                    has_mic = caps.get("has_mic", False)
                    has_spk = caps.get("has_speaker", False)
                    has_cam = caps.get("has_camera", False)

                    # If ESP32 does NOT have a mic attached, ensure network/phone mic fallback is active
                    if not has_mic and self._audio.get_active_mic().get("is_local"):
                        logger.info(f"ℹ️ ESP32 ({ip}) reports NO attached mic. Auto-selecting network microphone...")
                        self._audio._auto_select_mic()

                    # If ESP32 does NOT have a speaker attached, ensure network/bluetooth speaker fallback is active
                    if not has_spk and self._audio.get_active_speaker().get("is_local"):
                        logger.info(f"ℹ️ ESP32 ({ip}) reports NO attached speaker. Auto-selecting network speaker...")
                        self._audio._auto_select_speaker()

            except Exception:
                pass

    # ── Camera Fallback ─────────────────────────────────────────────

    def _check_camera_fallback(self):
        """Check if we need to switch camera sources."""
        cameras = self._registry.get_permitted_devices(CAP_CAMERA)
        online_cameras = [c for c in cameras if c.get("online")]

        if online_cameras:
            # Sort by priority
            online_cameras.sort(
                key=lambda d: FALLBACK_PRIORITY.get(d["device_type"], 50)
            )
            best = online_cameras[0]
            new_state = best["mac"]

            if new_state != self._last_camera_state:
                if self._last_camera_state == "local":
                    self._notify(
                        f"Network camera online: {best['ip']} "
                        f"({best.get('vendor', 'Unknown')}). "
                        f"Switching from local camera.",
                        "info"
                    )
                elif self._last_camera_state is not None:
                    self._notify(
                        f"Switching to better camera: {best['ip']}",
                        "info"
                    )
                self._last_camera_state = new_state
        else:
            if self._last_camera_state != "local":
                self._notify(
                    "All network cameras offline. "
                    "Falling back to local camera.",
                    "warning"
                )
                self._last_camera_state = "local"

    # ── Mic Fallback ────────────────────────────────────────────────

    def _check_mic_fallback(self):
        """Check if we need to switch mic sources."""
        mic_info = self._audio.get_active_mic()
        current_mac = mic_info.get("mac", "local")

        if current_mac != self._last_mic_state:
            if mic_info.get("is_local"):
                if self._last_mic_state and self._last_mic_state != "local":
                    self._notify(
                        "Network microphone offline. "
                        "Falling back to local mic.",
                        "warning"
                    )
            else:
                if self._last_mic_state == "local":
                    name = mic_info.get("name", "Unknown")
                    self._notify(
                        f"Network microphone available: {name}. "
                        f"Switching from local mic.",
                        "info"
                    )
            self._last_mic_state = current_mac

    # ── Speaker Fallback ────────────────────────────────────────────

    def _check_speaker_fallback(self):
        """Check if we need to switch speaker sources."""
        speaker_info = self._audio.get_active_speaker()
        current_mac = speaker_info.get("mac", "local")

        if current_mac != self._last_speaker_state:
            if speaker_info.get("is_local"):
                if (self._last_speaker_state
                        and self._last_speaker_state != "local"):
                    self._notify(
                        "Network speaker offline. "
                        "Falling back to local speaker.",
                        "warning"
                    )
            else:
                if self._last_speaker_state == "local":
                    name = speaker_info.get("name", "Unknown")
                    self._notify(
                        f"Network speaker available: {name}. "
                        f"Switching from local speaker.",
                        "info"
                    )
            self._last_speaker_state = current_mac

    # ── Status ──────────────────────────────────────────────────────

    def get_status(self) -> dict:
        """Get comprehensive fallback status."""
        mic = self._audio.get_active_mic()
        speaker = self._audio.get_active_speaker()

        cameras = self._registry.get_permitted_devices(CAP_CAMERA)
        online_cameras = [c for c in cameras if c.get("online")]

        return {
            "camera": {
                "using_local": len(online_cameras) == 0,
                "network_cameras_online": len(online_cameras),
                "network_cameras_total": len(cameras),
                "active_source": (
                    online_cameras[0]["ip"] if online_cameras
                    else "local"
                ),
            },
            "microphone": {
                "using_local": mic.get("is_local", True),
                "active_source": mic.get("ip", "local"),
                "active_name": mic.get("name", "Local Device"),
            },
            "speaker": {
                "using_local": speaker.get("is_local", True),
                "active_source": speaker.get("ip", "local"),
                "active_name": speaker.get("name", "Local Device"),
            },
            "events": self._event_log[-10:],  # Last 10 events
        }

    def get_event_log(self) -> List[dict]:
        """Get fallback event history."""
        return self._event_log.copy()
