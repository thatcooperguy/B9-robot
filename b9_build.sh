#!/bin/bash
################################################################################
#  B-9 Robot — Complete From-Scratch Build Script
#  Target: Jetson Orin Nano Super 8GB running JetPack / Ubuntu 22.04
#  Run:    sudo ./b9_build.sh
#
#  What this script does:
#    1. System packages  (espeak-ng, aplay, python3, curl, git, v4l-utils)
#    2. Python packages  (vosk, pyaudio, opencv-python, numpy)
#    3. Ollama           (CUDA-enabled, auto-detects Jetson GPU)
#    4. AI models        (qwen2.5:0.5b for chat, moondream:latest for vision)
#    5. Vosk STT model   (vosk-model-small-en-us-0.15, offline, 67MB)
#    6. B-9 application  (/opt/b9robot/b9_complete_system.py)
#    7. systemd services (ollama, b9-robot, cuda-init, daily restart timer)
#    8. ALSA audio config (/etc/asound.conf for USB speaker/mic)
#    9. Boot verification (cold-boot test checklist)
################################################################################

set -e   # exit on first error
SECONDS=0

# ─── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

ok()   { echo -e "${GREEN}  ✓ $*${NC}"; }
warn() { echo -e "${YELLOW}  ⚠ $*${NC}"; }
err()  { echo -e "${RED}  ✗ $*${NC}"; }
hdr()  { echo -e "\n${CYAN}${BOLD}=== $* ===${NC}"; }
step() { echo -e "${BOLD}--- $* ---${NC}"; }

# ─── Must run as root ──────────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Run as root: sudo ./b9_build.sh${NC}"; exit 1
fi

# ─── Config ────────────────────────────────────────────────────────────────────
B9_USER="cooper"                        # non-root user that owns the robot files
B9_DIR="/opt/b9robot"                   # application directory
VOSK_DIR="$B9_DIR/vosk-model"           # Vosk model directory
VOSK_MODEL="vosk-model-small-en-us-0.15"
VOSK_URL="https://alphacephei.com/vosk/models/${VOSK_MODEL}.zip"
CHAT_MODEL="qwen2.5:0.5b"
VISION_MODEL="moondream:latest"
SERVICE_FILE="/etc/systemd/system/b9-robot.service"
OLLAMA_OVERRIDE="/etc/systemd/system/ollama.service.d/b9-override.conf"
LOG_FILE="/var/log/b9_build.log"

# Confirm user exists
if ! id "$B9_USER" &>/dev/null; then
    warn "User '$B9_USER' not found. Using root for file ownership."
    B9_USER="root"
fi

echo -e "${CYAN}${BOLD}"
echo "  ██████╗       █████╗      ██████╗  ██████╗ ██████╗  ██████╗ ████████╗"
echo "  ██╔══██╗     ██╔══██╗     ██╔══██╗██╔═══██╗██╔══██╗██╔═══██╗╚══██╔══╝"
echo "  ██████╔╝     ███████║     ██████╔╝██║   ██║██████╔╝██║   ██║   ██║   "
echo "  ██╔══██╗     ██╔══██║     ██╔══██╗██║   ██║██╔══██╗██║   ██║   ██║   "
echo "  ██████╔╝  ██╗██║  ██║  ██╗██║  ██║╚██████╔╝██████╔╝╚██████╔╝   ██║   "
echo "  ╚═════╝   ╚═╝╚═╝  ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚═════╝  ╚═════╝   ╚═╝   "
echo -e "${NC}"
echo -e "${BOLD}  B-9 Class M-3 Environmental Control Robot — Build Script${NC}"
echo -e "  Target: Jetson Orin Nano Super 8GB"
echo -e "  Log:    $LOG_FILE"
echo ""

# Redirect all output to log as well
exec > >(tee -a "$LOG_FILE") 2>&1

################################################################################
hdr "1 / 9  System Package Dependencies"
################################################################################

step "Updating package lists"
apt-get update -qq
ok "Package lists updated"

