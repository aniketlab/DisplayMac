# DisplayMac Setup & Deployment Guide

This guide covers building and configuring **DisplayMacServer** (macOS) and **DisplayMac** (Android client).

---

## 1. macOS Host Setup

### Requirements
- macOS 14.0+ (Sonoma or Sequoia, Apple Silicon or Intel)
- Xcode Command Line Tools (`xcode-select --install`)

### Automated Installation
From the repository root:
```bash
./install.sh
```
*(Or double-click `Install DisplayMac.command` in Finder.)*

For **USB-C only security mode** (binds listeners strictly to `127.0.0.1`, disabling Wi-Fi access):
```bash
./install.sh --usb-only
```

The installer:
1. Compiles and installs `DisplayMacAudio.driver` to `/Library/Audio/Plug-Ins/HAL/` (`arm64` + `x86_64`).
2. Installs standalone Google `adb` to `/usr/local/bin/adb` if not already present.
3. Builds `DisplayMacServer` in release mode and installs it to `/usr/local/bin/DisplayMacServer`.
4. Configures `~/Library/LaunchAgents/com.displaymac.server.plist` (`KeepAlive`, `RunAtLoad`).
5. Prompts for **Accessibility** permission; macOS will also prompt for **Screen Recording** when the first stream begins.

### Manual Build & Test (Development)
```bash
cd macos-server
swift build -c release
swift test
```

### Headless Mac Configuration (No Physical Monitor Attached)
If booting a desktop Mac without a monitor:
1. Turn **FileVault** off in **System Settings > Privacy & Security > FileVault** (macOS prevents LaunchAgents from starting before pre-boot FileVault decryption).
2. Enable **Automatic Login** in **System Settings > Users & Groups** so the user session starts on boot.

---

## 2. Android Client Setup

### Requirements
- Android 8.0+ (API 26+) tablet or phone with hardware HEVC decoding
- Android SDK / JDK 17 (to build from source)

### Build from Source
On macOS / Linux:
```bash
cd android-client
./gradlew testDebugUnitTest assembleDebug
```
On Windows:
```bat
cd android-client
gradlew.bat testDebugUnitTest assembleDebug
```

To install onto an ADB-connected device:
- macOS / Linux: `cd android-client && ./gradlew installDebug`
- Windows: `scripts\deploy_android.bat`

---

## 3. Connecting

### USB-C (Recommended)
1. Enable **USB Debugging** in Android Developer Options and accept the host authorization prompt.
2. Connect the USB-C cable between Mac and Android device (or run `./scripts/setup_usb_link.sh` if using manual ADB forwarding).
3. Open DisplayMac on the Android device and tap **Connect with USB-C**.

### Wi-Fi
1. Connect both devices to the same local network (5 GHz or 6 GHz recommended).
2. Open DisplayMac on the Android device; Bonjour automatically discovers your Mac host name and IP address.
3. Tap **Connect over Wi-Fi** (or use **Enter IP manually** if mDNS is blocked by your router).

---

## 4. Stylus & Touch Controls

| Tablet Input | macOS Action |
| :--- | :--- |
| **Single Tap / Double Tap** | Left click / Double click |
| **Long Press / Two-Finger Tap** | Right click (Context menu) |
| **Single-Finger Drag** | Smooth continuous scroll |
| **Double-Tap + Hold Drag** | Window / item drag |
| **Two-Finger Pinch** | Command + Scroll zoom |
| **Stylus Touch & Move** | Pressure- and tilt-aware tablet pointer input |
| **Stylus Side Button + Tap** | Secondary click |
| **Stylus Hover** | Pointer movement without clicking |
