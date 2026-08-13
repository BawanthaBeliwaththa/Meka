#!/usr/bin/env python3
"""
Meka IoT Hub — Network Device Scanner
══════════════════════════════════════════════════════════════════════

Discovers all devices on the local WiFi network using multiple
discovery protocols:
  • ARP scan — finds all active IPs and MACs
  • mDNS/Bonjour — finds advertised services (RTSP, HTTP, Meka agents)
  • UPnP/SSDP — finds smart speakers, Chromecast, media renderers
  • Port probing — detects camera/audio services on open ports
  • RTSP DESCRIBE — confirms actual video streams
  • MAC vendor lookup — identifies device manufacturer
"""

import socket
import ipaddress
import subprocess
import re
import sys
import time
import threading
import logging
from typing import List, Dict, Optional, Tuple, Set
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field

import requests

from config import (
    CAMERA_PORTS, RTSP_PORTS, ONVIF_PORTS, HTTP_STREAM_PORTS,
    SPEAKER_PORTS, MEKA_AGENT_PORT,
    CAMERA_VENDORS, SPEAKER_VENDORS, PHONE_VENDORS, PC_VENDORS,
    DEVICE_TYPE_CAMERA, DEVICE_TYPE_SPEAKER, DEVICE_TYPE_PHONE,
    DEVICE_TYPE_PC, DEVICE_TYPE_IOT, DEVICE_TYPE_MEKA_NODE,
    DEVICE_TYPE_UNKNOWN,
    CAP_CAMERA, CAP_MICROPHONE, CAP_SPEAKER,
    SCAN_TIMEOUT_SECONDS, MDNS_BROWSE_TIMEOUT, SSDP_TIMEOUT,
)

logger = logging.getLogger("meka.scanner")


# ══════════════════════════════════════════════════════════════════════
# Data Models
# ══════════════════════════════════════════════════════════════════════

@dataclass
class DiscoveredDevice:
    """Represents a device found on the network."""
    ip: str
    mac: str
    vendor: str = "Unknown"
    device_type: str = DEVICE_TYPE_UNKNOWN
    hostname: str = ""
    open_ports: List[int] = field(default_factory=list)
    capabilities: List[str] = field(default_factory=list)
    rtsp_confirmed: bool = False
    mdns_services: List[str] = field(default_factory=list)
    upnp_info: Dict[str, str] = field(default_factory=dict)
    last_seen: float = field(default_factory=time.time)
    friendly_name: str = ""

    def to_dict(self) -> dict:
        return {
            "ip": self.ip,
            "mac": self.mac,
            "vendor": self.vendor,
            "device_type": self.device_type,
            "hostname": self.hostname,
            "open_ports": self.open_ports,
            "capabilities": self.capabilities,
            "rtsp_confirmed": self.rtsp_confirmed,
            "mdns_services": self.mdns_services,
            "upnp_info": self.upnp_info,
            "last_seen": self.last_seen,
            "friendly_name": self.friendly_name or self.hostname or self.vendor,
        }


# ══════════════════════════════════════════════════════════════════════
# Network Range Detection
# ══════════════════════════════════════════════════════════════════════

