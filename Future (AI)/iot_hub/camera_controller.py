#!/usr/bin/env python3
"""
Meka IoT Hub — Camera Controller
══════════════════════════════════════════════════════════════════════

Manages camera streams, recording, and snapshots across all
permitted network cameras. Supports:
  • RTSP streams (IP cameras, NVRs)
  • HTTP MJPEG streams (ESP32-CAM, webcam servers)
  • Multi-camera simultaneous recording
  • Snapshot capture
  • MJPEG relay for web dashboard viewing
"""

import os
import time
import threading
import logging
from typing import Dict, Optional, List
from datetime import datetime

from config import (
    RECORDINGS_DIR, SNAPSHOTS_DIR, RTSP_PORTS,
    CAP_CAMERA, PERM_GRANTED,
)
from device_registry import DeviceRegistry

logger = logging.getLogger("meka.camera")


# ══════════════════════════════════════════════════════════════════════
# Recording Session
# ══════════════════════════════════════════════════════════════════════

class RecordingSession:
    """Manages a single camera recording session."""

    def __init__(
        self,
        camera_mac: str,
        camera_ip: str,
        stream_url: str,
        output_path: str,
        recording_id: int,
    ):
        self.camera_mac = camera_mac
        self.camera_ip = camera_ip
        self.stream_url = stream_url
        self.output_path = output_path
        self.recording_id = recording_id
        self.start_time = time.time()
        self.frame_count = 0
        self.is_active = False
        self._thread: Optional[threading.Thread] = None
        self._stop_event = threading.Event()

    def start(self):
        """Start recording in a background thread."""
        if self.is_active:
            return

        self.is_active = True
        self._stop_event.clear()
        self._thread = threading.Thread(
            target=self._record_loop, daemon=True,
            name=f"rec-{self.camera_mac[-5:]}"
        )
        self._thread.start()
        logger.info(
            f"🔴 Recording started: {self.camera_ip} → {self.output_path}"
        )

    def stop(self) -> dict:
        """Stop recording and return session info."""
        self._stop_event.set()
        self.is_active = False

        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=5)

        duration = time.time() - self.start_time
        file_size = 0
        if os.path.exists(self.output_path):
            file_size = os.path.getsize(self.output_path)

        logger.info(
            f"⏹️  Recording stopped: {self.camera_ip} "
            f"({duration:.1f}s, {file_size} bytes, "
            f"{self.frame_count} frames)"
        )

        return {
            "camera_mac": self.camera_mac,
            "camera_ip": self.camera_ip,
            "output_path": self.output_path,
            "duration_s": round(duration, 1),
            "frame_count": self.frame_count,
            "file_size_bytes": file_size,
        }

    def _record_loop(self):
        """Main recording loop — captures frames from stream."""
        try:
            import cv2
        except ImportError:
            logger.error("OpenCV (cv2) not installed. Cannot record.")
            self.is_active = False
            return

        cap = None
        writer = None

        try:
            cap = cv2.VideoCapture(self.stream_url)
            if not cap.isOpened():
                logger.error(
                    f"❌ Cannot open stream: {self.stream_url}"
                )
                self.is_active = False
                return

            # Get stream properties
            fps = cap.get(cv2.CAP_PROP_FPS)
            if fps <= 0 or fps > 120:
                fps = 25.0  # Default fallback

            width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
            height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
            if width <= 0 or height <= 0:
                width, height = 1280, 720

            # Initialize video writer
            fourcc = cv2.VideoWriter_fourcc(*'mp4v')
            writer = cv2.VideoWriter(
                self.output_path, fourcc, fps, (width, height)
            )

            logger.info(
                f"📹 Stream opened: {width}x{height} @ {fps}fps"
            )

            while not self._stop_event.is_set():
                ret, frame = cap.read()
                if not ret:
                    # Try to reconnect
                    logger.warning(
                        f"⚠️ Frame read failed on {self.camera_ip}, "
                        f"attempting reconnect..."
                    )
                    cap.release()
                    time.sleep(2)
                    cap = cv2.VideoCapture(self.stream_url)
                    if not cap.isOpened():
                        logger.error(f"❌ Reconnect failed: {self.camera_ip}")
                        break
                    continue

                # Add timestamp overlay
                timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                cv2.putText(
                    frame, f"MEKA | {timestamp}",
                    (10, height - 15),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.5,
                    (255, 255, 255), 1, cv2.LINE_AA
                )

                writer.write(frame)
                self.frame_count += 1

        except Exception as e:
            logger.error(f"Recording error ({self.camera_ip}): {e}")

        finally:
            if cap:
                cap.release()
            if writer:
                writer.release()
            self.is_active = False


# ══════════════════════════════════════════════════════════════════════
# Camera Controller
# ══════════════════════════════════════════════════════════════════════