step "Installing system packages"
PKGS=(
    # Audio
    espeak-ng
    alsa-utils          # aplay, amixer, arecord
    libasound2
    libasound2-dev
    libportaudio2
    portaudio19-dev
    # Camera / Video
    v4l-utils
    libv4l-dev
    libopencv-dev
    # Python
    python3
    python3-pip
    python3-dev
    python3-numpy
    python3-opencv
    # Network / Download
    curl
    wget
    unzip
    git
    # System
    build-essential
    pkg-config
    libjpeg-dev
    libpng-dev
)
apt-get install -y --no-install-recommends "${PKGS[@]}" -qq
ok "System packages installed"

step "Verifying critical binaries"
for bin in python3 pip3 espeak-ng aplay curl wget unzip; do
    if command -v "$bin" &>/dev/null; then
        ok "$bin: $(command -v $bin)"
    else
        err "$bin: NOT FOUND"
    fi
done

################################################################################
hdr "2 / 9  Python Package Dependencies"
################################################################################

step "Upgrading pip"
python3 -m pip install --upgrade pip --break-system-packages -q
ok "pip upgraded"

step "Installing Python packages"
PY_PKGS=(
    "vosk"                    # offline speech recognition
    "pyaudio"                 # microphone access
    "opencv-python-headless"  # camera capture (headless = no GUI deps)
    "numpy"                   # required by vosk and cv2
)
for pkg in "${PY_PKGS[@]}"; do
    echo "  Installing $pkg..."
    python3 -m pip install "$pkg" --break-system-packages -q && \
        ok "$pkg installed" || warn "$pkg install failed (may already be present)"
done

step "Verifying Python imports"
python3 -c "import vosk;   print('  vosk:   OK')"   || warn "vosk import failed"
python3 -c "import cv2;    print('  cv2:    OK')"    || warn "cv2 import failed"
python3 -c "import pyaudio; print('  pyaudio:OK')"  || warn "pyaudio import failed"
python3 -c "import numpy;  print('  numpy:  OK')"   || warn "numpy import failed"
ok "Python imports verified"

################################################################################
hdr "3 / 9  Ollama (CUDA backend)"
################################################################################

if command -v ollama &>/dev/null; then
    CURRENT_VER=$(ollama --version 2>/dev/null | awk '{print $NF}')
    ok "Ollama already installed: $CURRENT_VER"
    step "Checking if Ollama service is running"
    systemctl is-active --quiet ollama && ok "Ollama service active" || \
        warn "Ollama service not running (will fix in step 7)"
else
    step "Installing Ollama with CUDA support"
    # Official Ollama installer — auto-detects Jetson CUDA
    curl -fsSL https://ollama.com/install.sh | sh
    ok "Ollama installed: $(ollama --version 2>/dev/null)"
fi

step "Verifying Ollama CUDA backend"
# Start Ollama temporarily to check GPU
systemctl start ollama 2>/dev/null || true
sleep 3
if curl -sf http://127.0.0.1:11434/api/tags > /dev/null 2>&1; then
    ok "Ollama API responding"
else
    warn "Ollama not responding yet — will retry during model download"
    systemctl restart ollama 2>/dev/null || true
    sleep 5
fi

################################################################################
hdr "4 / 9  AI Models (qwen2.5:0.5b + moondream)"
################################################################################
# Both models must be downloaded now (internet required).
# On deployment the Jetson will be offline — models live in ~/.ollama/models/

# Ensure Ollama is running for pulls
for attempt in 1 2 3; do
    curl -sf http://127.0.0.1:11434/api/tags > /dev/null 2>&1 && break
    warn "Ollama not ready, waiting 5s (attempt $attempt)..."
    sleep 5
done

step "Pulling chat model: $CHAT_MODEL"
# Run as ollama user if it exists, otherwise root
if id "ollama" &>/dev/null; then
    sudo -u ollama ollama pull "$CHAT_MODEL" && ok "$CHAT_MODEL downloaded" || \
        { err "$CHAT_MODEL pull failed"; exit 1; }
else
    ollama pull "$CHAT_MODEL" && ok "$CHAT_MODEL downloaded" || \
        { err "$CHAT_MODEL pull failed"; exit 1; }
fi

step "Pulling vision model: $VISION_MODEL"
if id "ollama" &>/dev/null; then
    sudo -u ollama ollama pull "$VISION_MODEL" && ok "$VISION_MODEL downloaded" || \
        { err "$VISION_MODEL pull failed"; exit 1; }