def get_local_ip() -> str:
    """Get the local IP address by connecting to an external address."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.settimeout(1)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        hostname = socket.gethostname()
        return socket.gethostbyname(hostname)


def get_network_range() -> str:
    """Return the local network CIDR (e.g., '192.168.1.0/24')."""
    local_ip = get_local_ip()
    logger.info(f"Local IP: {local_ip}")

    try:
        if sys.platform == "win32":
            output = subprocess.check_output(
                "ipconfig", encoding="utf-8", errors="replace"
            )
        else:
            output = subprocess.check_output(
                ["ip", "addr"], encoding="utf-8", errors="replace"
            )
        lines = output.split('\n')
        for i, line in enumerate(lines):
            if local_ip in line:
                # Look for subnet mask in nearby lines
                for j in range(max(0, i - 2), min(i + 6, len(lines))):
                    # Windows: "Subnet Mask" or "子网掩码"
                    # Linux: CIDR notation in same line
                    if any(kw in lines[j].lower() for kw in
                           ['subnet mask', '子网掩码', 'netmask', 'mask']):
                        masks = re.findall(r'\d+\.\d+\.\d+\.\d+', lines[j])
                        if masks:
                            mask = masks[-1]  # Take last match (mask value)
                            net = ipaddress.IPv4Network(
                                f"{local_ip}/{mask}", strict=False
                            )
                            return str(net)
                    # Linux ip addr: "inet 192.168.1.5/24"
                    cidr_match = re.search(
                        r'inet\s+' + re.escape(local_ip) + r'/(\d+)', lines[j]
                    )
                    if cidr_match:
                        prefix = cidr_match.group(1)
                        net = ipaddress.IPv4Network(
                            f"{local_ip}/{prefix}", strict=False
                        )
                        return str(net)
    except Exception as e:
        logger.warning(f"Could not detect subnet mask: {e}")

    # Fallback to /24
    parts = local_ip.split('.')
    return f"{parts[0]}.{parts[1]}.{parts[2]}.0/24"


# ══════════════════════════════════════════════════════════════════════
# ARP Scan
# ══════════════════════════════════════════════════════════════════════

def arp_scan(network_cidr: str) -> List[Tuple[str, str]]:
    """
    Send ARP requests and return list of (ip, mac).
    Uses scapy if available, falls back to arp command.
    """
    devices = []

    # Try scapy first (requires admin/root)
    try:
        import scapy.all as scapy_all
        import scapy.layers.l2 as l2

        arp = l2.ARP(pdst=network_cidr)
        ether = l2.Ether(dst="ff:ff:ff:ff:ff:ff")
        packet = ether / arp
        result = scapy_all.srp(
            packet, timeout=SCAN_TIMEOUT_SECONDS, verbose=False
        )[0]
        for sent, received in result:
            devices.append((received.psrc, received.hwsrc.lower()))
        logger.info(f"ARP scan (scapy): found {len(devices)} devices")
        return devices
    except ImportError:
        logger.info("Scapy not available, falling back to arp command")
    except PermissionError:
        logger.warning("ARP scan requires admin privileges, using arp cache")
    except Exception as e:
        logger.warning(f"Scapy ARP scan failed: {e}")

    # Fallback: ping sweep + arp cache
    try:
        _ping_sweep(network_cidr)
        devices = _read_arp_cache()
        logger.info(f"ARP cache: found {len(devices)} devices")
    except Exception as e:
        logger.error(f"ARP fallback failed: {e}")

    return devices


def _ping_sweep(network_cidr: str):
    """Quick ping sweep to populate ARP cache."""
    network = ipaddress.IPv4Network(network_cidr, strict=False)
    hosts = list(network.hosts())

    def _ping(ip):
        ip_str = str(ip)
        try:
            if sys.platform == "win32":
                subprocess.run(
                    ["ping", "-n", "1", "-w", "500", ip_str],
                    capture_output=True, timeout=2
                )
            else:
                subprocess.run(
                    ["ping", "-c", "1", "-W", "1", ip_str],
                    capture_output=True, timeout=2
                )
        except Exception:
            pass

    with ThreadPoolExecutor(max_workers=50) as pool:
        pool.map(_ping, hosts[:254])  # Limit to /24


def _read_arp_cache() -> List[Tuple[str, str]]:
    """Read the OS ARP cache."""
    devices = []
    try:
        if sys.platform == "win32":
            output = subprocess.check_output(
                ["arp", "-a"], encoding="utf-8", errors="replace"
            )
        else:
            output = subprocess.check_output(
                ["arp", "-n"], encoding="utf-8", errors="replace"
            )

        for line in output.split('\n'):
            # Match IP and MAC address patterns
            match = re.search(
                r'(\d+\.\d+\.\d+\.\d+)\s+'
                r'.*?'
                r'([0-9a-fA-F]{2}[:-][0-9a-fA-F]{2}[:-][0-9a-fA-F]{2}'
                r'[:-][0-9a-fA-F]{2}[:-][0-9a-fA-F]{2}[:-][0-9a-fA-F]{2})',
                line
            )
            if match:
                ip = match.group(1)
                mac = match.group(2).lower().replace('-', ':')
                if mac != "ff:ff:ff:ff:ff:ff" and not mac.startswith("00:00:00"):
                    devices.append((ip, mac))
    except Exception as e:
        logger.error(f"Failed to read ARP cache: {e}")

    return devices


# ══════════════════════════════════════════════════════════════════════
# mDNS / Bonjour Discovery
# ══════════════════════════════════════════════════════════════════════

def mdns_discover() -> Dict[str, Dict]:
    """
    Discover devices advertising mDNS services.
    Returns dict of {ip: {services: [...], hostname: str}}
    """
    results: Dict[str, Dict] = {}

    try:
        from zeroconf import Zeroconf, ServiceBrowser

        class _Listener:
            def __init__(self):
                self.found = {}

            def add_service(self, zc, stype, name):
                try:
                    info = zc.get_service_info(stype, name)
                    if info and info.addresses:
                        ip = socket.inet_ntoa(info.addresses[0])
                        if ip not in self.found:
                            self.found[ip] = {
                                "services": [],
                                "hostname": info.server or "",
                                "properties": {},
                            }
                        self.found[ip]["services"].append(stype)
                        # Extract properties
                        if info.properties:
                            for k, v in info.properties.items():
                                key = k.decode() if isinstance(k, bytes) else str(k)
                                val = v.decode() if isinstance(v, bytes) else str(v)
                                self.found[ip]["properties"][key] = val
                except Exception:
                    pass

            def remove_service(self, zc, stype, name):
                pass

            def update_service(self, zc, stype, name):
                pass

        # Service types to browse
        service_types = [
            "_rtsp._tcp.local.",        # RTSP cameras
            "_http._tcp.local.",        # HTTP devices
            "_meka-agent._tcp.local.",  # Meka companion agents
            "_meka-node._tcp.local.",   # Meka ESP32 nodes
            "_googlecast._tcp.local.",  # Chromecast / Google speakers
            "_sonos._tcp.local.",       # Sonos speakers
            "_airplay._tcp.local.",     # AirPlay devices
            "_raop._tcp.local.",        # AirPlay audio
            "_ipp._tcp.local.",         # Printers (to exclude)
        ]

        zc = Zeroconf()
        listener = _Listener()
        browsers = []
        for stype in service_types:
            try:
                browsers.append(ServiceBrowser(zc, stype, listener))
            except Exception:
                pass

        time.sleep(MDNS_BROWSE_TIMEOUT)

        for browser in browsers:
            browser.cancel()
        zc.close()

        results = listener.found
        logger.info(f"mDNS discovery: found {len(results)} devices")

    except ImportError:
        logger.info("zeroconf not installed, skipping mDNS discovery")
    except Exception as e:
        logger.warning(f"mDNS discovery failed: {e}")

    return results


# ══════════════════════════════════════════════════════════════════════
# UPnP / SSDP Discovery
# ══════════════════════════════════════════════════════════════════════

def ssdp_discover() -> Dict[str, Dict]:
    """
    Discover UPnP/SSDP devices (smart speakers, media renderers).
    Returns dict of {ip: {device_type: str, friendly_name: str, ...}}
    """
    results: Dict[str, Dict] = {}

    try:
        SSDP_ADDR = "239.255.255.250"
        SSDP_PORT = 1900
        msg = (
            "M-SEARCH * HTTP/1.1\r\n"
            f"HOST: {SSDP_ADDR}:{SSDP_PORT}\r\n"
            "MAN: \"ssdp:discover\"\r\n"
            f"MX: {SSDP_TIMEOUT}\r\n"
            "ST: ssdp:all\r\n"
            "\r\n"
        )

        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.settimeout(SSDP_TIMEOUT + 1)
        sock.sendto(msg.encode(), (SSDP_ADDR, SSDP_PORT))

        while True:
            try:
                data, addr = sock.recvfrom(4096)
                ip = addr[0]
                response = data.decode("utf-8", errors="replace")

                if ip not in results:
                    results[ip] = {"services": [], "headers": {}}

                # Parse headers
                for line in response.split('\r\n'):
                    if ':' in line:
                        key, _, value = line.partition(':')
                        results[ip]["headers"][key.strip().upper()] = value.strip()

                # Extract useful info
                st = results[ip]["headers"].get("ST", "")
                if st:
                    results[ip]["services"].append(st)

            except socket.timeout:
                break

        sock.close()
        logger.info(f"SSDP discovery: found {len(results)} devices")

    except Exception as e:
        logger.warning(f"SSDP discovery failed: {e}")

    return results


# ══════════════════════════════════════════════════════════════════════
# Port Scanner
# ══════════════════════════════════════════════════════════════════════

def check_port(ip: str, port: int, timeout: float = 1.5) -> bool:
    """Return True if port is open."""
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(timeout)
        result = sock.connect_ex((ip, port))
        sock.close()
        return result == 0
    except Exception:
        return False


def scan_ports(ip: str, ports: Optional[List[int]] = None) -> List[int]:
    """Scan common IoT service ports on an IP."""
    if ports is None:
        all_ports = set(
            CAMERA_PORTS + SPEAKER_PORTS + [MEKA_AGENT_PORT, 5555]
        )
        ports = sorted(all_ports)

    open_ports = []
    with ThreadPoolExecutor(max_workers=20) as pool:
        futures = {pool.submit(check_port, ip, p): p for p in ports}
        for future in as_completed(futures):
            port = futures[future]
            try:
                if future.result():
                    open_ports.append(port)
            except Exception:
                pass

    return open_ports


# ══════════════════════════════════════════════════════════════════════
# RTSP Probe
# ══════════════════════════════════════════════════════════════════════

def rtsp_probe(ip: str, port: int = 554) -> bool:
    """Send RTSP OPTIONS to check if device is a camera stream."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(2)
        s.connect((ip, port))
        request = f"OPTIONS rtsp://{ip}:{port} RTSP/1.0\r\nCSeq: 1\r\n\r\n"
        s.send(request.encode())
        data = s.recv(1024).decode("utf-8", errors="replace")
        s.close()
        return "RTSP/1.0" in data
    except Exception:
        return False


