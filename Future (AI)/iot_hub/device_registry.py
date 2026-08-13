#!/usr/bin/env python3
"""
Meka IoT Hub — Device Registry
══════════════════════════════════════════════════════════════════════

Persistent SQLite database tracking all discovered network devices,
their capabilities, permissions, and online/offline status.
"""

import sqlite3
import time
import threading
import logging
from typing import List, Optional, Dict
from contextlib import contextmanager

from config import (
    DB_PATH,
    PERM_PENDING, PERM_GRANTED, PERM_DENIED,
    DEVICE_TYPE_UNKNOWN,
)

logger = logging.getLogger("meka.registry")


# ══════════════════════════════════════════════════════════════════════
# Database Schema
# ══════════════════════════════════════════════════════════════════════

_SCHEMA = """
CREATE TABLE IF NOT EXISTS devices (
    mac             TEXT PRIMARY KEY,
    ip              TEXT NOT NULL,
    vendor          TEXT DEFAULT 'Unknown',
    device_type     TEXT DEFAULT 'unknown',
    hostname        TEXT DEFAULT '',
    friendly_name   TEXT DEFAULT '',
    open_ports      TEXT DEFAULT '[]',
    capabilities    TEXT DEFAULT '[]',
    rtsp_confirmed  INTEGER DEFAULT 0,
    mdns_services   TEXT DEFAULT '[]',
    permission      TEXT DEFAULT 'pending',
    first_seen      REAL NOT NULL,
    last_seen       REAL NOT NULL,
    online          INTEGER DEFAULT 1,
    notes           TEXT DEFAULT '',
    rtsp_url        TEXT DEFAULT '',
    stream_url      TEXT DEFAULT '',
    auth_user       TEXT DEFAULT '',
    auth_pass       TEXT DEFAULT ''
);

CREATE TABLE IF NOT EXISTS recordings (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    camera_mac      TEXT NOT NULL,
    camera_ip       TEXT NOT NULL,
    file_path       TEXT NOT NULL,
    start_time      REAL NOT NULL,
    end_time        REAL DEFAULT 0,
    duration_s      REAL DEFAULT 0,
    file_size_bytes INTEGER DEFAULT 0,
    status          TEXT DEFAULT 'recording',
    FOREIGN KEY (camera_mac) REFERENCES devices(mac)
);

CREATE TABLE IF NOT EXISTS audit_log (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp       REAL NOT NULL,
    action          TEXT NOT NULL,
    device_mac      TEXT DEFAULT '',
    details         TEXT DEFAULT ''
);

CREATE INDEX IF NOT EXISTS idx_devices_type ON devices(device_type);
CREATE INDEX IF NOT EXISTS idx_devices_perm ON devices(permission);
CREATE INDEX IF NOT EXISTS idx_devices_online ON devices(online);
CREATE INDEX IF NOT EXISTS idx_recordings_cam ON recordings(camera_mac);
CREATE INDEX IF NOT EXISTS idx_recordings_status ON recordings(status);
"""


# ══════════════════════════════════════════════════════════════════════
# Device Registry
# ══════════════════════════════════════════════════════════════════════

