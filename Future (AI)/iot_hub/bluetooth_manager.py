#!/usr/bin/env python3
"""
Meka IoT Hub — Bluetooth Device Manager
══════════════════════════════════════════════════════════════════════

Scans, pairs, and manages Bluetooth devices (speakers, headsets,
microphones, and BLE serial nodes). Integrates with Audio Controller
to use Bluetooth speakers as audio outputs.
"""

import sys
import time
import subprocess
import threading
import logging
from typing import List, Dict, Optional

from config import (
    DEVICE_TYPE_SPEAKER, CAP_SPEAKER, CAP_MICROPHONE,
)

logger = logging.getLogger("meka.bluetooth")


class BluetoothManager:
    """Manages Bluetooth device discovery, pairing, and connection."""

    def __init__(self):
        self._lock = threading.Lock()
        self._discovered_devices: Dict[str, dict] = {}
        self._connected_devices: Dict[str, dict] = {}
        self._is_scanning = False

    # ── Device Discovery ────────────────────────────────────────────

    def scan_devices(self, timeout: int = 8) -> List[dict]:
        """
        Scan for nearby Bluetooth devices (Bluetooth Classic + BLE).
        Returns a list of device dicts.
        """
        with self._lock:
            if self._is_scanning:
                return list(self._discovered_devices.values())
            self._is_scanning = True

        logger.info("📡 Scanning for Bluetooth devices...")
        found: Dict[str, dict] = {}

        # 1. Try bleak for BLE scanning (Cross-platform Python)
        try:
            import asyncio
            from bleak import BleakScanner

            async def _ble_scan():
                devices = await BleakScanner.discover(timeout=float(timeout))
                for d in devices:
                    mac = d.address.upper()
                    found[mac] = {
                        "mac": mac,
                        "name": d.name or "Unknown BLE Device",
                        "rssi": d.rssi,
                        "type": "ble",
                        "capabilities": [CAP_SPEAKER] if "speaker" in (d.name or "").lower() else [],
                        "connected": False,
                    }

            asyncio.run(_ble_scan())
            logger.info(f"Bluetooth BLE scan found {len(found)} devices")
        except Exception as e:
            logger.debug(f"Bleak scanner not available or failed: {e}")

        # 2. Try OS-native Bluetooth scan (Windows PowerShell / Bluetooth CLI)
        if sys.platform == "win32":
            self._scan_windows(found)
        else:
            self._scan_linux(found)

        with self._lock:
            self._discovered_devices = found
            self._is_scanning = False

        return list(found.values())

    def _scan_windows(self, found: Dict[str, dict]):
        """Windows PowerShell Bluetooth device query."""
        try:
            cmd = (
                "Get-PnpDevice -Class 'Bluetooth' | "
                "Select-Object Status, Class, FriendlyName, InstanceId | "
                "ConvertTo-Json"
            )
            res = subprocess.check_output(
                ["powershell", "-Command", cmd],
                encoding="utf-8", errors="replace"
            )
            import json
            data = json.loads(res)
            if isinstance(data, dict):
                data = [data]

            for item in data:
                name = item.get("FriendlyName", "")
                status = item.get("Status", "")
                inst = item.get("InstanceId", "")
                if name and "enumerator" not in name.lower() and "adapter" not in name.lower():
                    # Generate a pseudo MAC or extract from instance ID
                    mac_part = inst.split("_")[-1] if "_" in inst else "BT-DEV"
                    found[inst] = {
                        "mac": mac_part,
                        "name": name,
                        "status": status,
                        "type": "bluetooth_classic",
                        "capabilities": [CAP_SPEAKER] if any(w in name.lower() for w in ["speaker", "headphone", "audio", "soundbar", "airpods"]) else [],
                        "connected": status == "OK",
                    }
        except Exception as e:
            logger.warning(f"Windows Bluetooth scan failed: {e}")

    def _scan_linux(self, found: Dict[str, dict]):
        """Linux bluetoothctl scan."""
        try:
            output = subprocess.check_output(
                ["bluetoothctl", "devices"],
                encoding="utf-8", errors="replace"
            )
            for line in output.strip().split("\n"):
                parts = line.split(" ", 2)
                if len(parts) >= 3 and parts[0] == "Device":
                    mac = parts[1].upper()
                    name = parts[2]
                    found[mac] = {
                        "mac": mac,
                        "name": name,
                        "type": "bluetooth_classic",
                        "capabilities": [CAP_SPEAKER] if any(w in name.lower() for w in ["speaker", "headphone", "audio", "soundbar"]) else [],
                        "connected": False,
                    }
        except Exception as e:
            logger.warning(f"Linux Bluetooth scan failed: {e}")

    # ── Connection & Pairing ────────────────────────────────────────

    def connect_device(self, mac_or_id: str) -> dict:
        """Connect to a Bluetooth audio device."""
        logger.info(f"🔗 Attempting connection to Bluetooth device: {mac_or_id}")
        
        # Try OS connection
        success = False
        if sys.platform == "win32":
            # Attempt Windows bluetooth connect
            try:
                cmd = f"Get-PnpDevice | Where-Object {{$_.InstanceId -like '*{mac_or_id}*' -or $_.FriendlyName -like '*{mac_or_id}*'}} | Enable-PnpDevice -Confirm:$false"
                subprocess.run(["powershell", "-Command", cmd], capture_output=True, timeout=5)
                success = True
            except Exception as e:
                logger.error(f"Windows BT connect error: {e}")
        else:
            try:
                subprocess.run(["bluetoothctl", "connect", mac_or_id], capture_output=True, timeout=10)
                success = True
            except Exception as e:
                logger.error(f"Linux BT connect error: {e}")

        dev_info = self._discovered_devices.get(mac_or_id, {
            "mac": mac_or_id,
            "name": f"Bluetooth Device ({mac_or_id})",
            "type": "bluetooth",
            "capabilities": [CAP_SPEAKER],
        })
        dev_info["connected"] = success

        if success:
            self._connected_devices[mac_or_id] = dev_info
            logger.info(f"✅ Bluetooth connected: {dev_info['name']}")
            return {"status": "connected", "device": dev_info}
        else:
            return {"status": "connection_attempted", "device": dev_info, "note": "Connection initiated"}

    def disconnect_device(self, mac_or_id: str) -> dict:
        """Disconnect a Bluetooth device."""
        if mac_or_id in self._connected_devices:
            del self._connected_devices[mac_or_id]
        return {"status": "disconnected", "mac": mac_or_id}

    def get_devices(self) -> List[dict]:
        """Get list of all discovered and connected Bluetooth devices."""
        return list(self._discovered_devices.values())
