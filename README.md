# 🤖 B-9 Environmental Control Robot

```
██████╗       █████╗      ██████╗  ██████╗ ██████╗  ██████╗ ████████╗
██╔══██╗     ██╔══██╗     ██╔══██╗██╔═══██╗██╔══██╗██╔═══██╗╚══██╔══╝
██████╔╝     ███████║     ██████╔╝██║   ██║██████╔╝██║   ██║   ██║   
██╔══██╗     ██╔══██║     ██╔══██╗██║   ██║██╔══██╗██║   ██║   ██║   
██████╔╝  ██╗██║  ██║  ██╗██║  ██║╚██████╔╝██████╔╝╚██████╔╝   ██║   
╚═════╝   ╚═╝╚═╝  ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚═════╝  ╚═════╝   ╚═╝   
```

> *"Warning. Warning. This unit is now online. All primary systems nominal."*

**B-9** is an always-on, voice-activated AI robot running on a **NVIDIA Jetson Orin Nano Super 8GB**. It listens for wake words, responds to voice commands, answers questions in the unmistakable voice and personality of the B-9 robot from *Lost in Space* (1965), and can scan its environment using an onboard AI vision model — all completely offline after initial setup.

No cloud. No subscription. No internet required. Just a robot standing by, always watching, always ready to warn you of danger.

---

## 📺 What It Does

| Capability | Details |
|---|---|
| 🎙️ **Wake word detection** | Offline, always-on via Vosk STT. Say *"robot"*, *"B9"*, *"danger"*, *"warning"* |
| 🗣️ **Voice commands** | Ask anything — B-9 responds in character via espeak-ng TTS |
| 👁️ **Vision scanning** | Say *"what do you see"* — AI describes the room through the webcam |
| 🧠 **AI reasoning** | Powered by Qwen2.5:0.5b (chat) + Moondream (vision) via Ollama |
| 📡 **TCP interface** | Send text commands over the network on port 5000 |
| ⌨️ **Keypad support** | Optional USB numpad: one key for push-to-talk, one for camera scan |
| 🔁 **Self-healing** | Watchdog restarts Ollama if unresponsive. Daily 4AM memory refresh |
| ⚡ **Fully offline** | After build, zero internet required. All models run locally on-device |

---

## 🎬 Personality

B-9 is not a chatbot. B-9 **IS** the Class M-3 General Utility Non-Theorizing Environmental Control Robot from the Jupiter 2 deep space mission.

```
You:  "What is two plus two?"
B-9:  "Two plus two equals four. This unit experiences what humans call satisfaction."

You:  "Where are you located?"
B-9:  "On the third moon of Priplanus... or so this unit's navigational banks suggest."

You:  "What do you see?"
B-9:  "My optical sensors detect the following. A person seated at a desk with two
       computer monitors and a keyboard positioned between them."

You:  "Robot, danger!"
B-9:  "Danger, Will Robinson. This unit is already aware. All sensors at maximum."
```

Fiercely loyal. Deadpan robotic humor. No contractions. Maximum 3 sentences. Occasionally quotes space coordinates from missions past.

---

## 🛠️ Hardware