class DeviceRegistry:
    """Persistent device database with permission management."""

    def __init__(self, db_path: str = DB_PATH):
        self._db_path = db_path
        self._lock = threading.Lock()
        self._init_db()

    def _init_db(self):
        """Create tables if they don't exist."""
        with self._connect() as conn:
            conn.executescript(_SCHEMA)
            logger.info(f"📦 Device registry initialized: {self._db_path}")

    @contextmanager
    def _connect(self):
        """Thread-safe database connection context manager."""
        conn = sqlite3.connect(self._db_path)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA journal_mode=WAL")
        try:
            yield conn
            conn.commit()
        except Exception:
            conn.rollback()
            raise
        finally:
            conn.close()

    # ── Device CRUD ─────────────────────────────────────────────────

    def upsert_device(self, device_data: dict) -> dict:
        """
        Insert or update a device. Preserves existing permission state
        and user-set fields (friendly_name, auth_user, auth_pass, rtsp_url).
        """
        mac = device_data.get("mac", "").lower()
        if not mac or mac == "unknown":
            return {}

        now = time.time()

        with self._connect() as conn:
            # Check if device already exists
            existing = conn.execute(
                "SELECT * FROM devices WHERE mac = ?", (mac,)
            ).fetchone()

            if existing:
                # Update — preserve permission and user-set fields
                conn.execute("""
                    UPDATE devices SET
                        ip = ?,
                        vendor = CASE WHEN ? != 'Unknown' THEN ? ELSE vendor END,
                        device_type = CASE WHEN ? != 'unknown' THEN ? ELSE device_type END,
                        hostname = CASE WHEN ? != '' THEN ? ELSE hostname END,
                        open_ports = ?,
                        capabilities = ?,
                        rtsp_confirmed = ?,
                        mdns_services = ?,
                        last_seen = ?,
                        online = 1
                    WHERE mac = ?
                """, (
                    device_data.get("ip", existing["ip"]),
                    device_data.get("vendor", "Unknown"),
                    device_data.get("vendor", "Unknown"),
                    device_data.get("device_type", "unknown"),
                    device_data.get("device_type", "unknown"),
                    device_data.get("hostname", ""),
                    device_data.get("hostname", ""),
                    str(device_data.get("open_ports", [])),
                    str(device_data.get("capabilities", [])),
                    1 if device_data.get("rtsp_confirmed", False) else 0,
                    str(device_data.get("mdns_services", [])),
                    now,
                    mac,
                ))
                logger.debug(f"Updated device: {mac} ({device_data.get('ip')})")
            else:
                # Insert new device — starts with 'pending' permission
                conn.execute("""
                    INSERT INTO devices (
                        mac, ip, vendor, device_type, hostname,
                        friendly_name, open_ports, capabilities,
                        rtsp_confirmed, mdns_services, permission,
                        first_seen, last_seen, online
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)
                """, (
                    mac,
                    device_data.get("ip", ""),
                    device_data.get("vendor", "Unknown"),
                    device_data.get("device_type", DEVICE_TYPE_UNKNOWN),
                    device_data.get("hostname", ""),
                    device_data.get("friendly_name", ""),
                    str(device_data.get("open_ports", [])),
                    str(device_data.get("capabilities", [])),
                    1 if device_data.get("rtsp_confirmed", False) else 0,
                    str(device_data.get("mdns_services", [])),
                    PERM_PENDING,
                    now,
                    now,
                ))
                logger.info(f"🆕 New device registered: {mac} "
                            f"({device_data.get('ip')}) "
                            f"[{device_data.get('device_type')}]")

                # Audit log
                self._audit(conn, "device_discovered", mac,
                            f"IP: {device_data.get('ip')}, "
                            f"Type: {device_data.get('device_type')}, "
                            f"Vendor: {device_data.get('vendor')}")

            return self._get_device_dict(conn, mac)

    def get_device(self, mac: str) -> Optional[dict]:
        """Get a single device by MAC address."""
        with self._connect() as conn:
            return self._get_device_dict(conn, mac.lower())

    def get_all_devices(self) -> List[dict]:
        """Get all registered devices."""
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT * FROM devices ORDER BY last_seen DESC"
            ).fetchall()
            return [self._row_to_dict(r) for r in rows]

    def get_devices_by_type(self, device_type: str) -> List[dict]:
        """Get all devices of a specific type."""
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT * FROM devices WHERE device_type = ? "
                "ORDER BY last_seen DESC",
                (device_type,)
            ).fetchall()
            return [self._row_to_dict(r) for r in rows]

    def get_devices_by_capability(self, capability: str) -> List[dict]:
        """Get all devices that have a specific capability."""
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT * FROM devices WHERE capabilities LIKE ? "
                "ORDER BY last_seen DESC",
                (f"%{capability}%",)
            ).fetchall()
            return [self._row_to_dict(r) for r in rows]

    def get_permitted_devices(
        self, capability: Optional[str] = None
    ) -> List[dict]:
        """Get all devices with granted permissions."""
        with self._connect() as conn:
            if capability:
                rows = conn.execute(
                    "SELECT * FROM devices WHERE permission = ? "
                    "AND capabilities LIKE ? AND online = 1 "
                    "ORDER BY last_seen DESC",
                    (PERM_GRANTED, f"%{capability}%")
                ).fetchall()
            else:
                rows = conn.execute(
                    "SELECT * FROM devices WHERE permission = ? "
                    "ORDER BY last_seen DESC",
                    (PERM_GRANTED,)
                ).fetchall()
            return [self._row_to_dict(r) for r in rows]

    def get_online_cameras(self) -> List[dict]:
        """Get all permitted, online cameras."""
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT * FROM devices WHERE permission = ? "
                "AND capabilities LIKE '%camera%' AND online = 1 "
                "ORDER BY last_seen DESC",
                (PERM_GRANTED,)
            ).fetchall()
            return [self._row_to_dict(r) for r in rows]

    # ── Permission Management ───────────────────────────────────────

    def set_permission(self, mac: str, permission: str) -> bool:
        """Grant or deny permission for a device. One-time operation."""
        mac = mac.lower()
        if permission not in (PERM_GRANTED, PERM_DENIED, PERM_PENDING):
            return False

        with self._connect() as conn:
            cursor = conn.execute(
                "UPDATE devices SET permission = ? WHERE mac = ?",
                (permission, mac)
            )
            if cursor.rowcount > 0:
                action = "permission_granted" if permission == PERM_GRANTED \
                    else "permission_denied" if permission == PERM_DENIED \
                    else "permission_reset"
                self._audit(conn, action, mac, f"Permission set to: {permission}")
                logger.info(f"🔑 Permission for {mac}: {permission}")
                return True
            return False

    def grant_permission(self, mac: str) -> bool:
        """Grant permission to a device."""
        return self.set_permission(mac, PERM_GRANTED)

    def revoke_permission(self, mac: str) -> bool:
        """Revoke permission for a device."""
        return self.set_permission(mac, PERM_DENIED)

    # ── Device Configuration ────────────────────────────────────────

    def set_device_config(self, mac: str, **kwargs) -> bool:
        """Update user-configurable fields for a device."""
        mac = mac.lower()
        allowed_fields = {
            "friendly_name", "rtsp_url", "stream_url",
            "auth_user", "auth_pass", "notes",
        }
        updates = {k: v for k, v in kwargs.items() if k in allowed_fields}
        if not updates:
            return False

        set_clause = ", ".join(f"{k} = ?" for k in updates)
        values = list(updates.values()) + [mac]

        with self._connect() as conn:
            cursor = conn.execute(
                f"UPDATE devices SET {set_clause} WHERE mac = ?", values
            )
            return cursor.rowcount > 0

    # ── Online/Offline Status ───────────────────────────────────────

    def mark_offline(self, mac: str):
        """Mark a device as offline."""
        with self._connect() as conn:
            conn.execute(
                "UPDATE devices SET online = 0 WHERE mac = ?",
                (mac.lower(),)
            )

    def mark_all_offline(self):
        """Mark all devices offline (before a new scan)."""
        with self._connect() as conn:
            conn.execute("UPDATE devices SET online = 0")

    def mark_online(self, mac: str):
        """Mark a device as online."""
        with self._connect() as conn:
            conn.execute(
                "UPDATE devices SET online = 1, last_seen = ? WHERE mac = ?",
                (time.time(), mac.lower())
            )

    def update_online_status(self, seen_macs: List[str]):
        """
        Update online/offline status based on scan results.
        Devices not seen in the scan are marked offline.
        """
        seen_set = {m.lower() for m in seen_macs}
        with self._connect() as conn:
            all_devices = conn.execute("SELECT mac FROM devices").fetchall()
            for row in all_devices:
                mac = row["mac"]
                if mac in seen_set:
                    conn.execute(
                        "UPDATE devices SET online = 1, last_seen = ? "
                        "WHERE mac = ?",
                        (time.time(), mac)
                    )
                else:
                    conn.execute(
                        "UPDATE devices SET online = 0 WHERE mac = ?",
                        (mac,)
                    )

    # ── Recording Management ────────────────────────────────────────

    def add_recording(
        self, camera_mac: str, camera_ip: str, file_path: str
    ) -> int:
        """Register a new recording. Returns recording ID."""
        with self._connect() as conn:
            cursor = conn.execute(
                "INSERT INTO recordings "
                "(camera_mac, camera_ip, file_path, start_time, status) "
                "VALUES (?, ?, ?, ?, 'recording')",
                (camera_mac.lower(), camera_ip, file_path, time.time())
            )
            rec_id = cursor.lastrowid
            self._audit(conn, "recording_started", camera_mac,
                        f"File: {file_path}")
            return rec_id

    def finish_recording(
        self, recording_id: int, file_size: int = 0
    ):
        """Mark a recording as complete."""
        now = time.time()
        with self._connect() as conn:
            rec = conn.execute(
                "SELECT start_time FROM recordings WHERE id = ?",
                (recording_id,)
            ).fetchone()
            duration = now - rec["start_time"] if rec else 0

            conn.execute(
                "UPDATE recordings SET "
                "end_time = ?, duration_s = ?, "
                "file_size_bytes = ?, status = 'complete' "
                "WHERE id = ?",
                (now, duration, file_size, recording_id)
            )

    def get_recordings(
        self, camera_mac: Optional[str] = None, limit: int = 50
    ) -> List[dict]:
        """Get recording history."""
        with self._connect() as conn:
            if camera_mac:
                rows = conn.execute(
                    "SELECT * FROM recordings WHERE camera_mac = ? "
                    "ORDER BY start_time DESC LIMIT ?",
                    (camera_mac.lower(), limit)
                ).fetchall()
            else:
                rows = conn.execute(
                    "SELECT * FROM recordings "
                    "ORDER BY start_time DESC LIMIT ?",
                    (limit,)
                ).fetchall()
            return [dict(r) for r in rows]

    def get_active_recordings(self) -> List[dict]:
        """Get all currently active recordings."""
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT * FROM recordings WHERE status = 'recording'"
            ).fetchall()
            return [dict(r) for r in rows]

    # ── Statistics ──────────────────────────────────────────────────

    def get_stats(self) -> dict:
        """Get registry statistics."""
        with self._connect() as conn:
            total = conn.execute(
                "SELECT COUNT(*) as c FROM devices"
            ).fetchone()["c"]
            online = conn.execute(
                "SELECT COUNT(*) as c FROM devices WHERE online = 1"
            ).fetchone()["c"]
            permitted = conn.execute(
                "SELECT COUNT(*) as c FROM devices WHERE permission = ?",
                (PERM_GRANTED,)
            ).fetchone()["c"]
            cameras = conn.execute(
                "SELECT COUNT(*) as c FROM devices "
                "WHERE capabilities LIKE '%camera%'"
            ).fetchone()["c"]
            mics = conn.execute(
                "SELECT COUNT(*) as c FROM devices "
                "WHERE capabilities LIKE '%microphone%'"
            ).fetchone()["c"]
            speakers = conn.execute(
                "SELECT COUNT(*) as c FROM devices "
                "WHERE capabilities LIKE '%speaker%'"
            ).fetchone()["c"]
            recordings = conn.execute(
                "SELECT COUNT(*) as c FROM recordings"
            ).fetchone()["c"]
            active_recordings = conn.execute(
                "SELECT COUNT(*) as c FROM recordings "
                "WHERE status = 'recording'"
            ).fetchone()["c"]

            return {
                "total_devices": total,
                "online_devices": online,
                "permitted_devices": permitted,
                "cameras": cameras,
                "microphones": mics,
                "speakers": speakers,
                "total_recordings": recordings,
                "active_recordings": active_recordings,
            }

    # ── Audit Log ───────────────────────────────────────────────────

    def get_audit_log(self, limit: int = 100) -> List[dict]:
        """Get recent audit log entries."""
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT * FROM audit_log ORDER BY timestamp DESC LIMIT ?",
                (limit,)
            ).fetchall()
            return [dict(r) for r in rows]

    def _audit(self, conn, action: str, mac: str = "", details: str = ""):
        """Write an audit log entry."""
        conn.execute(
            "INSERT INTO audit_log (timestamp, action, device_mac, details) "
            "VALUES (?, ?, ?, ?)",
            (time.time(), action, mac, details)
        )

    # ── Helpers ─────────────────────────────────────────────────────

    def _get_device_dict(self, conn, mac: str) -> Optional[dict]:
        row = conn.execute(
            "SELECT * FROM devices WHERE mac = ?", (mac,)
        ).fetchone()
        return self._row_to_dict(row) if row else None

    @staticmethod
    def _row_to_dict(row) -> dict:
        """Convert a sqlite3.Row to a clean dict with parsed lists."""
        if row is None:
            return {}
        d = dict(row)
        # Parse stored list strings back to actual lists
        for key in ("open_ports", "capabilities", "mdns_services"):
            if key in d and isinstance(d[key], str):
                try:
                    import ast
                    d[key] = ast.literal_eval(d[key])
                except (ValueError, SyntaxError):
                    d[key] = []
        d["rtsp_confirmed"] = bool(d.get("rtsp_confirmed", 0))
        d["online"] = bool(d.get("online", 0))
        return d
