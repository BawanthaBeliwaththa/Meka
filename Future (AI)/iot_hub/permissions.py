#!/usr/bin/env python3
"""
Meka IoT Hub — Permission Manager
══════════════════════════════════════════════════════════════════════

One-time device permission system. Once a device is granted access,
it's never asked again (persisted in SQLite). Handles permission
workflows for cameras, mics, and speakers.
"""

import time
import logging
from typing import List, Optional, Dict

from device_registry import DeviceRegistry
from config import (
    PERM_PENDING, PERM_GRANTED, PERM_DENIED,
    CAP_CAMERA, CAP_MICROPHONE, CAP_SPEAKER,
)

logger = logging.getLogger("meka.permissions")


class PermissionManager:
    """
    Manages one-time device permissions.

    Permission flow:
    1. Device discovered → status = 'pending'
    2. User grants permission via UI/voice/API → status = 'granted'
    3. Device is now usable by Meka forever (persisted by MAC)
    4. User can revoke anytime → status = 'denied'
    5. User can re-grant → status = 'granted'
    """

    def __init__(self, registry: DeviceRegistry):
        self._registry = registry
        self._callbacks: List[callable] = []

    def on_permission_change(self, callback: callable):
        """Register a callback for permission changes."""
        self._callbacks.append(callback)

    def _notify(self, mac: str, permission: str):
        """Notify all registered callbacks."""
        for cb in self._callbacks:
            try:
                cb(mac, permission)
            except Exception as e:
                logger.error(f"Permission callback error: {e}")

    # ── Permission Operations ───────────────────────────────────────

    def grant(self, mac: str) -> dict:
        """
        Grant permission to a device. One-time operation.
        Returns the updated device dict.
        """
        mac = mac.lower()
        device = self._registry.get_device(mac)
        if not device:
            return {"error": "Device not found", "mac": mac}

        if device.get("permission") == PERM_GRANTED:
            return {"status": "already_granted", "device": device}

        success = self._registry.grant_permission(mac)
        if success:
            logger.info(
                f"✅ Permission GRANTED: {mac} "
                f"({device.get('ip')}) [{device.get('device_type')}]"
            )
            self._notify(mac, PERM_GRANTED)
            return {
                "status": "granted",
                "device": self._registry.get_device(mac),
            }

        return {"error": "Failed to grant permission", "mac": mac}

    def revoke(self, mac: str) -> dict:
        """Revoke permission for a device."""
        mac = mac.lower()
        device = self._registry.get_device(mac)
        if not device:
            return {"error": "Device not found", "mac": mac}

        success = self._registry.revoke_permission(mac)
        if success:
            logger.info(
                f"🚫 Permission REVOKED: {mac} "
                f"({device.get('ip')}) [{device.get('device_type')}]"
            )
            self._notify(mac, PERM_DENIED)
            return {
                "status": "revoked",
                "device": self._registry.get_device(mac),
            }

        return {"error": "Failed to revoke permission", "mac": mac}

    def reset(self, mac: str) -> dict:
        """Reset permission to pending (ask again)."""
        mac = mac.lower()
        success = self._registry.set_permission(mac, PERM_PENDING)
        if success:
            self._notify(mac, PERM_PENDING)
            return {"status": "reset", "mac": mac}
        return {"error": "Failed to reset permission", "mac": mac}

    def grant_all_pending(self) -> List[dict]:
        """Grant permission to all pending devices. Returns list of updated devices."""
        results = []
        for device in self.get_pending_devices():
            result = self.grant(device["mac"])
            results.append(result)
        return results

    # ── Queries ─────────────────────────────────────────────────────

    def is_permitted(self, mac: str) -> bool:
        """Check if a device has been granted permission."""
        device = self._registry.get_device(mac.lower())
        return device is not None and device.get("permission") == PERM_GRANTED

    def get_permission(self, mac: str) -> str:
        """Get the permission state of a device."""
        device = self._registry.get_device(mac.lower())
        if device:
            return device.get("permission", PERM_PENDING)
        return PERM_PENDING

    def get_pending_devices(self) -> List[dict]:
        """Get all devices awaiting permission."""
        all_devices = self._registry.get_all_devices()
        return [d for d in all_devices if d.get("permission") == PERM_PENDING]

    def get_granted_devices(self) -> List[dict]:
        """Get all devices with granted permission."""
        return self._registry.get_permitted_devices()

    def get_denied_devices(self) -> List[dict]:
        """Get all devices with denied permission."""
        all_devices = self._registry.get_all_devices()
        return [d for d in all_devices if d.get("permission") == PERM_DENIED]

    # ── Capability-Specific Queries ─────────────────────────────────

    def get_permitted_cameras(self) -> List[dict]:
        """Get all permitted devices with camera capability."""
        return self._registry.get_permitted_devices(CAP_CAMERA)

    def get_permitted_microphones(self) -> List[dict]:
        """Get all permitted devices with microphone capability."""
        return self._registry.get_permitted_devices(CAP_MICROPHONE)

    def get_permitted_speakers(self) -> List[dict]:
        """Get all permitted devices with speaker capability."""
        return self._registry.get_permitted_devices(CAP_SPEAKER)

    # ── Bulk Operations ─────────────────────────────────────────────

    def auto_permit_known_vendors(self, vendor_keywords: List[str]) -> List[dict]:
        """
        Auto-grant permission to devices from known/trusted vendors.
        Useful for auto-approving known camera brands.
        """
        results = []
        pending = self.get_pending_devices()
        for device in pending:
            vendor = device.get("vendor", "").lower()
            if any(kw in vendor for kw in vendor_keywords):
                result = self.grant(device["mac"])
                results.append(result)
                logger.info(
                    f"🤖 Auto-permitted {device['mac']} "
                    f"(vendor: {device.get('vendor')})"
                )
        return results

    # ── Summary ─────────────────────────────────────────────────────

    def get_summary(self) -> dict:
        """Get a permission summary for display."""
        all_devices = self._registry.get_all_devices()
        pending = [d for d in all_devices if d.get("permission") == PERM_PENDING]
        granted = [d for d in all_devices if d.get("permission") == PERM_GRANTED]
        denied = [d for d in all_devices if d.get("permission") == PERM_DENIED]

        return {
            "total_devices": len(all_devices),
            "pending": len(pending),
            "granted": len(granted),
            "denied": len(denied),
            "pending_devices": [
                {
                    "mac": d["mac"],
                    "ip": d["ip"],
                    "type": d["device_type"],
                    "vendor": d["vendor"],
                    "capabilities": d.get("capabilities", []),
                }
                for d in pending
            ],
        }