else
    ollama pull "$VISION_MODEL" && ok "$VISION_MODEL downloaded" || \
        { err "$VISION_MODEL pull failed"; exit 1; }
fi

step "Verifying models are listed"
ollama list
ok "Models verified"

################################################################################
hdr "5 / 9  Vosk Offline STT Model"
################################################################################

mkdir -p "$VOSK_DIR"
TARGET_PATH="$VOSK_DIR/$VOSK_MODEL"

if [ -d "$TARGET_PATH/am" ] && [ -d "$TARGET_PATH/graph" ] && [ -d "$TARGET_PATH/conf" ]; then
    SIZE=$(du -sh "$TARGET_PATH" | cut -f1)
    ok "Vosk model already installed: $TARGET_PATH ($SIZE)"
else
    step "Downloading Vosk model (67MB)..."
    TMPZIP="/tmp/${VOSK_MODEL}.zip"
    wget -q --show-progress -O "$TMPZIP" "$VOSK_URL" && \
        ok "Downloaded $VOSK_MODEL" || { err "Vosk download failed"; exit 1; }

    step "Extracting Vosk model to $VOSK_DIR"
    # Extract directly into vosk-model dir so path is vosk-model/vosk-model-small-.../
    unzip -q "$TMPZIP" -d "$VOSK_DIR/"
    rm -f "$TMPZIP"
    ok "Vosk model extracted"

    # Verify structure
    if [ -d "$TARGET_PATH/am" ] && [ -d "$TARGET_PATH/graph" ] && [ -d "$TARGET_PATH/conf" ]; then
        SIZE=$(du -sh "$TARGET_PATH" | cut -f1)
        ok "Vosk model verified: $SIZE (am/ graph/ conf/ present)"
    else
        err "Vosk model structure invalid — expected $TARGET_PATH/am, graph, conf"
        echo "Contents of $VOSK_DIR:"
        ls -la "$VOSK_DIR/"
        exit 1
    fi
fi

chown -R "$B9_USER:$B9_USER" "$VOSK_DIR" 2>/dev/null || true

################################################################################
hdr "6 / 9  B-9 Application"
################################################################################

step "Creating application directory: $B9_DIR"
mkdir -p "$B9_DIR"

step "Installing b9_complete_system.py"
# The script expects b9_complete_system.py to be alongside this build script,
# OR it will be downloaded from a known location.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_FILE="$SCRIPT_DIR/b9_complete_system.py"

if [ -f "$SRC_FILE" ]; then
    cp "$SRC_FILE" "$B9_DIR/b9_complete_system.py"
    ok "Copied b9_complete_system.py from $SCRIPT_DIR"
else
    err "b9_complete_system.py not found alongside this script!"
    echo ""
    echo "  Expected: $SRC_FILE"
    echo "  Place b9_complete_system.py in the same directory as b9_build.sh"
    echo "  and re-run."
    exit 1
fi

chmod +x "$B9_DIR/b9_complete_system.py"
chown -R "$B9_USER:$B9_USER" "$B9_DIR" 2>/dev/null || true

step "Verifying Python syntax"
python3 -m py_compile "$B9_DIR/b9_complete_system.py" && \
    ok "Syntax OK" || { err "Syntax error in b9_complete_system.py"; exit 1; }

step "Checking b9 application imports"
python3 -c "
import sys
sys.path.insert(0, '$B9_DIR')
# Test all stdlib imports used by the app
import subprocess, threading, os, re, random, time
import socket, queue, struct, glob, json, sys, ctypes
print('  stdlib: OK')
import vosk
print('  vosk: OK')
import cv2
print('  cv2: OK')
import pyaudio
print('  pyaudio: OK')
import numpy
print('  numpy: OK')
" && ok "All imports verified" || warn "Some imports failed — check above"

################################################################################
hdr "7 / 9  systemd Service Configuration"
################################################################################

# ── 7a: cuda-init (warms CUDA context before Ollama starts) ───────────────────
step "Creating cuda-init.service"
cat > /etc/systemd/system/cuda-init.service << 'SVCEOF'
[Unit]
Description=Pre-initialize NVIDIA CUDA context on Jetson
After=local-fs.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c '\
    nvidia-smi > /dev/null 2>&1 || \
    cat /sys/devices/gpu.0/devfreq/*/cur_freq > /dev/null 2>&1 || \
    true'
