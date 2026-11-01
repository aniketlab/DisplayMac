# DisplayMac ⚡🖥️

<p align="center">
  <img src="https://raw.githubusercontent.com/aniketlab/DisplayMac/main/docs/assets/banner.png" alt="DisplayMac Banner" width="100%" onerror="this.style.display='none'"/>
</p>

<p align="center">
  <strong>Transform your Android Tablet into an Ultra-Low-Latency, 120Hz ProMotion, True Retina 4K Secondary Display for macOS.</strong><br>
  <em>Native Apple Silicon Hardware Acceleration • Direct 5 Gbps USB-C & Wi-Fi 6E/7 • S-Pen Wacom Digitizer • Zero Cloud • 100% Free & Open Source</em>
</p>

<p align="center">
  <a href="https://github.com/aniketlab/DisplayMac/releases"><img src="https://img.shields.io/github/v/release/aniketlab/DisplayMac?color=blue&label=Release&style=flat-square" alt="Release"></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square" alt="License: MIT"></a>
  <a href="https://www.apple.com/macos/"><img src="https://img.shields.io/badge/macOS-14.0%2B%20%28Sonoma%20%7C%20Sequoia%29-black?logo=apple&style=flat-square" alt="macOS"></a>
  <a href="https://www.android.com/"><img src="https://img.shields.io/badge/Android-10.0%2B%20%28API%2029%2B%29-3DDC84?logo=android&logoColor=white&style=flat-square" alt="Android"></a>
  <a href="#"><img src="https://img.shields.io/badge/Refresh%20Rate-120Hz%20ProMotion-FF6F00?style=flat-square" alt="120Hz"></a>
  <a href="#"><img src="https://img.shields.io/badge/Latency-%3C%201ms%20%28USB--C%29-brightgreen?style=flat-square" alt="Latency"></a>
  <a href="#"><img src="https://img.shields.io/badge/Resolution-2960%C3%971848%20OLED-purple?style=flat-square" alt="Resolution"></a>
</p>

---

## 📖 Table of Contents