### Compute
| Component | Details |
|---|---|
| **Board** | [NVIDIA Jetson Orin Nano Super 8GB Developer Kit](https://developer.nvidia.com/embedded/jetson-orin-nano-developer-kit) |
| **CPU** | 6-core Arm Cortex-A78AE |
| **GPU** | 1024-core NVIDIA Ampere with 32 Tensor Cores |
| **RAM** | 8GB LPDDR5 (shared CPU/GPU) |
| **Storage** | microSD or NVMe SSD (NVMe recommended) |
| **Power** | 7W – 25W configurable (runs at MAXN for inference) |

### Audio / Visual (All-in-One USB Device)
| Component | Details |
|---|---|
| **Webcam + Mic + Speaker** | [Oivom 1080P USB Webcam with Microphone and Speaker](https://www.amazon.com/dp/B0D3TKX352) |
| **Resolution** | 1080P HD camera, wide angle |
| **Audio** | Built-in microphone array + built-in speaker, single USB connection |
| **Privacy** | Physical privacy cover for camera lens |
| **Connection** | USB plug-and-play, no drivers required on Linux |

> **Why this webcam?** One USB cable handles camera input, microphone input, AND speaker output. No audio interface, no separate USB hub needed. The Jetson sees it as two separate ALSA devices (card 0: speaker, card 1: mic) which the software detects and routes automatically.

### Optional
| Component | Details |
|---|---|
| **Keypad** | [BTXETUEL 2-Key USB Numpad](https://www.amazon.com/) — key 1: push-to-talk, key 2: camera scan |
| **Storage** | Samsung 970 EVO NVMe 500GB (recommended for model storage) |

---

## 💻 Software Stack

| Layer | Technology | Version |
|---|---|---|
| **OS** | Ubuntu 22.04 LTS (JetPack 6.x) | 22.04 |
| **AI Runtime** | [Ollama](https://ollama.com) — CUDA backend | 0.15.6+ |
| **Chat Model** | [Qwen2.5:0.5b](https://ollama.com/library/qwen2.5) — reasoning & Q&A | Q4_K_M |
| **Vision Model** | [Moondream](https://ollama.com/library/moondream) — scene description | latest |
| **Speech-to-Text** | [Vosk](https://alphacephei.com/vosk/) — offline wake word + command recognition | 0.3.x |
| **Text-to-Speech** | [espeak-ng](https://github.com/espeak-ng/espeak-ng) — robotic voice synthesis | 1.51 |
| **Language** | Python 3.10+ | 3.10 |
| **Audio** | PyAudio + ALSA | — |
| **Vision** | OpenCV (headless) | 4.x |

### Architecture
```
                    ┌─────────────────────────────────────┐
                    │           b9_complete_system.py      │
                    │                                      │
  USB Mic ──► Vosk Wake Loop ──► Wake Word ──► Listen ──► │
                    │                                      │
  USB Cam ──► OpenCV ──► JPEG ──► Moondream ──────────────┤
                    │                                      │
  TCP :5000 ──────────────────────────────────────────────┤
                    │                                      │
  Keypad ──────────────────────────────────────────────── │
                    │                                      │
                    │  ┌─── AI Worker Queue ───────────┐  │
                    │  │  Single thread, serialized     │  │
                    │  │  Qwen2.5 ◄──► Moondream       │  │
                    │  │  Watchdog + auto-recovery      │  │
                    │  └───────────────────────────────┘  │
                    │                                      │
                    └──────────────┬──────────────────────┘
                                   │
                          espeak-ng + aplay
                                   │
                             USB Speaker 🔊
```

**Key design decisions:**
- **Single AI worker queue** — one thread processes all Ollama requests sequentially. No concurrent GPU allocations, no memory fragmentation.
- **`OLLAMA_MAX_LOADED_MODELS=1`** — Ollama auto-evicts models; no manual swap logic needed.
- **USB device wait on boot** — polls for mic/camera enumeration before starting voice listener; eliminates the need to manually restart the service after cold boot.
- **Offline-first** — Vosk STT, both AI models, and TTS all run entirely on-device with zero network calls.

---

## 🚀 Quick Start

### Prerequisites
- Jetson Orin Nano Super 8GB running JetPack 6 / Ubuntu 22.04
- Internet connection during build (offline after)
- Oivom USB webcam plugged in
- At least 8GB free storage for models

### Build & Install
On bootup of fresh OS create user name `jetson`

Open termanal

- `sudo apt update -y`
- `sudo apt upgrade -y`
- `sudo apt install git -y`
- `git clone https://github.com/thatcooperguy/B9-robot.git`
- `cd B9-robot`
- `chmod +x b9_build.sh`
- `sudo ./b9_build.sh`

The build script (~10-15 minutes) handles everything:
1. System packages (espeak-ng, ALSA, Python, OpenCV, PortAudio)
2. Python packages (vosk, pyaudio, opencv-headless, numpy)
3. Ollama with CUDA backend
4. AI model downloads (Qwen2.5:0.5b + Moondream)
5. Vosk offline STT model (67MB)
6. Application deployment to `/opt/b9robot/`
7. systemd services with correct boot ordering
8. ALSA audio configuration for USB combo device
9. Service startup and verification

### Verify it's working
```bash
# Watch the live log (filtered for readability)
sudo journalctl -u b9-robot -f | grep -v "ALSA lib\|confmisc\|pcm_\|pulse.c"
```

You should see:
```
[B-9] Initializing...
[B-9] TTS: espeak-ng
[B-9] Camera: /dev/video0 (640x480)
[B-9] Audio: speaker=0  mic=1
[B-9] Chat:   qwen2.5:0.5b
[B-9] Vision: moondream:latest
[BOOT] Waiting for USB devices to enumerate...
[BOOT] USB devices ready after 6s
[BOOT] Pre-warming qwen2.5:0.5b...
[BOOT] qwen2.5:0.5b ready in GPU
[VOICE] Wake word detection running...
[B-9 SPEAKS] Warning. Warning. B-9 online. All systems nominal.
```

---

## 🎙️ Voice Commands

All commands start with a **wake word**: `robot`, `b9`, `b-9`, `hey robot`, `danger`, or `warning`.

| Say | B-9 Does |
|---|---|
| *"Robot"* | Wakes up, listens for command |
| *"What do you see"* | Captures frame, runs Moondream vision AI, describes the scene |
| *"Scan"* | Same as above |
| *"Status"* | Reports temperature, uptime, AI queue depth |
| *"Clear"* | Wipes conversation history |
| *"What is [anything]"* | Answers via Qwen2.5 in B-9's voice |
| *"Danger, Will Robinson"* | You know what happens |

**TCP interface** (port 5000) — send any text command over the network:
```bash
echo "what is the capital of Texas" | nc 192.168.1.x 5000
```

---

## 📁 File Structure

```
/opt/b9robot/
├── b9_complete_system.py          # Main application
└── vosk-model/
    └── vosk-model-small-en-us-0.15/
        ├── am/                    # Acoustic model
        ├── graph/                 # Language graph
        └── conf/                  # Configuration

/etc/systemd/system/
├── cuda-init.service              # Pre-warms CUDA context at boot
├── b9-robot.service               # Main application service
├── b9-daily-restart.service       # Memory refresh service
├── b9-daily-restart.timer         # Triggers restart at 04:00 AM
└── ollama.service.d/
    └── b9-override.conf           # OLLAMA_MAX_LOADED_MODELS=1 etc.

/etc/asound.conf                   # USB audio routing (auto-generated)
```

---

## 🔧 Service Management

```bash
# Start / stop / restart
sudo systemctl start b9-robot
sudo systemctl stop b9-robot
sudo systemctl restart b9-robot

# Live logs
sudo journalctl -u b9-robot -f | grep -v "ALSA lib\|confmisc\|pcm_\|pulse.c"

# Check all B-9 services
sudo systemctl status ollama b9-robot

# Force immediate daily restart (for testing)
sudo systemctl start b9-daily-restart.service
```

---

## 🧪 Troubleshooting

**Voice not working after fresh boot**
The USB mic may not have enumerated yet. The system auto-waits up to 20 seconds — if it still fails, restart the service:
```bash
sudo systemctl restart b9-robot
```

**Vision returns "OpenCV fallback" description**
Moondream ran out of GPU memory. Ensure `OLLAMA_MAX_LOADED_MODELS=1` is set:
```bash
sudo cat /etc/systemd/system/ollama.service.d/b9-override.conf
```

**B-9 doesn't answer questions correctly (gives wrong answers)**
This means Moondream loaded instead of Qwen2.5 for chat. Verify both models are installed:
```bash
ollama list
# Should show: qwen2.5:0.5b AND moondream:latest
```

**Ollama service won't start after reboot**
Check for conflicting service drop-ins:
```bash
ls /etc/systemd/system/ollama.service.d/
# Should only contain: b9-override.conf
```

**Audio card numbers changed after reboot**
Unplug and replug the USB webcam, then restart:
```bash
cat /proc/asound/cards   # verify card numbers
sudo systemctl restart b9-robot
```

---

## ⚙️ Configuration

Key settings at the top of `b9_complete_system.py`:

```python
# Wake words — any of these trigger the listen cycle
WAKE_WORDS = ["robot", "b9", "b-9", "hey robot", "danger", "warning"]

# TTS voice character
ESPEAK_PITCH = 35     # Lower = deeper robotic voice
ESPEAK_SPEED = 128    # Words per minute
ESPEAK_AMP   = 185    # Volume amplitude

# AI inference parameters
CHAT_OPTIONS = {
    "temperature": 0.7,   # Response creativity
    "num_predict": 120,   # Max response tokens (~3 sentences)
    "num_ctx": 384,       # Context window (saves VRAM vs default 2048)
    "num_keep": 48,       # Keeps B-9 persona tokens resident
}
```

---

## 📊 Resource Usage

Measured on Jetson Orin Nano Super 8GB at MAXN power mode:

| State | RAM Used | GPU Mem | CPU |
|---|---|---|---|
| Idle (listening) | ~1.2GB | ~400MB (Qwen2.5 resident) | <5% |
| Chat inference | ~1.8GB | ~900MB | 15-25% |
| Vision scan | ~2.1GB | ~1.7GB (Moondream loaded) | 20-30% |
| Peak (vision response) | ~2.4GB | ~1.8GB | 30% |

Comfortable headroom within 8GB. No swap needed.

---

## 🔌 Boot Sequence

```
Power on
    └─► cuda-init.service      (warms NVIDIA CUDA context, ~2s)
            └─► ollama.service  (starts AI runtime, ~5s)
                    └─► b9-robot.service
                            ├─ Load Vosk STT model (offline, ~2s)
                            ├─ Wait for USB devices (mic + camera, up to 20s)
                            ├─ Pre-warm Qwen2.5 into GPU (~8s)
                            ├─ Start voice listener
                            └─ "Warning. Warning. B-9 online."
                                        ▲
                              Total: ~30-40 seconds
```

---

## 🙏 Credits & Inspiration

- **B-9 Robot** — Created by Robert Kinoshita for *Lost in Space* (1965, Irwin Allen Productions). Voice of B-9: Dick Tufeld.
- **Ollama** — [ollama.com](https://ollama.com) — local LLM runtime
- **Qwen2.5** — Alibaba DAMO Academy — chat and reasoning model
- **Moondream** — vikhyatk — lightweight vision-language model
- **Vosk** — Alpha Cephei — offline speech recognition
- **NVIDIA Jetson** — edge AI compute platform

---

## ⚠️ Disclaimer

This project is a fan-made homage to the B-9 robot from *Lost in Space*. It is not affiliated with or endorsed by the original creators, CBS, Netflix, or any rights holders. The B-9 character and associated phrases are the property of their respective owners.

---

<div align="center">

*"Danger, Will Robinson."*

**B-9 Class M-3 General Utility Non-Theorizing Environmental Control Robot**  
*Jupiter 2 Deep Space Mission — Always Watching, Always Ready*

</div>
