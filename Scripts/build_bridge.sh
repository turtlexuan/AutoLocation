#!/bin/bash
# build_bridge.sh — Package bridge.py + pymobiledevice3 into a standalone binary
# using PyInstaller (--onedir mode for instant startup).
#
# Output: Scripts/dist/bridge/bridge
#
# Usage:
#   cd Scripts && ./build_bridge.sh
#   OR from project root: Scripts/build_bridge.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

VENV_DIR="$SCRIPT_DIR/.venv"
DIST_DIR="$SCRIPT_DIR/dist"
BUILD_DIR="$SCRIPT_DIR/build"
OUTPUT_BINARY="$DIST_DIR/bridge/bridge"

# ---------------------------------------------------------------------------
# Incremental check: skip if binary is newer than bridge.py
# ---------------------------------------------------------------------------
if [ -f "$OUTPUT_BINARY" ] && [ "$OUTPUT_BINARY" -nt "$SCRIPT_DIR/bridge.py" ]; then
    echo "[build_bridge] bridge binary is up-to-date, skipping build."
    exit 0
fi

# ---------------------------------------------------------------------------
# Activate virtual environment
# ---------------------------------------------------------------------------
if [ ! -d "$VENV_DIR" ]; then
    echo "[build_bridge] Creating virtual environment..."
    python3 -m venv "$VENV_DIR"
fi

source "$VENV_DIR/bin/activate"

# ---------------------------------------------------------------------------
# Install dependencies
# ---------------------------------------------------------------------------
echo "[build_bridge] Installing/upgrading pip dependencies..."
pip install --quiet --upgrade pip
pip install --quiet "pymobiledevice3>=2.0.0,<7.7.0"
pip install --quiet pyinstaller

# ---------------------------------------------------------------------------
# Run PyInstaller
# ---------------------------------------------------------------------------
echo "[build_bridge] Running PyInstaller..."

pyinstaller \
    --noconfirm \
    --onedir \
    --name bridge \
    --distpath "$DIST_DIR" \
    --workpath "$BUILD_DIR" \
    --specpath "$SCRIPT_DIR" \
    --strip \
    --collect-all pymobiledevice3 \
    --hidden-import pymobiledevice3.usbmux \
    --hidden-import pymobiledevice3.lockdown \
    --hidden-import pymobiledevice3.services.simulate_location \
    --hidden-import pymobiledevice3.services.dvt.dvt_secure_socket_proxy \
    --hidden-import pymobiledevice3.services.dvt.instruments.location_simulation \
    --hidden-import pymobiledevice3.tunneld.api \
    --hidden-import pymobiledevice3.remote.remote_service_discovery \
    --hidden-import xml.etree.ElementTree \
    --hidden-import json \
    --hidden-import signal \
    --hidden-import threading \
    bridge.py

# ---------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------
if [ -f "$OUTPUT_BINARY" ]; then
    echo "[build_bridge] Success: $OUTPUT_BINARY"
    ls -lh "$OUTPUT_BINARY"
else
    echo "[build_bridge] ERROR: binary not found at $OUTPUT_BINARY" >&2
    exit 1
fi
