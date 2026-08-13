#!/usr/bin/env python3
"""
Meka IoT Hub — Audio Controller
══════════════════════════════════════════════════════════════════════

Manages microphone and speaker routing across network devices.
Implements smart fallback: if no external device is available,
falls back to the local device's hardware.
"""

import time
import logging
from typing import Optional, List, Dict

from device_registry import DeviceRegistry
from config import (
    CAP_MICROPHONE, CAP_SPEAKER,
    PERM_GRANTED,
    DEVICE_TYPE_CAMERA, DEVICE_TYPE_PHONE, DEVICE_TYPE_PC,
    DEVICE_TYPE_MEKA_NODE, DEVICE_TYPE_SPEAKER,
    FALLBACK_PRIORITY,
)

logger = logging.getLogger("meka.audio")


class AudioController:
    """
    Routes microphone input and speaker output across network devices.

    Fallback hierarchy:
      1. Dedicated network devices (speakers, mic arrays)
      2. Meka ESP32 nodes with audio hardware
      3. Phone cameras/mics (via companion app)
      4. PC/Laptop webcam mics and speakers (via companion agent)
      5. Local device hardware (this device's own mic/speaker) — LAST RESORT
    """

    def __init__(self, registry: DeviceRegistry):
        self._registry = registry
        self._selected_mic: Optional[str] = None      # MAC of selected mic
        self._selected_speaker: Optional[str] = None   # MAC of selected speaker
        self._use_local_mic = False
        self._use_local_speaker = False
        self._callbacks: List[callable] = []

    def on_source_change(self, callback: callable):
        """Register callback for when audio source changes."""
        self._callbacks.append(callback)

    def _notify(self, change_type: str, device_mac: str, is_local: bool):
        for cb in self._callbacks:
            try:
                cb(change_type, device_mac, is_local)
            except Exception as e:
                logger.error(f"Audio callback error: {e}")

    # ── Microphone Management ───────────────────────────────────────

    def select_mic(self, mac: str) -> dict:
        """Select a specific network device as the active microphone."""
        mac = mac.lower()
        device = self._registry.get_device(mac)

        if not device:
            return {"error": "Device not found", "mac": mac}

        if device.get("permission") != PERM_GRANTED:
            return {"error": "Device not permitted", "mac": mac}

        if CAP_MICROPHONE not in device.get("capabilities", []):
            return {"error": "Device has no microphone capability", "mac": mac}

        if not device.get("online", False):
            return {"error": "Device is offline", "mac": mac}

        self._selected_mic = mac
        self._use_local_mic = False
        logger.info(
            f"🎤 Mic source selected: {device['ip']} "
            f"({device.get('friendly_name') or device.get('vendor')})"
        )
        self._notify("mic_selected", mac, False)

        return {
            "status": "mic_selected",
            "mac": mac,
            "ip": device["ip"],
            "name": device.get("friendly_name") or device.get("vendor"),
        }

    def select_local_mic(self) -> dict:
        """Switch to the local device's microphone."""
        self._selected_mic = None
        self._use_local_mic = True
        logger.info("🎤 Mic source: LOCAL DEVICE")
        self._notify("mic_selected", "local", True)
        return {"status": "local_mic_selected"}

    def get_active_mic(self) -> dict:
        """Get the currently active microphone source."""
        if self._use_local_mic or not self._selected_mic:
            # Check if we should auto-select a network mic
            auto = self._auto_select_mic()
            if auto:
                return auto
            return {
                "source": "local",
                "is_local": True,
                "reason": "No network microphone available",
            }

        device = self._registry.get_device(self._selected_mic)
        if not device or not device.get("online"):
            # Selected mic went offline — fallback
            logger.warning(
                f"⚠️ Selected mic {self._selected_mic} is offline, "
                f"falling back..."
            )
            auto = self._auto_select_mic()
            if auto:
                return auto
            return {
                "source": "local",
                "is_local": True,
                "reason": "Network mic offline, using local fallback",
            }

        return {
            "source": "network",
            "is_local": False,
            "mac": device["mac"],
            "ip": device["ip"],
            "name": device.get("friendly_name") or device.get("vendor"),
            "device_type": device["device_type"],
        }

    def _auto_select_mic(self) -> Optional[dict]:
        """Auto-select the best available network microphone."""
        mics = self._registry.get_permitted_devices(CAP_MICROPHONE)
        online_mics = [m for m in mics if m.get("online")]

        if not online_mics:
            return None

        # Sort by fallback priority
        online_mics.sort(
            key=lambda d: FALLBACK_PRIORITY.get(d["device_type"], 50)
        )

        best = online_mics[0]
        self._selected_mic = best["mac"]
        self._use_local_mic = False

        logger.info(
            f"🎤 Auto-selected mic: {best['ip']} ({best['device_type']})"
        )
        self._notify("mic_auto_selected", best["mac"], False)

        return {
            "source": "network",
            "is_local": False,
            "mac": best["mac"],
            "ip": best["ip"],
            "name": best.get("friendly_name") or best.get("vendor"),
            "device_type": best["device_type"],
            "auto_selected": True,
        }

    # ── Speaker Management ──────────────────────────────────────────

    def select_speaker(self, mac: str) -> dict:
        """Select a specific network device as the active speaker."""
        mac = mac.lower()
        device = self._registry.get_device(mac)

        if not device:
            return {"error": "Device not found", "mac": mac}

        if device.get("permission") != PERM_GRANTED:
            return {"error": "Device not permitted", "mac": mac}

        if CAP_SPEAKER not in device.get("capabilities", []):
            return {"error": "Device has no speaker capability", "mac": mac}

        if not device.get("online", False):
            return {"error": "Device is offline", "mac": mac}

        self._selected_speaker = mac
        self._use_local_speaker = False
        logger.info(
            f"🔊 Speaker selected: {device['ip']} "
            f"({device.get('friendly_name') or device.get('vendor')})"
        )
        self._notify("speaker_selected", mac, False)

        return {
            "status": "speaker_selected",
            "mac": mac,
            "ip": device["ip"],
            "name": device.get("friendly_name") or device.get("vendor"),
        }

    def select_local_speaker(self) -> dict:
        """Switch to the local device's speaker."""
        self._selected_speaker = None
        self._use_local_speaker = True
        logger.info("🔊 Speaker source: LOCAL DEVICE")
        self._notify("speaker_selected", "local", True)
        return {"status": "local_speaker_selected"}

    def get_active_speaker(self) -> dict:
        """Get the currently active speaker."""
        if self._use_local_speaker or not self._selected_speaker:
            auto = self._auto_select_speaker()
            if auto:
                return auto
            return {
                "source": "local",
                "is_local": True,
                "reason": "No network speaker available",
            }

        device = self._registry.get_device(self._selected_speaker)
        if not device or not device.get("online"):
            logger.warning(
                f"⚠️ Selected speaker {self._selected_speaker} offline, "
                f"falling back..."
            )
            auto = self._auto_select_speaker()
            if auto:
                return auto
            return {
                "source": "local",
                "is_local": True,
                "reason": "Network speaker offline, using local fallback",
            }

        return {
            "source": "network",
            "is_local": False,
            "mac": device["mac"],
            "ip": device["ip"],
            "name": device.get("friendly_name") or device.get("vendor"),
            "device_type": device["device_type"],
        }

    def _auto_select_speaker(self) -> Optional[dict]:
        """Auto-select the best available network speaker."""
        speakers = self._registry.get_permitted_devices(CAP_SPEAKER)
        online_speakers = [s for s in speakers if s.get("online")]

        if not online_speakers:
            return None

        online_speakers.sort(
            key=lambda d: FALLBACK_PRIORITY.get(d["device_type"], 50)
        )

        best = online_speakers[0]
        self._selected_speaker = best["mac"]
        self._use_local_speaker = False

        logger.info(
            f"🔊 Auto-selected speaker: {best['ip']} ({best['device_type']})"
        )
        self._notify("speaker_auto_selected", best["mac"], False)

        return {
            "source": "network",
            "is_local": False,
            "mac": best["mac"],
            "ip": best["ip"],
            "name": best.get("friendly_name") or best.get("vendor"),
            "device_type": best["device_type"],
            "auto_selected": True,
        }

    # ── Available Devices ───────────────────────────────────────────

    def get_available_microphones(self) -> List[dict]:
        """List all permitted devices with mic capability."""
        mics = self._registry.get_permitted_devices(CAP_MICROPHONE)
        result = []
        for m in mics:
            result.append({
                "mac": m["mac"],
                "ip": m["ip"],
                "name": m.get("friendly_name") or m.get("vendor"),
                "device_type": m["device_type"],
                "online": m.get("online", False),
                "is_active": m["mac"] == self._selected_mic,
            })
        # Add local option
        result.append({
            "mac": "local",
            "ip": "localhost",
            "name": "This Device (Built-in Mic)",
            "device_type": "local",
            "online": True,
            "is_active": self._use_local_mic or not self._selected_mic,
        })
        return result

    def get_available_speakers(self) -> List[dict]:
        """List all permitted devices with speaker capability."""
        speakers = self._registry.get_permitted_devices(CAP_SPEAKER)
        result = []
        for s in speakers:
            result.append({
                "mac": s["mac"],
                "ip": s["ip"],
                "name": s.get("friendly_name") or s.get("vendor"),
                "device_type": s["device_type"],
                "online": s.get("online", False),
                "is_active": s["mac"] == self._selected_speaker,
            })
        # Add local option
        result.append({
            "mac": "local",
            "ip": "localhost",
            "name": "This Device (Built-in Speaker)",
            "device_type": "local",
            "online": True,
            "is_active": self._use_local_speaker
                or not self._selected_speaker,
        })
        return result

    # ── Fallback Status ─────────────────────────────────────────────

    def get_fallback_status(self) -> dict:
        """Get current fallback status for all audio devices."""
        mic = self.get_active_mic()
        speaker = self.get_active_speaker()

        return {
            "microphone": {
                "is_local_fallback": mic.get("is_local", True),
                "active_source": mic,
                "available_count": len(
                    self._registry.get_permitted_devices(CAP_MICROPHONE)
                ),
            },
            "speaker": {
                "is_local_fallback": speaker.get("is_local", True),
                "active_source": speaker,
                "available_count": len(
                    self._registry.get_permitted_devices(CAP_SPEAKER)
                ),
            },
        }