class CameraController:
    """
    Manages all camera operations: streaming, recording, snapshots.
    """

    def __init__(self, registry: DeviceRegistry):
        self._registry = registry
        self._active_recordings: Dict[str, RecordingSession] = {}
        self._lock = threading.Lock()

    # ── Stream URL Resolution ───────────────────────────────────────

    def _get_stream_url(self, device: dict) -> str:
        """
        Determine the best stream URL for a camera device.
        Priority: user-configured > RTSP default > HTTP MJPEG
        """
        # User-configured RTSP URL
        if device.get("rtsp_url"):
            url = device["rtsp_url"]
            # Insert auth if provided
            if device.get("auth_user") and "://" in url:
                proto, rest = url.split("://", 1)
                user = device["auth_user"]
                passwd = device.get("auth_pass", "")
                url = f"{proto}://{user}:{passwd}@{rest}"
            return url

        # User-configured stream URL
        if device.get("stream_url"):
            return device["stream_url"]

        ip = device["ip"]
        open_ports = device.get("open_ports", [])

        # RTSP auto-detect (common camera paths)
        for port in RTSP_PORTS:
            if port in open_ports:
                # Try common RTSP paths
                common_paths = [
                    f"rtsp://{ip}:{port}/stream1",
                    f"rtsp://{ip}:{port}/h264",
                    f"rtsp://{ip}:{port}/live",
                    f"rtsp://{ip}:{port}/cam/realmonitor?channel=1&subtype=0",
                    f"rtsp://{ip}:{port}/Streaming/Channels/101",
                    f"rtsp://{ip}:{port}/",
                ]
                # For now return the basic URL — user can configure later
                return f"rtsp://{ip}:{port}/"

        # HTTP MJPEG (ESP32-CAM, generic webcam servers)
        for port in [81, 80, 8080]:
            if port in open_ports:
                return f"http://{ip}:{port}/stream"

        return f"rtsp://{ip}:554/"

    def _generate_filename(
        self, camera_ip: str, extension: str = "mp4"
    ) -> str:
        """Generate a timestamped filename for recordings/snapshots."""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        safe_ip = camera_ip.replace(".", "_")
        return f"meka_{safe_ip}_{timestamp}.{extension}"

    # ── Recording Operations ────────────────────────────────────────

    def start_recording(
        self, camera_mac: str, custom_url: Optional[str] = None
    ) -> dict:
        """Start recording from a specific camera."""
        camera_mac = camera_mac.lower()

        with self._lock:
            # Check if already recording
            if camera_mac in self._active_recordings:
                session = self._active_recordings[camera_mac]
                if session.is_active:
                    return {
                        "status": "already_recording",
                        "camera_mac": camera_mac,
                        "camera_ip": session.camera_ip,
                        "started": session.start_time,
                    }

            # Get device info
            device = self._registry.get_device(camera_mac)
            if not device:
                return {"error": "Camera not found", "mac": camera_mac}

            if device.get("permission") != PERM_GRANTED:
                return {
                    "error": "Camera not permitted. Grant permission first.",
                    "mac": camera_mac,
                }

            if CAP_CAMERA not in device.get("capabilities", []):
                return {
                    "error": "Device does not have camera capability",
                    "mac": camera_mac,
                }

            # Resolve stream URL
            stream_url = custom_url or self._get_stream_url(device)
            camera_ip = device["ip"]

            # Generate output path
            filename = self._generate_filename(camera_ip)
            output_path = os.path.join(RECORDINGS_DIR, filename)

            # Register recording in DB
            rec_id = self._registry.add_recording(
                camera_mac, camera_ip, output_path
            )

            # Create and start session
            session = RecordingSession(
                camera_mac=camera_mac,
                camera_ip=camera_ip,
                stream_url=stream_url,
                output_path=output_path,
                recording_id=rec_id,
            )
            session.start()
            self._active_recordings[camera_mac] = session

            return {
                "status": "recording_started",
                "camera_mac": camera_mac,
                "camera_ip": camera_ip,
                "stream_url": stream_url,
                "output_path": output_path,
                "recording_id": rec_id,
            }

    def stop_recording(self, camera_mac: str) -> dict:
        """Stop recording from a specific camera."""
        camera_mac = camera_mac.lower()

        with self._lock:
            if camera_mac not in self._active_recordings:
                return {
                    "status": "not_recording",
                    "camera_mac": camera_mac,
                }

            session = self._active_recordings[camera_mac]
            info = session.stop()

            # Update DB
            file_size = info.get("file_size_bytes", 0)
            self._registry.finish_recording(
                session.recording_id, file_size
            )

            del self._active_recordings[camera_mac]

            return {
                "status": "recording_stopped",
                **info,
            }

    def start_recording_all(self) -> List[dict]:
        """Start recording from ALL permitted online cameras."""
        cameras = self._registry.get_online_cameras()
        results = []

        for cam in cameras:
            result = self.start_recording(cam["mac"])
            results.append(result)

        logger.info(
            f"🔴 Recording ALL cameras: {len(results)} started"
        )
        return results

    def stop_recording_all(self) -> List[dict]:
        """Stop all active recordings."""
        results = []
        macs = list(self._active_recordings.keys())

        for mac in macs:
            result = self.stop_recording(mac)
            results.append(result)

        logger.info(f"⏹️  Stopped ALL recordings: {len(results)}")
        return results

    # ── Snapshot ─────────────────────────────────────────────────────

    def take_snapshot(self, camera_mac: str) -> dict:
        """Capture a single frame from a camera."""
        camera_mac = camera_mac.lower()

        device = self._registry.get_device(camera_mac)
        if not device:
            return {"error": "Camera not found"}

        if device.get("permission") != PERM_GRANTED:
            return {"error": "Camera not permitted"}

        stream_url = self._get_stream_url(device)

        try:
            import cv2

            cap = cv2.VideoCapture(stream_url)
            if not cap.isOpened():
                return {"error": f"Cannot open stream: {stream_url}"}

            ret, frame = cap.read()
            cap.release()

            if not ret:
                return {"error": "Failed to capture frame"}

            # Add timestamp
            timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            h = frame.shape[0]
            cv2.putText(
                frame, f"MEKA | {timestamp}",
                (10, h - 15),
                cv2.FONT_HERSHEY_SIMPLEX, 0.5,
                (255, 255, 255), 1, cv2.LINE_AA
            )

            # Save snapshot
            filename = self._generate_filename(device["ip"], "jpg")
            filepath = os.path.join(SNAPSHOTS_DIR, filename)
            cv2.imwrite(filepath, frame)

            logger.info(f"📸 Snapshot saved: {filepath}")

            return {
                "status": "snapshot_taken",
                "camera_mac": camera_mac,
                "camera_ip": device["ip"],
                "file_path": filepath,
                "file_size": os.path.getsize(filepath),
            }

        except ImportError:
            return {"error": "OpenCV (cv2) not installed"}
        except Exception as e:
            return {"error": f"Snapshot failed: {e}"}

    # ── MJPEG Stream Relay ──────────────────────────────────────────

    def generate_mjpeg_frames(self, camera_mac: str):
        """
        Generator that yields MJPEG frames for web streaming.
        Used by Flask to serve live camera feeds to the dashboard.
        """
        camera_mac = camera_mac.lower()

        device = self._registry.get_device(camera_mac)
        if not device:
            return

        stream_url = self._get_stream_url(device)

        try:
            import cv2

            cap = cv2.VideoCapture(stream_url)
            if not cap.isOpened():
                logger.error(f"Cannot open stream for relay: {stream_url}")
                return

            while True:
                ret, frame = cap.read()
                if not ret:
                    time.sleep(0.1)
                    continue

                # Resize for web viewing (reduce bandwidth)
                frame = cv2.resize(frame, (640, 480))

                # Encode as JPEG
                _, buffer = cv2.imencode(
                    '.jpg', frame,
                    [cv2.IMWRITE_JPEG_QUALITY, 70]
                )
                frame_bytes = buffer.tobytes()

                yield (
                    b'--frame\r\n'
                    b'Content-Type: image/jpeg\r\n\r\n'
                    + frame_bytes + b'\r\n'
                )

        except ImportError:
            logger.error("OpenCV not installed — cannot relay stream")
        except GeneratorExit:
            pass
        except Exception as e:
            logger.error(f"MJPEG relay error: {e}")
        finally:
            if 'cap' in locals() and cap:
                cap.release()

    # ── Status ──────────────────────────────────────────────────────

    def get_recording_status(self) -> dict:
        """Get status of all active recordings."""
        active = {}
        for mac, session in self._active_recordings.items():
            if session.is_active:
                active[mac] = {
                    "camera_ip": session.camera_ip,
                    "output_path": session.output_path,
                    "duration_s": round(
                        time.time() - session.start_time, 1
                    ),
                    "frame_count": session.frame_count,
                }

        return {
            "active_count": len(active),
            "recordings": active,
        }

    def get_available_cameras(self) -> List[dict]:
        """Get all permitted online cameras with their stream URLs."""
        cameras = self._registry.get_online_cameras()
        result = []
        for cam in cameras:
            cam_info = {
                **cam,
                "stream_url": self._get_stream_url(cam),
                "is_recording": cam["mac"] in self._active_recordings
                    and self._active_recordings[cam["mac"]].is_active,
            }
            result.append(cam_info)
        return result

    def get_recordings_list(
        self, camera_mac: Optional[str] = None
    ) -> List[dict]:
        """Get list of all saved recordings."""
        return self._registry.get_recordings(camera_mac)