# ══════════════════════════════════════════════════════════════════════
# MAC Vendor Lookup
# ══════════════════════════════════════════════════════════════════════

_vendor_cache: Dict[str, str] = {}


def get_vendor(mac: str) -> str:
    """Look up the manufacturer for a MAC address."""
    if mac in _vendor_cache:
        return _vendor_cache[mac]

    # Try online API
    try:
        resp = requests.get(
            f"https://api.macvendors.com/{mac}",
            timeout=2
        )
        if resp.status_code == 200:
            vendor = resp.text.strip()
            _vendor_cache[mac] = vendor
            return vendor
    except Exception:
        pass

    _vendor_cache[mac] = "Unknown"
    return "Unknown"


# ══════════════════════════════════════════════════════════════════════
# Device Classification
# ══════════════════════════════════════════════════════════════════════

def classify_device(device: DiscoveredDevice) -> DiscoveredDevice:
    """
    Determine device type and capabilities from all gathered data.
    Uses vendor, open ports, mDNS services, and UPnP info.
    """
    vendor_lower = device.vendor.lower()
    capabilities: Set[str] = set()
    device_type = DEVICE_TYPE_UNKNOWN

    # ── Vendor-based classification ──
    if any(v in vendor_lower for v in CAMERA_VENDORS):
        device_type = DEVICE_TYPE_CAMERA
        capabilities.add(CAP_CAMERA)
    elif any(v in vendor_lower for v in SPEAKER_VENDORS):
        device_type = DEVICE_TYPE_SPEAKER
        capabilities.add(CAP_SPEAKER)
    elif any(v in vendor_lower for v in PHONE_VENDORS):
        device_type = DEVICE_TYPE_PHONE
        capabilities.update([CAP_CAMERA, CAP_MICROPHONE, CAP_SPEAKER])
    elif any(v in vendor_lower for v in PC_VENDORS):
        device_type = DEVICE_TYPE_PC
        capabilities.update([CAP_CAMERA, CAP_MICROPHONE, CAP_SPEAKER])

    # ── Port-based classification ──
    for port in device.open_ports:
        if port == 5555:
            if device_type == DEVICE_TYPE_UNKNOWN:
                device_type = "android"
        if port in RTSP_PORTS:
            capabilities.add(CAP_CAMERA)
            if device_type == DEVICE_TYPE_UNKNOWN:
                device_type = DEVICE_TYPE_CAMERA
        if port in SPEAKER_PORTS:
            capabilities.add(CAP_SPEAKER)
            if device_type == DEVICE_TYPE_UNKNOWN:
                device_type = DEVICE_TYPE_SPEAKER
        if port == MEKA_AGENT_PORT:
            # Check if it's a Meka companion agent
            capabilities.update([CAP_CAMERA, CAP_MICROPHONE, CAP_SPEAKER])
            if device_type == DEVICE_TYPE_UNKNOWN:
                device_type = DEVICE_TYPE_PC

    # ── RTSP confirmation ──
    if device.rtsp_confirmed:
        capabilities.add(CAP_CAMERA)
        if device_type == DEVICE_TYPE_UNKNOWN:
            device_type = DEVICE_TYPE_CAMERA

    # ── mDNS service-based ──
    for service in device.mdns_services:
        if "_rtsp" in service:
            capabilities.add(CAP_CAMERA)
        if "_meka-node" in service:
            device_type = DEVICE_TYPE_MEKA_NODE
        if "_meka-agent" in service:
            capabilities.update([CAP_CAMERA, CAP_MICROPHONE, CAP_SPEAKER])
        if "_googlecast" in service or "_sonos" in service:
            device_type = DEVICE_TYPE_SPEAKER
            capabilities.add(CAP_SPEAKER)
        if "_airplay" in service or "_raop" in service:
            capabilities.add(CAP_SPEAKER)

    # ── ONVIF port check (strong camera indicator) ──
    if any(p in device.open_ports for p in ONVIF_PORTS):
        if device.rtsp_confirmed or any(p in device.open_ports for p in RTSP_PORTS):
            device_type = DEVICE_TYPE_CAMERA
            capabilities.add(CAP_CAMERA)

    device.device_type = device_type
    device.capabilities = sorted(capabilities)
    return device


