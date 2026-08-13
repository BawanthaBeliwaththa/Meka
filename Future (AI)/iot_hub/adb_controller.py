import subprocess
import logging
import base64
import time
import threading
import json
import os
from typing import List, Dict, Optional

logger = logging.getLogger(__name__)

# Persistent paired devices file — survives hub restarts
_PAIRED_DEVICES_FILE = os.path.join(
    os.path.dirname(__file__), "data", "adb_paired_devices.json"
)


def _load_paired_devices() -> Dict[str, dict]:
    """Load known paired WiFi devices from disk."""
    try:
        if os.path.exists(_PAIRED_DEVICES_FILE):
            with open(_PAIRED_DEVICES_FILE, "r") as f:
                return json.load(f)
    except Exception:
        pass
    return {}


def _save_paired_devices(devices: Dict[str, dict]) -> None:
    """Persist known paired WiFi devices to disk."""
    try:
        os.makedirs(os.path.dirname(_PAIRED_DEVICES_FILE), exist_ok=True)
        with open(_PAIRED_DEVICES_FILE, "w") as f:
            json.dump(devices, f, indent=2)
    except Exception as e:
        logger.warning(f"Could not save paired devices: {e}")


class AdbController:
    """
    Manages connections and commands to Android devices via ADB over WiFi.
    Supports:
      - Wireless pairing (Android 11+ adb pair)
      - Persistent auto-reconnect on hub restart
      - Screen lock bypass (wake + swipe + optional PIN)
      - Shell execution, screenshot, APK install
      - scrcpy screen mirror (spawns subprocess)
    """

    def __init__(self, adb_path: str = "adb"):
        self.adb_path = adb_path
        self._mirror_procs: Dict[str, subprocess.Popen] = {}  # serial → scrcpy process
        self._paired_devices: Dict[str, dict] = _load_paired_devices()
        # Start adb server
        try:
            self._run_cmd(["start-server"])
        except Exception:
            pass

    # ──────────────────────────────────────────────────────────────────────────
    # Internal helpers
    # ──────────────────────────────────────────────────────────────────────────

    def _run_cmd(self, args: List[str], timeout: int = 15) -> subprocess.CompletedProcess:
        """Run an ADB command (binary output)."""
        cmd = [self.adb_path] + args
        try:
            creationflags = 0x08000000 if hasattr(subprocess, "CREATE_NO_WINDOW") else 0
            return subprocess.run(
                cmd, capture_output=True, text=False,
                timeout=timeout, creationflags=creationflags
            )
        except subprocess.TimeoutExpired as e:
            logger.error(f"ADB timeout: {' '.join(cmd)}")
            raise e
        except Exception as e:
            logger.error(f"ADB failed: {' '.join(cmd)} — {e}")
            raise e

    def _run_cmd_text(self, args: List[str], timeout: int = 15) -> subprocess.CompletedProcess:
        """Run an ADB command (text output)."""
        cmd = [self.adb_path] + args
        try:
            creationflags = 0x08000000 if hasattr(subprocess, "CREATE_NO_WINDOW") else 0
            return subprocess.run(
                cmd, capture_output=True, text=True,
                timeout=timeout, creationflags=creationflags
            )
        except Exception as e:
            logger.error(f"ADB failed: {' '.join(cmd)} — {e}")
            raise e

    def _shell(self, serial: str, command: str, timeout: int = 10) -> str:
        """Run adb shell command on a device, return stdout."""
        try:
            res = self._run_cmd_text(["-s", serial, "shell"] + command.split(), timeout=timeout)
            return (res.stdout or "").strip()
        except Exception as e:
            return str(e)

    # ──────────────────────────────────────────────────────────────────────────
    # Device listing
    # ──────────────────────────────────────────────────────────────────────────

    def list_devices(self) -> List[Dict[str, str]]:
        """List currently connected ADB devices."""
        try:
            res = self._run_cmd_text(["devices", "-l"])
            if res.returncode != 0:
                return []
            devices = []
            for line in res.stdout.strip().split("\n")[1:]:
                parts = line.split()
                if len(parts) >= 2:
                    serial = parts[0]
                    state  = parts[1]
                    model  = next((p.split(":")[1] for p in parts[2:] if p.startswith("model:")), "")
                    devices.append({"serial": serial, "state": state, "model": model})
            return devices
        except Exception:
            return []

    # ──────────────────────────────────────────────────────────────────────────
    # WiFi Pairing (Android 11+) — adb pair
    # ──────────────────────────────────────────────────────────────────────────

    def pair(self, ip: str, pair_port: int, code: str) -> Dict[str, str]:
        """
        Pair with an Android 11+ device using Wireless Debugging pairing code.
        After pairing, save device IP for persistent auto-reconnect.
        Returns {"status": "paired"} or {"error": "..."}
        """
        try:
            res = self._run_cmd_text(
                ["pair", f"{ip}:{pair_port}", code],
                timeout=20
            )
            output = (res.stdout + res.stderr).lower()
            if "successfully paired" in output or "paired" in output:
                logger.info(f"✅ Paired with {ip}:{pair_port}")
                # Persist this device for auto-reconnect
                self._paired_devices[ip] = {
                    "ip": ip,
                    "pair_port": pair_port,
                    "adb_port": 5555,
                    "paired_at": time.time(),
                    "label": f"Android ({ip})",
                }
                _save_paired_devices(self._paired_devices)
                # Now connect on the main ADB port
                connected = self.connect(ip, 5555)
                return {
                    "status": "paired",
                    "connected": connected,
                    "ip": ip,
                    "serial": f"{ip}:5555",
                }
            else:
                err = (res.stdout + res.stderr).strip()
                logger.warning(f"Pairing failed for {ip}: {err}")
                return {"error": f"Pairing failed: {err}"}
        except Exception as e:
            return {"error": str(e)}

    def connect(self, ip: str, port: int = 5555) -> bool:
        """Connect to an ADB device over WiFi."""
        try:
            res = self._run_cmd_text(["connect", f"{ip}:{port}"])
            return "connected to" in res.stdout.lower()
        except Exception:
            return False

    def disconnect(self, serial: str) -> bool:
        """Disconnect an ADB WiFi device."""
        try:
            res = self._run_cmd_text(["disconnect", serial])
            return res.returncode == 0
        except Exception:
            return False

    def auto_reconnect(self) -> List[str]:
        """
        Reconnect all previously paired devices on hub start.
        Returns list of successfully reconnected serials.
        """
        reconnected = []
        for ip, info in list(self._paired_devices.items()):
            port = info.get("adb_port", 5555)
            try:
                if self.connect(ip, port):
                    reconnected.append(f"{ip}:{port}")
                    logger.info(f"🔗 Auto-reconnected: {ip}:{port}")
                else:
                    logger.info(f"⚠️  Could not reconnect {ip}:{port} (device offline?)")
            except Exception as e:
                logger.warning(f"Auto-reconnect error for {ip}: {e}")
        return reconnected

    def get_paired_devices(self) -> List[dict]:
        """Return the list of all ever-paired devices."""
        return list(self._paired_devices.values())

    # ──────────────────────────────────────────────────────────────────────────
    # Shell / Commands
    # ──────────────────────────────────────────────────────────────────────────

    def execute_shell(self, serial: str, command: str) -> str:
        """Execute a shell command on the specified device."""
        try:
            # Use shell=False-safe split only for simple commands
            args = ["-s", serial, "shell"] + command.split()
            res = self._run_cmd_text(args)
            return (res.stdout if res.returncode == 0 else res.stderr).strip()
        except Exception as e:
            return str(e)

    # ──────────────────────────────────────────────────────────────────────────
    # Screen Lock Bypass
    # ──────────────────────────────────────────────────────────────────────────

    def unlock(self, serial: str, pin: Optional[str] = None) -> bool:
        """
        Wake up and unlock the device screen.
        Steps:
          1. Send KEYCODE_WAKEUP  (works even when screen is off)
          2. Wait for screen to turn on
          3. Dismiss lock screen with swipe (works for swipe/no-lock)
          4. If PIN provided, send it via 'input text {pin}' + ENTER
        """
        try:
            # 1. Wake screen (KEYCODE_WAKEUP = 224, safer than POWER toggle)
            self._shell(serial, "input keyevent 224")
            time.sleep(0.8)

            # 2. Check if screen is on
            screen_state = self._shell(serial, "dumpsys power | grep 'Display Power'")
            if "state=OFF" in screen_state:
                # Fallback: use POWER key
                self._shell(serial, "input keyevent 26")
                time.sleep(0.8)

            # 3. Dismiss lock screen: swipe up from bottom third of screen
            self._shell(serial, "input swipe 540 1600 540 400 300")
            time.sleep(0.5)

            # 4. If PIN provided, type it and press Enter
            if pin:
                time.sleep(0.3)
                # input text sends the PIN to the current focused field (PIN prompt)
                self._shell(serial, f"input text {pin}")
                time.sleep(0.2)
                self._shell(serial, "input keyevent 66")  # KEYCODE_ENTER

            return True
        except Exception as e:
            logger.warning(f"Unlock failed for {serial}: {e}")
            return False

    # ──────────────────────────────────────────────────────────────────────────
    # Screenshot
    # ──────────────────────────────────────────────────────────────────────────

    def screenshot(self, serial: str) -> Optional[str]:
        """Capture a screenshot and return as base64 PNG bytes."""
        try:
            res = self._run_cmd(
                ["-s", serial, "exec-out", "screencap", "-p"],
                timeout=15
            )
            if res.returncode == 0 and len(res.stdout) > 0:
                return base64.b64encode(res.stdout).decode("utf-8")
            return None
        except Exception:
            return None

    # ──────────────────────────────────────────────────────────────────────────
    # Device Info
    # ──────────────────────────────────────────────────────────────────────────

    def get_device_info(self, serial: str) -> Dict[str, str]:
        """
        Return a rich dict of device information via adb shell.
        Includes: model, brand, android version, battery, WiFi IP, SDK level.
        """
        def sh(cmd): return self._shell(serial, cmd)

        model    = sh("getprop ro.product.model")
        brand    = sh("getprop ro.product.brand")
        sdk      = sh("getprop ro.build.version.sdk")
        android  = sh("getprop ro.build.version.release")
        battery  = sh("dumpsys battery | grep level").replace("level:", "").strip()
        # Get WiFi IP from wlan0
        wifi_ip  = sh("ip addr show wlan0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1")
        # Screen state
        screen   = sh("dumpsys power | grep 'Display Power'")
        screen_on = "ON" in screen.upper()

        return {
            "serial":          serial,
            "model":           model,
            "brand":           brand,
            "android_version": android,
            "sdk":             sdk,
            "battery_level":   battery,
            "wifi_ip":         wifi_ip,
            "screen_on":       screen_on,
        }

    # ──────────────────────────────────────────────────────────────────────────
    # APK Install
    # ──────────────────────────────────────────────────────────────────────────

    def install_apk(self, serial: str, apk_path: str) -> Dict[str, str]:
        """Install an APK on the device. Returns status dict."""
        if not os.path.exists(apk_path):
            return {"error": f"APK not found: {apk_path}"}
        try:
            res = self._run_cmd_text(
                ["-s", serial, "install", "-r", "-d", apk_path],
                timeout=120
            )
            output = (res.stdout + res.stderr).strip()
            if "Success" in output:
                return {"status": "installed", "output": output}
            return {"error": output}
        except Exception as e:
            return {"error": str(e)}

    # ──────────────────────────────────────────────────────────────────────────
    # scrcpy Screen Mirror
    # ──────────────────────────────────────────────────────────────────────────

    def start_mirror(self, serial: str, window_title: str = "MEKA Mirror") -> Dict[str, str]:
        """
        Launch scrcpy for the given device serial.
        Runs scrcpy in a subprocess — visible on the hub PC desktop.
        """
        if serial in self._mirror_procs:
            proc = self._mirror_procs[serial]
            if proc.poll() is None:
                return {"status": "already_running", "serial": serial}

        # Find scrcpy binary
        scrcpy_path = self._find_scrcpy()
        if not scrcpy_path:
            return {"error": "scrcpy not found. Install from https://github.com/Genymobile/scrcpy"}

        try:
            creationflags = 0
            proc = subprocess.Popen(
                [scrcpy_path, "--serial", serial,
                 "--window-title", window_title,
                 "--max-size", "1280",
                 "--bit-rate", "4M",
                 "--no-audio"],  # Audio routed through phone bridge instead
                creationflags=creationflags,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            self._mirror_procs[serial] = proc
            logger.info(f"🖥️  scrcpy started for {serial} (pid={proc.pid})")
            return {"status": "mirror_started", "serial": serial, "pid": proc.pid}
        except Exception as e:
            return {"error": str(e)}

    def stop_mirror(self, serial: str) -> Dict[str, str]:
        """Stop an active scrcpy mirror session."""
        proc = self._mirror_procs.get(serial)
        if not proc:
            return {"status": "not_running"}
        try:
            proc.terminate()
            proc.wait(timeout=5)
        except Exception:
            proc.kill()
        del self._mirror_procs[serial]
        logger.info(f"🖥️  scrcpy stopped for {serial}")
        return {"status": "mirror_stopped", "serial": serial}

    def _find_scrcpy(self) -> Optional[str]:
        """Find scrcpy binary on PATH or common locations."""
        import shutil
        found = shutil.which("scrcpy")
        if found:
            return found
        # Windows common install paths
        candidates = [
            r"C:\scrcpy\scrcpy.exe",
            r"C:\Program Files\scrcpy\scrcpy.exe",
            r"C:\Users\Bawantha Beliwaththa\scrcpy\scrcpy.exe",
        ]
        for c in candidates:
            if os.path.exists(c):
                return c
        return None

    # ──────────────────────────────────────────────────────────────────────────
    # Screenshot-based pseudo-mirror (for web admin panel)
    # ──────────────────────────────────────────────────────────────────────────

    _mirror_stream_active: Dict[str, bool] = {}

    def start_screenshot_stream(self, serial: str) -> None:
        """Start a background thread that continuously captures screenshots for the web mirror."""
        self._mirror_stream_active[serial] = True

        def _loop():
            while self._mirror_stream_active.get(serial, False):
                try:
                    # Stored in memory — served by /api/adb/{serial}/mirror/frame
                    b64 = self.screenshot(serial)
                    if b64:
                        _ADB_MIRROR_FRAMES[serial] = b64
                except Exception:
                    pass
                time.sleep(0.5)  # ~2 fps for web mirror

        t = threading.Thread(target=_loop, daemon=True, name=f"mirror-{serial}")
        t.start()

    def stop_screenshot_stream(self, serial: str) -> None:
        self._mirror_stream_active[serial] = False
        _ADB_MIRROR_FRAMES.pop(serial, None)


# Global frame store for web mirror streaming
_ADB_MIRROR_FRAMES: Dict[str, str] = {}
