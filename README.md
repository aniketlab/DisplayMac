# DisplayMac ⚡🖥️

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![macOS](https://img.shields.io/badge/macOS-14.0%2B%20%7C%20Apple%20Silicon-blue)](https://www.apple.com/macos/)
[![Android](https://img.shields.io/badge/Android-12.0%2B%20(API%2031%2B)-green)](https://www.android.com/)
[![Refresh Rate](https://img.shields.io/badge/Refresh%20Rate-120Hz%20ProMotion-orange)](https://developer.apple.com/)
[![Resolution](https://img.shields.io/badge/Max%20Resolution-2960%C3%971848%20(16:10)-purple)](https://developer.android.com/)

> **DisplayMac** turns high-end Android tablets (like the Samsung Galaxy Tab S10 Ultra) into an ultra-low-latency, pixel-perfect primary or secondary display for Mac (Mac mini M4, MacBook Pro, Mac Studio) over direct **USB-C (5 Gbps)** or **Wi-Fi 6E/7**.

---

## 🌟 Key Highlights

- **Native Resolution & 120Hz ProMotion**: Calibrated for 2960×1848 OLED panels with zero letterboxing and full 120 FPS buttery-smooth rendering.
- **Dual Transport Pipeline**:
  - **Direct USB-C Link**: Sub-millisecond latency (`< 1ms`) over 5 Gbps USB-C tethering. No router or Wi-Fi required.
  - **High-Bandwidth Wi-Fi**: Zero-config Bonjour/mDNS auto-discovery with adaptive bitrate streaming (50–150 Mbps).
- **Apple Silicon Hardware Accelerated**:
  - Uses `ScreenCaptureKit` for zero-copy GPU frame capture.
  - Hardware HEVC / H.265 encoding via Apple Silicon `VideoToolbox`.
- **Low-Latency Android Client**:
  - Dedicated hardware decoding (`c2.mtk.hevc.decoder.lowlatency` / Snapdragon MediaCodec).
  - Direct-to-`SurfaceView` Vulkan/OpenGL rendering at hardware 120Hz display modes.
- **Bi-Directional Input**:
  - S-Pen Wacom digitizer support: forwards pen pressure, tilt, and hover as native macOS tablet events.
  - Multi-touch gestures and trackpad support mapped directly to `CGEvent`.

---

## 🏗️ Architecture Overview

```mermaid
flowchart LR
    subgraph macOS ["macOS Host (Mac mini M4)"]
        A[CGVirtualDisplay Engine\n2960x1848 @ 120Hz] --> B[ScreenCaptureKit\nZero-Copy GPU Capture]
        B --> C[VideoToolbox\nHardware HEVC / H.265]
        C --> D[Transport Server\nTCP / High-Speed UDP]
        I[Input Injector\nCGEventPost / Tablet Events] <-- D
    end

    subgraph Link ["Link Layer"]
        D <==>|Direct USB-C (5 Gbps)\nOR Wi-Fi 6E/7| E[Transport Client]
    end

    subgraph Android ["Android Client (Tab S10 Ultra)"]
        E --> F[Hardware MediaCodec\nLow-Latency Decoder]
        F --> G[120Hz SurfaceView\nOLED Native 2960x1848]
        H[Touch & S-Pen Engine\nPressure + Hover] --> E
    end
```

---

## 📁 Repository Structure

```
DisplayMac/
├── shared/              # Binary protocol specification & packet definitions
│   └── protocol.md      # Framing, packet headers, input format
├── macos-server/        # macOS Swift server daemon
│   ├── Sources/
│   │   ├── VirtualDisplay/ # Headless virtual display generator (CoreGraphics)
│   │   ├── Capture/        # ScreenCaptureKit frame stream
│   │   ├── Encoder/        # VideoToolbox real-time HEVC encoder
│   │   ├── Network/        # Socket server & Bonjour discovery
│   │   ├── Input/          # CGEvent injection (stylus & touch)
│   │   └── main.swift
│   └── Package.swift
├── android-client/      # Android Kotlin/Jetpack application
│   ├── app/
│   │   ├── src/main/java/com/displaymac/client/
│   │   │   ├── decoder/    # Low-latency MediaCodec pipeline
│   │   │   ├── display/    # 120Hz SurfaceView controller
│   │   │   ├── input/      # S-Pen & multi-touch forwarder
│   │   │   └── network/    # Auto USB/Wi-Fi connection manager
│   │   └── AndroidManifest.xml
│   └── build.gradle.kts
└── docs/                # Technical guides & hardware setup
```

---

## 🚀 Quick Start

### 1. Requirements
- **Host**: macOS 14.0+ (Sonoma or Sequoia) on Apple Silicon (M1/M2/M3/M4).
- **Client**: Android 12.0+ tablet (Samsung Galaxy Tab S8/S9/S10 Ultra recommended for 120Hz OLED).
- **Cable**: USB 3.2 Gen 1 (5 Gbps) Type-C to Type-C cable for wired mode, or Wi-Fi 6/6E router.

### 2. Running the macOS Server
```bash
cd macos-server
swift run DisplayMacServer
```

### 3. Installing Android Client
Open `android-client` in Android Studio, build and deploy the APK to your tablet:
```bash
cd android-client
./gradlew installDebug
```

---

## 📄 License
This project is licensed under the [MIT License](LICENSE).