TimeoutStartSec=10

[Install]
WantedBy=multi-user.target
SVCEOF
ok "cuda-init.service written"

# ── 7b: Ollama service override ────────────────────────────────────────────────
step "Creating Ollama service override"
mkdir -p /etc/systemd/system/ollama.service.d/
# Remove any conflicting drop-ins from previous installs
rm -f /etc/systemd/system/ollama.service.d/jetson-hardening.conf
rm -f /etc/systemd/system/ollama.service.d/jetson-cuda.conf
rm -f /etc/systemd/system/ollama.service.d/jetson-gpu.conf
rm -f /etc/systemd/system/ollama.service.d/single-model.conf

cat > "$OLLAMA_OVERRIDE" << 'SVCEOF'
[Unit]
After=local-fs.target cuda-init.service
Wants=cuda-init.service

[Service]
Restart=on-failure
RestartSec=5
StartLimitBurst=5
StartLimitIntervalSec=60
Environment="OLLAMA_MAX_LOADED_MODELS=1"
Environment="OLLAMA_NUM_PARALLEL=1"
Environment="OLLAMA_FLASH_ATTENTION=1"
SVCEOF
ok "Ollama override written: $OLLAMA_OVERRIDE"

# ── 7c: b9-robot.service ───────────────────────────────────────────────────────
step "Creating b9-robot.service"
PYTHON_BIN=$(command -v python3)
cat > "$SERVICE_FILE" << SVCEOF
[Unit]
Description=B-9 Environmental Control Robot - Complete System
After=ollama.service
Requires=ollama.service

[Service]
Type=simple
User=root
WorkingDirectory=$B9_DIR
ExecStart=$PYTHON_BIN $B9_DIR/b9_complete_system.py
Restart=on-failure
RestartSec=5
TimeoutStartSec=120
StandardOutput=journal
StandardError=journal
# Suppress ALSA spam from journal
SyslogIdentifier=b9-robot

[Install]
WantedBy=multi-user.target
SVCEOF
ok "b9-robot.service written: $SERVICE_FILE"

# ── 7d: b9-robot drop-in ──────────────────────────────────────────────────────
mkdir -p /etc/systemd/system/b9-robot.service.d/
cat > /etc/systemd/system/b9-robot.service.d/wait-for-ollama.conf << 'SVCEOF'
[Unit]
After=ollama.service
Requires=ollama.service

[Service]
Restart=on-failure
RestartSec=5
TimeoutStartSec=120
SVCEOF
ok "b9-robot drop-in written"

# ── 7e: Daily Ollama restart timer (prevents 72hr memory creep) ───────────────
step "Creating daily restart timer (04:00 AM)"
cat > /etc/systemd/system/b9-daily-restart.service << 'SVCEOF'
[Unit]
Description=Daily B-9 system refresh (clears model memory creep)
After=ollama.service b9-robot.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c '\
    systemctl restart ollama && \
    sleep 5 && \
    systemctl restart b9-robot'
SVCEOF

cat > /etc/systemd/system/b9-daily-restart.timer << 'SVCEOF'
[Unit]
Description=Daily B-9 restart at 4AM

[Timer]
OnCalendar=*-*-* 04:00:00
Persistent=true

[Install]
WantedBy=timers.target
SVCEOF
ok "Daily restart timer written (04:00 AM)"

# ── 7f: Enable and start everything ───────────────────────────────────────────
step "Reloading systemd and enabling services"
systemctl daemon-reload
systemctl enable cuda-init.service  && ok "cuda-init enabled"
systemctl enable ollama.service     && ok "ollama enabled"
systemctl enable b9-robot.service   && ok "b9-robot enabled"
systemctl enable b9-daily-restart.timer && ok "daily restart timer enabled"

################################################################################
hdr "8 / 9  ALSA Audio Configuration"
################################################################################

step "Detecting USB audio cards"

