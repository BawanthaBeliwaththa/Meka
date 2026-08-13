#!/bin/bash
# MEKA IoT Hub Auto-Runner for HestiaCP Cron
# Auto-installs/verifies required Python dependencies and starts hub_server.py.

HUB_DIR="/home/bawantha/web/meka.starlight-coders.site/public_html/backend"
LOG_FILE="$HUB_DIR/hub.log"

cd "$HUB_DIR" || exit 1

# Check if process is already running
if pgrep -f "hub_server.py" > /dev/null; then
    exit 0
fi

echo "==========================================" >> "$LOG_FILE"
echo "$(date) - Verifying Python dependencies..." >> "$LOG_FILE"

# Auto-install/verify all dependencies before starting
pip3 install flask flask-socketio flask-cors cryptography scapy netifaces requests --break-system-packages >> "$LOG_FILE" 2>&1

echo "$(date) - Starting MEKA IoT Hub server..." >> "$LOG_FILE"
nohup python3 hub_server.py >> "$LOG_FILE" 2>&1 &
echo "$(date) - MEKA IoT Hub process spawned successfully (PID $!)" >> "$LOG_FILE"