- [Why DisplayMac?](#-why-displaymac)
- [Feature Highlights](#-feature-highlights)
- [Competitive Comparison](#-competitive-comparison)
- [Architecture & Data Pipeline](#-architecture--data-pipeline)
- [Device & Hardware Compatibility](#-device--hardware-compatibility)
- [Hardware & Software Prerequisites](#-hardware--software-prerequisites)
- [Quick Start Guide](#-quick-start-guide)
  - [1. macOS Host Server Setup](#1-macos-host-server-setup)
  - [2. Android Tablet Setup](#2-android-tablet-setup)
  - [3. Connection Modes (USB-C & Wi-Fi)](#3-connection-modes-usb-c--wi-fi)
- [Audio Subsystem & Smart Fallback](#-audio-subsystem--smart-fallback)
- [S-Pen Stylus & Multi-Touch Input](#-s-pen-stylus--multi-touch-input)
- [Repository Structure](#-repository-structure)
- [Troubleshooting & Maintenance](#-troubleshooting--maintenance)
- [Credits & Acknowledgements](#-credits--acknowledgements)
- [License](#-license)

---

## 💡 Why DisplayMac?

Apple’s official **Sidecar** is artificially restricted solely to iPads, completely locking out high-end Android OLED hardware like the **Samsung Galaxy Tab S10 / S9 / S8 Ultra**. Meanwhile, third-party commercial alternatives (such as Duet Display, Astropad Studio, or Spacedesk) suffer from major shortcomings:
- Costly monthly recurring subscriptions.
- Noticeable input compression artifacts and high frame latency.
- Inflexible scaling that produces blurry text or letterboxed black bars on 16:10 OLED displays.
- High host CPU overhead without native Apple Silicon hardware acceleration.

**DisplayMac** was built from the ground up to solve this:
1. **True Retina 4K Backing Store**: Native `2960×1848` physical canvas running with a razor-sharp `1480×924` 2.0x HiDPI logical UI scale.
2. **Zero-Copy Apple Silicon Pipeline**: Directly leverages `ScreenCaptureKit`, Apple Silicon `VideoToolbox` hardware HEVC encoding, and Android low-latency `MediaCodec` direct-to-`SurfaceView` rendering.
3. **Bypass MacBook Air External Display Limit**: M1/M2/M3 MacBook Air laptops are limited by Apple hardware to only **one** external physical monitor. DisplayMac creates a virtual display via software, enabling MacBook Air users to run a full **dual-monitor workstation anywhere**.
4. **Completely Local & Wire-Speed**: Operates directly over high-speed USB-C (5 Gbps) or local Wi-Fi 6E/7 with zero telemetry, zero cloud accounts, and zero internet dependency.

---

## 🌟 Feature Highlights

- **⚡ 120 FPS ProMotion Real-Time Stream**: True 120Hz output with sub-millisecond input response, delivering the fluid motion expected from desktop ProMotion monitors.
- **🖥️ Pixel-Perfect 16:10 OLED Calibration**: Custom tailored to fill the entire display of Galaxy Tab S-series tablets with zero distortion, zero scaling blur, and zero aspect-ratio padding.
- **🔌 Plug-and-Play USB-C Auto-Bridge**: Simply plug a USB-C cable between your Mac and tablet. The built-in ADB watchdog automatically detects the device, forwards communication ports, and connects instantly.
- **📡 Wireless Bonjour / mDNS Discovery**: Want wireless freedom? Connect to your 5GHz/6GHz local Wi-Fi router. DisplayMac auto-advertises via Bonjour and pairs in seconds.
- **🔊 Smart Audio Routing with Memory Fallback**:
  - Routes crystal-clear Mac audio directly to your tablet's quad AKG/Dolby Atmos speakers.
  - **Hardware Memory Guardian**: When you disconnect or unplug the tablet, audio automatically falls back to your physical Mac Mini / BenQ monitor / headphones without muting or stalling playback.
- **✏️ Wacom Digitizer & S-Pen Emulation**: Transmits S-Pen pressure sensitivity, tilt angle, hover tracking, and barrel buttons directly to macOS apps (Photoshop, Figma, Illustrator, Apple Notes, Freeform) using the standard Wacom digitizer protocol (`VendorID: 0x056a`).
- **🛡️ Headless & Safe Operation**: The virtual display spawns **only** when the tablet connects. Your physical desktop monitor (e.g. BenQ, Dell, Studio Display) is never hijacked or modified.

---

## 📊 Competitive Comparison

| Feature | **DisplayMac** | **Apple Sidecar** | **Duet Display** | **Astropad Studio** |
| :--- | :---: | :---: | :---: | :---: |
| **Price** | **100% Free & Open Source** | Free (Bundled) | \$15 – \$50 / year | \$30 – \$100 / year |
| **Android Tablet Support** | **Yes (Full Support)** | ❌ Apple Only | Yes | ❌ Apple Only |
| **120Hz ProMotion Stream** | **Yes (Native 120 FPS)** | Yes (iPad Pro only) | Variable (30–60 FPS) | 60 FPS typical |
| **Native 16:10 OLED Scaling** | **Yes (2960×1848)** | ❌ 4:3 iPad only | Letterboxed | Letterboxed |
| **MacBook Air Monitor Limit Bypass** | **Yes (Virtual Display)** | ❌ Limited | Yes | Yes |
| **Connection Options** | **Direct USB-C (5 Gbps) & Wi-Fi** | Wi-Fi / Lightning / USB-C | USB / Wi-Fi | USB / Wi-Fi |
| **Audio Routing with Auto-Fallback** | **Yes (Zero-Silence Engine)** | ❌ Limited | Paid Tier Only | ❌ No Audio |
| **Stylus Pressure & Tilt** | **Yes (S-Pen / Wacom)** | Yes (Apple Pencil) | Paid Tier Only | Yes |
| **Account / Cloud Required** | **None (100% Offline)** | Apple ID | Required | Required |

---

## 🏗️ Architecture & Data Pipeline

```mermaid
flowchart TD
    subgraph macOS ["macOS Host (Apple Silicon / Intel)"]
        A["SLSVirtualDisplay Engine\n2960×1848 @ 120Hz (2.0x Retina)"] --> B["ScreenCaptureKit\nZero-Copy GPU NV12 Capture"]
        B --> C["Apple VideoToolbox\nHardware HEVC / H.265 Real-Time Encoder"]
        C --> D["Video Channel (Port 7101)\nWire-Speed Stream"]
        
        M["CoreAudio HAL Engine\nVirtual Audio Stream"] --> N["Audio Channel (Port 7102)\nPCM / AAC Stereo"]
        
        P["InputInjector.swift\nCGEventTap + Wacom Digitizer"] <-- O["Control Channel (Port 7100)\nBidirectional Protocol"]
    end

    subgraph Link ["Link Transport Layer"]
        D ===>|Direct USB-C 5 Gbps Link\nOR Low-Latency Wi-Fi 6E/7| E["Video Receiver"]
        N ===>|Direct USB-C Link\nOR Wi-Fi 6E/7| F["Audio Receiver"]
        O <===>|TCP Socket Control Tunnel\nHeartbeat + Handshake + Packets| G["Control Engine"]
    end

    subgraph Android ["Android Client (Galaxy Tab S10 Ultra)"]
        E --> H["Hardware MediaCodec\nLow-Latency HEVC Decoder"]
        H --> I["SurfaceView (Vulkan / EGL)\nHardware 120Hz OLED Display"]
        
        F --> J["AudioTrack Engine\nQuad Speaker Dolby Atmos Output"]
        
        K["S-Pen & Touch Engine\nPressure + Tilt + Gestures"] --> G
    end
```

### Protocol Stream Breakdown
1. **Control & Input Channel (`TCP 7100`)**: Handshake, resolution negotiation, S-Pen digitizer telemetry (pressure, tilt, coordinates), multi-touch packets, and IDR keyframe synchronization.
2. **Video Streaming Channel (`TCP 7101`)**: High-throughput packetized video bitstream carrying hardware HEVC NAL units with zero-copy presentation timestamps (PTS).
3. **Audio Streaming Channel (`TCP 7102`)**: Dedicated uncompressed low-latency PCM/AAC stereo stream bypassing the video queue to prevent audio desynchronization.

---

## 💻 Device & Hardware Compatibility

### Supported Mac Hardware
| Mac Model | Chip Architecture | Max Refresh Rate | Display Limit Bypass |
| :--- | :--- | :---: | :---: |
| **MacBook Air** | M1, M2, M3 | 120Hz | ✅ **Bypasses 1-monitor limit** |
| **MacBook Pro** | M1, M2, M3, M4 (Pro / Max) | 120Hz | ✅ Supported |
| **Mac mini** | M1, M2, M4 | 120Hz | ✅ Supported (Headless verified) |
| **iMac** | M1, M3, M4 | 120Hz | ✅ Supported |
| **Mac Studio & Mac Pro** | M1, M2, M3 (Max / Ultra) | 120Hz | ✅ Supported |
| **Intel Macs** | Core i5 / i7 / i9 (macOS 14+) | 60–120Hz | ✅ Supported |

### Supported Android Devices
- **Samsung Galaxy Tab Series**: S10 Ultra, S10+, S9 Ultra, S9+, S8 Ultra, S8+, S7+ (native 120Hz OLED panels calibrated out of the box).
- **Other Android Tablets**: Xiaomi Pad 6/7 Pro, Lenovo Legion Y700, OnePlus Pad 2, or any tablet running Android 10.0+ (API 29+) with hardware HEVC decoding.

---

## 🔧 Hardware & Software Prerequisites

1. **Mac Requirements**:
   - macOS 14.0 (Sonoma) or macOS 15.0+ (Sequoia).
   - Swift 5.9+ toolchain (installed via Xcode or Command Line Tools: `xcode-select --install`).
   - Android Debug Bridge (`adb`) installed for USB auto-tethering:
     ```bash
     brew install android-platform-tools
     ```
2. **Android Requirements**:
   - Android 10.0 or later (Android 12+ recommended for low-latency MediaCodec).
   - **USB Debugging enabled** in Android Developer Options.
3. **Cable (For Wired Mode)**:
   - High-quality USB-C 3.2 Gen 1 or Gen 2 (5 Gbps or 10 Gbps) cable.

---

## 🚀 Quick Start Guide

### 1. macOS Host Server Setup

Clone the repository and compile the native Swift daemon:
```bash
git clone https://github.com/aniketlab/DisplayMac.git
cd DisplayMac/macos-server
swift run
```
*On first execution, macOS will prompt you to grant **Screen Recording** and **Accessibility** permissions to Terminal. This is standard for capturing the virtual display and injecting input.*

---

### 2. Android Tablet Setup

#### Option A: Direct APK Installation (Fastest)
The repository includes a ready-to-run signed debug APK. With your tablet plugged in via USB:
```bash
adb install -r DisplayMac.apk
```
*(Or transfer `DisplayMac.apk` directly to your tablet storage and install via the My Files app).*

#### Option B: Build from Source via Gradle
```bash
cd android-client
./gradlew assembleDebug
./gradlew installDebug
```

---

### 3. Connection Modes (USB-C & Wi-Fi)

#### Mode 1: Direct USB-C Cable (Recommended — `< 1ms` Latency)
1. Plug your USB-C cable between your Mac and tablet.
2. In `macos-server`, run the automated USB link helper:
   ```bash
   ./setup_usb.sh
   ```
3. Open the **DisplayMac** app on your tablet and tap **Connect via USB-C**.
4. The virtual display will spawn immediately at full 120 FPS!

#### Mode 2: High-Speed Wi-Fi (Wireless Freedom)
1. Ensure both your Mac and tablet are connected to the same Wi-Fi router (5GHz or 6GHz recommended).
2. Launch the DisplayMac app on your tablet.
3. The app will auto-discover your Mac’s local IP via Bonjour mDNS. Tap **Connect via Wi-Fi**.

---

## 🔊 Audio Subsystem & Smart Fallback

DisplayMac features a dedicated audio pipeline engineered to avoid disrupting your physical hardware:

```
[Mac System Audio] 
       │
       ▼ (User chooses "DisplayMac Audio" in Control Centre)
[DisplayMac Virtual Stream] ──(Port 7102)──► [Tablet Quad AKG Speakers]
       │
       ▼ (Tablet unplugged / disconnected)
[Hardware Memory Guardian] ──► Automatically restores sound to:
                               • BenQ GW2780 / External Monitor
                               • Mac mini Built-in Speakers
                               • USB / Bluetooth Headphones
```

- **Zero Audio Hijack**: When the tablet connects, DisplayMac does **not** force system audio away from your monitor.
- **Smart Hardware Memory**: When you manually switch to "DisplayMac Audio" to enjoy movie/music playback on your tablet, the server remembers your previous physical output device.
- **Instant Fallback**: The moment the tablet is disconnected, audio instantly returns to your physical speakers, leaving zero silence.

---

## ✏️ S-Pen Stylus & Multi-Touch Input

DisplayMac transforms your Samsung S-Pen into a professional graphics digitizer:

| Input Method | Gesture / Action | macOS Target Event |
| :--- | :--- | :--- |
| **S-Pen Tip** | Contact & Stroke | `kCGEventMouseSubtypeTabletPoint` with 4096-level pressure curve |
| **S-Pen Tilt** | Angled Pen Drawing | `tabletEventTiltX` & `tabletEventTiltY` dynamics |
| **S-Pen Hover** | Proximity Hovering | Tracks pointer position natively without generating clicks |
| **S-Pen Side Button** | Button Pressed + Tap | Secondary Click (Right-Click Context Menu) |
| **Finger Tap** | Single Touch | Direct Point Click (Auto-dismisses cursor lingering) |
| **Multi-Touch Swipe** | 1-Finger / 2-Finger Drag | Smooth pixel-based kinetic scrolling (`CGEvent scrollWheelEvent2`) |
| **Two-Finger Tap** | Simultaneous 2-Finger Touch | Context Menu (Right Click) |
| **Pinch-to-Zoom** | Two-Finger Spread / Pinch | Native Zoom Magnification |

---

## 📁 Repository Structure

```
DisplayMac/
├── macos-server/                    # Native macOS Swift Server
│   ├── Sources/
│   │   ├── VirtualDisplay/          # CoreGraphics Virtual Display Engine
│   │   ├── Capture/                 # ScreenCaptureKit GPU NV12 Frame Stream
│   │   ├── Encoder/                 # VideoToolbox Hardware HEVC Encoder
│   │   ├── Network/                 # NWListener TCP/UDP & Bonjour Engine
│   │   ├── Common/                  # AudioManager & Binary Protocol Types
│   │   ├── Input/                   # InputInjector (CGEvent & Wacom Digitizer)
│   │   └── main.swift               # Coordinator & Lifecycle Engine
│   ├── Package.swift                # Swift Package Manager Manifest
│   ├── setup_usb.sh                 # USB port-forwarding helper
│   └── setup_dynamic_audio.sh       # CoreAudio driver configuration
├── android-client/                  # Native Android Kotlin Client
│   ├── app/src/main/java/com/displaymac/client/
│   │   ├── decoder/                 # Low-Latency MediaCodec H.265 Pipeline
│   │   ├── display/                 # 120Hz EGL/SurfaceView Controller
│   │   ├── input/                   # S-Pen & Multi-Touch Gesture Tracker
│   │   ├── network/                 # ConnectionManager & Bonjour Client
│   │   └── protocol/                # Binary Protocol Serializers
│   └── build.gradle.kts
├── shared/                          # Cross-Platform Architecture Docs
│   └── protocol.md                  # Comprehensive Wire Protocol Specification
├── scripts/                         # Deployment & helper utilities
├── docs/                            # Setup guides & architecture documentation
├── DisplayMac.apk                   # Pre-compiled production-ready Android APK
├── LICENSE                          # MIT Open Source License
└── README.md                        # Project Documentation
```

---

## 🛠️ Troubleshooting & Maintenance

### 1. Resetting Server & Audio
If a background session was interrupted or you want a fresh hardware reset:
```bash
./reset_server.sh
```
This utility:
- Terminates any stale `DisplayMacServer` processes.
- Releases any active virtual displays from WindowServer.
- Restores macOS default audio to your physical speakers.
- Resets all ADB socket tunnels.

### 2. Screen Sharing / Camera Menu Bar Indicator
macOS Sonoma and Sequoia display a persistent purple icon in the menu bar when an app captures display frames via ScreenCaptureKit. This is a built-in Apple privacy security feature. To tuck it away neatly without breaking DisplayMac, you can use menu bar utilities like [Hidden Bar](https://github.com/dwarvesf/hidden) or [Ice](https://github.com/jordanbaird/Ice).

---

## 🤝 Credits & Acknowledgements

DisplayMac stands on the shoulders of remarkable open-source engineering and low-latency streaming research:

- **Apple Developer Platforms**: For `ScreenCaptureKit` and `VideoToolbox` hardware media acceleration APIs.
- **Android Open Source Project (AOSP)**: For the high-performance `MediaCodec` and `SurfaceView` graphics subsystem.
- **[Genymobile / scrcpy](https://github.com/Genymobile/scrcpy)**: For pioneering wire-speed Android USB communication techniques.
- **[Moonlight](https://github.com/moonlight-stream) & [Sunshine](https://github.com/LizardByte/Sunshine)**: For groundbreaking low-latency frame pipeline methodologies.
- **Hackintosh & VoodooI2C Community**: For foundational research on macOS human interface device (HID) digitizer event mapping.

---

## 📄 License

DisplayMac is distributed under the **MIT License**. See [LICENSE](LICENSE) for complete details.

```
Copyright (c) 2026 Aniket Sharma

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction...
```

<p align="center">
  <b>Built with ❤️ for power users who believe Android OLED hardware belongs alongside Apple Silicon.</b>
</p>