# ══════════════════════════════════════════════════════════════════════
# Full Network Scan Orchestrator
# ══════════════════════════════════════════════════════════════════════

class NetworkScanner:
    """Orchestrates a full network device discovery scan."""

    def __init__(self):
        self._lock = threading.Lock()
        self._scanning = False
        self._last_results: List[DiscoveredDevice] = []
        self._scan_count = 0

    @property
    def is_scanning(self) -> bool:
        return self._scanning

    @property
    def last_results(self) -> List[DiscoveredDevice]:
        return self._last_results.copy()

    @property
    def scan_count(self) -> int:
        return self._scan_count

    def full_scan(self) -> List[DiscoveredDevice]:
        """
        Execute a complete network scan combining all discovery methods.
        Returns list of DiscoveredDevice objects.
        """
        with self._lock:
            if self._scanning:
                logger.info("Scan already in progress, returning cached results")
                return self._last_results.copy()
            self._scanning = True

        try:
            logger.info("═" * 60)
            logger.info("  MEKA IoT Hub — Starting full network scan")
            logger.info("═" * 60)
            start = time.time()

            # 1. Detect network range
            network = get_network_range()
            local_ip = get_local_ip()
            logger.info(f"📡 Network range: {network}")

            # 2. ARP scan — get all active IPs and MACs
            logger.info("🔍 Phase 1: ARP scan...")
            arp_devices = arp_scan(network)
            logger.info(f"   Found {len(arp_devices)} active devices")

            # 3. mDNS discovery (parallel with ARP)
            logger.info("🔍 Phase 2: mDNS discovery...")
            mdns_results = mdns_discover()
            logger.info(f"   Found {len(mdns_results)} mDNS-advertised devices")

            # 4. UPnP/SSDP discovery
            logger.info("🔍 Phase 3: UPnP/SSDP discovery...")
            ssdp_results = ssdp_discover()
            logger.info(f"   Found {len(ssdp_results)} UPnP devices")

            # 5. Build device list from ARP results
            devices: Dict[str, DiscoveredDevice] = {}
            for ip, mac in arp_devices:
                if ip == local_ip:
                    continue  # Skip self
                devices[ip] = DiscoveredDevice(ip=ip, mac=mac)

            # Add mDNS-only devices (might not appear in ARP)
            for ip, info in mdns_results.items():
                if ip == local_ip:
                    continue
                if ip not in devices:
                    devices[ip] = DiscoveredDevice(ip=ip, mac="unknown")
                devices[ip].mdns_services = info.get("services", [])
                devices[ip].hostname = info.get("hostname", "")

            # Add UPnP info
            for ip, info in ssdp_results.items():
                if ip in devices:
                    devices[ip].upnp_info = info.get("headers", {})

            # 6. MAC vendor lookup + port scan (parallel)
            logger.info("🔍 Phase 4: Vendor lookup + port scanning...")
            device_list = list(devices.values())

            with ThreadPoolExecutor(max_workers=10) as pool:
                # Vendor lookups
                vendor_futures = {}
                for dev in device_list:
                    if dev.mac != "unknown":
                        vendor_futures[pool.submit(get_vendor, dev.mac)] = dev

                # Port scans
                port_futures = {}
                for dev in device_list:
                    port_futures[pool.submit(scan_ports, dev.ip)] = dev

                # Collect vendor results
                for future in as_completed(vendor_futures):
                    dev = vendor_futures[future]
                    try:
                        dev.vendor = future.result()
                    except Exception:
                        pass

                # Collect port scan results
                for future in as_completed(port_futures):
                    dev = port_futures[future]
                    try:
                        dev.open_ports = future.result()
                    except Exception:
                        pass

            # 7. RTSP probes for devices with RTSP ports open
            logger.info("🔍 Phase 5: RTSP probes...")
            for dev in device_list:
                for port in dev.open_ports:
                    if port in RTSP_PORTS:
                        dev.rtsp_confirmed = rtsp_probe(dev.ip, port)
                        if dev.rtsp_confirmed:
                            break

            # 8. Classify all devices
            logger.info("🔍 Phase 6: Classifying devices...")
            for dev in device_list:
                classify_device(dev)
                dev.last_seen = time.time()

            elapsed = time.time() - start
            logger.info(f"✅ Scan complete in {elapsed:.1f}s — "
                        f"{len(device_list)} devices found")

            # Summary
            types = {}
            for dev in device_list:
                types[dev.device_type] = types.get(dev.device_type, 0) + 1
            for dtype, count in sorted(types.items()):
                logger.info(f"   {dtype}: {count}")

            self._last_results = device_list
            self._scan_count += 1
            return device_list

        finally:
            with self._lock:
                self._scanning = False


# ══════════════════════════════════════════════════════════════════════
# Standalone Test
# ══════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s │ %(name)s │ %(message)s",
        datefmt="%H:%M:%S",
    )

    scanner = NetworkScanner()
    devices = scanner.full_scan()

    print("\n" + "═" * 80)
    print("  DISCOVERED DEVICES")
    print("═" * 80)
    print(f"{'IP':<16} {'MAC':<18} {'Type':<12} {'Vendor':<25} {'Capabilities'}")
    print("─" * 80)
    for d in devices:
        caps = ", ".join(d.capabilities) if d.capabilities else "—"
        print(f"{d.ip:<16} {d.mac:<18} {d.device_type:<12} "
              f"{d.vendor[:25]:<25} {caps}")
    print("─" * 80)
    print(f"Total: {len(devices)} devices")
