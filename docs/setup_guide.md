# DisplayMac Setup & Deployment Guide

This guide walks you through setting up **DisplayMac** on your **Mac mini M4** and **Samsung Galaxy Tab S10 Ultra**.

---

## 🖥️ 1. Mac mini M4 Configuration (Headless Auto-Start)

When running the Mac mini without any physical display attached, you can set `DisplayMacServer` to launch automatically on boot using macOS `launchd`.

### Step 1: Build the Server on macOS
On your Mac mini:
```bash
cd macos-server
swift build -c release
```
The compiled binary will be located at:
`.build/release/DisplayMacServer`

### Step 2: Configure `launchd` Daemon (Optional - For True Headless Boot)
To make the Mac mini start the display server automatically every time it powers on:

Create `~/Library/LaunchAgents/com.displaymac.server.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.displaymac.server</string>
    <key>ProgramArguments</key>
    <array>
        <string>/path/to/DisplayMac/macos-server/.build/release/DisplayMacServer</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/displaymac.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/displaymac.error.log</string>
</dict>
</plist>
```

Load the service:
```bash
launchctl load ~/Library/LaunchAgents/com.displaymac.server.plist
```

---

## 📱 2. Android Client (Samsung Galaxy Tab S10 Ultra)

### Option A: Via Android Studio
1. Open the `android-client` folder in Android Studio.
2. Connect your Tab S10 Ultra via USB with **USB Debugging** enabled.
3. Click **Run** (`Shift + F10`).

### Option B: Via Command Line / Script
Run the automated deployment script:
- On Windows: `scripts\deploy_android.bat`
- On macOS/Linux:
  ```bash
  cd android-client
  ./gradlew installDebug
  ```

---

## ⚡ 3. Connection Modes

### Mode 1: Direct USB-C Cable (Recommended - 0ms Latency)
1. Connect a USB-C 3.2 cable between the Mac mini M4 and Galaxy Tab S10 Ultra.
2. Enable **USB Tethering** in Android Settings (`Connections > Mobile Hotspot and Tethering > USB Tethering`), OR run the USB helper:
   ```bash
   ./scripts/setup_usb_link.sh
   ```
3. Open DisplayMac on your tablet. It will instantly connect via direct wire at 120 FPS.

### Mode 2: High-Speed Wi-Fi (Wireless Freedom)
1. Ensure both your Mac mini and tablet are connected to the same Wi-Fi network (5GHz or 6GHz recommended).
2. Open DisplayMac on the tablet. The app utilizes zero-configuration **Bonjour / mDNS** to auto-discover and pair with the Mac within 1 second.

---

## 🖊️ 4. S-Pen & Touch Gestures

| Tablet Input | macOS Action |
| :--- | :--- |
| **S-Pen Touch** | Primary Click / Drag |
| **S-Pen Pressure** | Native Pressure Sensitivity (Photoshop, Figma, Illustrator) |
| **S-Pen Button + Touch** | Secondary Click (Right Click) |
| **S-Pen Hover** | Moves macOS Cursor without clicking |
| **Multi-touch Drag** | Window Scrolling & Panning |