# Find speaker card (first non-Tegra USB card)
SPEAKER_CARD=""
MIC_CARD=""
while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*([0-9]+)[[:space:]] ]]; then
        NUM="${BASH_REMATCH[1]}"
        # Skip Tegra/NVIDIA onboard audio
        if grep -q -i "tegra\|hda\|ape\|nvidia" <<< "$line"; then continue; fi
        if [ -z "$SPEAKER_CARD" ]; then SPEAKER_CARD="$NUM"; fi
        if grep -q -i "webcam\|uac" <<< "$line"; then MIC_CARD="$NUM"; fi
    fi
done < /proc/asound/cards

# Fallback
[ -z "$SPEAKER_CARD" ] && SPEAKER_CARD="0"
[ -z "$MIC_CARD" ]     && MIC_CARD="$SPEAKER_CARD"

echo "  Detected: speaker=card$SPEAKER_CARD  mic=card$MIC_CARD"

step "Writing /etc/asound.conf"
cat > /etc/asound.conf << ALSAEOF
# B-9 Robot ALSA configuration
# Speaker: card $SPEAKER_CARD  Mic: card $MIC_CARD
# Auto-generated by b9_build.sh

pcm.!default {
    type asym
    playback.pcm "b9_speaker"
    capture.pcm  "b9_mic"
}

pcm.b9_speaker {
    type plug
    slave.pcm "hw:${SPEAKER_CARD},0"
}

pcm.b9_mic {
    type plug
    slave.pcm "hw:${MIC_CARD},0"
}

ctl.!default {
    type hw
    card ${SPEAKER_CARD}
}
ALSAEOF
ok "ALSA config written: /etc/asound.conf"

step "Setting mixer volumes"
amixer -c "$SPEAKER_CARD" sset Master 90% unmute 2>/dev/null || true
amixer -c "$SPEAKER_CARD" sset PCM    90% unmute 2>/dev/null || true
amixer -c "$MIC_CARD"     sset Mic    80% cap   2>/dev/null || true
ok "Mixer volumes set"

################################################################################
hdr "9 / 9  Starting Services & Final Verification"
################################################################################

step "Starting cuda-init"
systemctl start cuda-init.service && ok "cuda-init started" || warn "cuda-init failed (non-fatal)"

step "Starting Ollama"
systemctl restart ollama
echo "  Waiting for Ollama API (up to 30s)..."
READY=false
for i in $(seq 1 30); do
    if curl -sf http://127.0.0.1:11434/api/tags > /dev/null 2>&1; then
        ok "Ollama API ready after ${i}s"
        READY=true
        break
    fi
    sleep 1
done
$READY || { err "Ollama did not become ready in 30s"; systemctl status ollama --no-pager; }

step "Starting b9-robot"
systemctl restart b9-robot
sleep 3
if systemctl is-active --quiet b9-robot; then
    ok "b9-robot service is running"
else
    err "b9-robot failed to start"
    journalctl -u b9-robot -n 20 --no-pager
fi

################################################################################
hdr "Build Summary"
################################################################################

echo ""
echo -e "${BOLD}Service Status:${NC}"
systemctl status ollama b9-robot --no-pager | grep -E "●|Active:|Main PID:"

echo ""
echo -e "${BOLD}Installed Models:${NC}"
ollama list 2>/dev/null || echo "  (ollama list unavailable)"

echo ""
echo -e "${BOLD}File Locations:${NC}"
echo "  Application:   $B9_DIR/b9_complete_system.py"
echo "  Vosk model:    $VOSK_DIR/$VOSK_MODEL"
echo "  ALSA config:   /etc/asound.conf"
echo "  Service:       $SERVICE_FILE"
echo "  Ollama config: $OLLAMA_OVERRIDE"
echo "  Build log:     $LOG_FILE"

echo ""
echo -e "${BOLD}Audio:${NC}"
cat /proc/asound/cards | grep -v "^$" | head -8

echo ""
echo -e "${BOLD}Verify cold boot:${NC}"
echo "  sudo reboot"
echo "  # After ~30s:"
echo "  sudo systemctl status ollama b9-robot"
echo "  sudo journalctl -u b9-robot -f | grep -v 'ALSA lib\|confmisc\|pcm_\|pulse.c'"

ELAPSED=$SECONDS
echo ""
echo -e "${GREEN}${BOLD}Build complete in ${ELAPSED}s.${NC}"
echo ""
echo -e "${CYAN}  Danger, Will Robinson. All systems nominal.${NC}"
echo ""
