import Foundation
import CoreMedia
import ApplicationServices
import IOKit.pwr_mgt

final class DisplayMacCoordinator: ScreenCaptureEngineDelegate, HardwareVideoEncoderDelegate, NetworkServerDelegate {
    private let displayManager = VirtualDisplayManager.shared
    private let captureEngine = ScreenCaptureEngine()
    private let videoEncoder = HardwareVideoEncoder()
    private let networkServer = NetworkServer()
    
    private var isStreaming = false
    private var encodedFrameCount: Int = 0
    private var lastStatsTime = Date()
    private var powerAssertionID: IOPMAssertionID = 0
    
    private func preventSleep() {
        guard powerAssertionID == 0 else { return }
        let reason = "DisplayMac Active Streaming" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &powerAssertionID
        )
        if result == kIOReturnSuccess {
            print("[Power] ⚡ Sleep prevention assertion engaged: Mac mini will stay awake while streaming.")
        }
    }
    
    private func allowSleep() {
        guard powerAssertionID != 0 else { return }
        IOPMAssertionRelease(powerAssertionID)
        powerAssertionID = 0
        print("[Power] 💤 Sleep prevention assertion released.")
    }
    
    init() {
        captureEngine.delegate = self
        videoEncoder.delegate = self
        networkServer.delegate = self
    }
    
    func start() {
        print("""
        ============================================================
           DisplayMac Server ⚡ Native 120Hz Apple Silicon Host
        ============================================================
        [Host] Initializing network listeners...
        """)
        
        // Start TCP/Bonjour Network Server
        do {
            try networkServer.start()
        } catch {
            print("[Host] Fatal: Failed to bind network server: \(error)")
            exit(1)
        }
        
        let ips = getLocalIPs()
        let ipList = ips.isEmpty ? "127.0.0.1" : ips.joined(separator: " or ")
        
        // Start automatic USB-C cable bridge watchdog (auto-forwards 7100, 7101, 7102 whenever tablet is plugged)
        USBLinkManager.shared.startAutoBridge()
        
        // Initialize dynamic audio driver state
        AudioManager.shared.setActive(false)
        AudioManager.shared.setDynamicDeviceName("DisplayMac Audio")
        
        // Verify Accessibility permissions for S-Pen and Mouse injection
        checkAccessibilityPermissions()
        
        print("""
        [Host] 🟢 Ready & Listening!
        • Mac IP Address(es): \(ipList)
        • Control Port:       \(ProtocolConstants.controlPort)
        • Video Port:         \(ProtocolConstants.videoPort)
        • Headless Safeguard: Virtual display will spawn ONLY after tablet connects!
                              (Your physical BenQ monitor will NOT be affected)
        
        👉 Enter this IP on your tablet: \(ips.first ?? "127.0.0.1")
        Waiting for DisplayMacClient connection...
        """)
    }
    
    // MARK: - NetworkServerDelegate
    func networkServer(_ server: NetworkServer, didConnectClient hello: ClientHello) {
        print("\n[Coordinator] ⚡ Tablet Connected! Handshake: \(hello.displayWidth)x\(hello.displayHeight) @ \(hello.maxRefreshRate)Hz")
        
        let targetWidth = Int(hello.displayWidth)
        let targetHeight = Int(hello.displayHeight)
        let targetFps = Int(hello.maxRefreshRate)
        
        let isUsb = server.isClientLoopback
        let targetBitrateMbps = isUsb ? 60 : 35
        print("[Coordinator] 🔗 Connection Link: \(isUsb ? "⚡ USB-C Direct Cable (60 Mbps Ultra-Low Latency)" : "📶 Wi-Fi Wireless (35 Mbps)")")
        
        // Spawn or reuse virtual display matching tablet exact resolution with HiDPI Retina modes
        _ = displayManager.setupVirtualDisplay(width: targetWidth, height: targetHeight, refreshRate: targetFps)
        
        guard let displayID = displayManager.activeDisplayID else {
            print("[Coordinator] ❌ Could not acquire virtual display. Aborting capture.")
            return
        }
        
        // Prevent Mac Mini sleep while tablet is connected
        preventSleep()
        
        let physicalDisplays = displayManager.getPhysicalDisplayIDs()
        if physicalDisplays.isEmpty {
            print("[Coordinator] 🖥️ Headless Mode Active: No physical monitor detected. Tablet is serving as the PRIMARY display (ID: \(displayID)).")
        } else {
            print("[Coordinator] 🖥️ Multi-Monitor Mode Active: Physical display detected. Tablet is serving as secondary HiDPI display (ID: \(displayID)).")
        }
        
        InputInjector.shared.updateActiveDisplay(displayID: displayID)
        let bounds = CGDisplayBounds(displayID)
        InputInjector.shared.updateScreenBounds(originX: bounds.origin.x, originY: bounds.origin.y, width: bounds.width, height: bounds.height)
        print("[Coordinator] Touch/Stylus bounds mapped to logical: (\(Int(bounds.origin.x)), \(Int(bounds.origin.y)), \(Int(bounds.width))x\(Int(bounds.height))) (HiDPI Retina)")
        
        // Send ServerConfig acknowledgement
        let config = ServerConfig(
            selectedCodec: .hevc,
            activeFps: UInt8(targetFps),
            streamWidth: UInt32(targetWidth),
            streamHeight: UInt32(targetHeight),
            targetBitrateKbps: UInt32(targetBitrateMbps * 1000)
        )
        server.sendServerConfig(config)
        
        // Setup Hardware HEVC encoder with medium-optimized bitrate
        _ = videoEncoder.setupSession(width: targetWidth, height: targetHeight, fps: targetFps, bitrateMbps: targetBitrateMbps)
        
        // Activate Tablet Audio & save active physical audio device (BenQ monitor or Mac mini speakers)
        AudioManager.shared.setActive(true)
        AudioManager.shared.saveCurrentOutputDevice()
        
        // Smart Dynamic Audio Naming based on connected device handshake
        let deviceModel = hello.deviceName.isEmpty ? "Samsung Galaxy Tab S10 Ultra" : hello.deviceName
        let dynamicName = "\(deviceModel) (DisplayMac)"
        AudioManager.shared.setDynamicDeviceName(dynamicName)
        
        if let tabletAudio = AudioManager.shared.findTabletAudioDevice() {
            // Start capturing direct audio loopback from the tablet virtual device
            _ = AudioManager.shared.startCapturing(deviceID: tabletAudio.id) { [weak self] pcmData in
                self?.networkServer.broadcastAudioFrame(pcmData: pcmData)
            }
            
            // Save active physical output for automatic fallback
            AudioManager.shared.saveCurrentOutputDevice()
            
            let activePhysical = AudioManager.shared.getPhysicalDefaultDeviceName()
            print("[Audio] 🔈 Dynamic Audio Driver ready: '\(dynamicName)'")
            print("        • Current physical sound remains on: '\(activePhysical)'")
            print("        • To listen on tablet, simply select '\(dynamicName)' from macOS Volume menu.")
            print("        • If tablet is unplugged, sound will automatically fall back to '\(activePhysical)'!")
        } else {
            print("[Audio] 🔈 Tip: Run './setup_dynamic_audio.sh' once to enable the dynamic tablet speaker in your Sound menu.")
        }
        
        // Launch ScreenCaptureKit pipeline
        Task {
            if captureEngine.isRunning {
                await captureEngine.stopCapture()
            }
            do {
                try await captureEngine.startCapture(displayID: displayID, width: targetWidth, height: targetHeight, targetFps: targetFps)
                self.isStreaming = true
                self.videoEncoder.requestImmediateKeyframe()
                print("[Coordinator] 🚀 Active streaming pipeline engaged at \(targetWidth)x\(targetHeight) @ \(targetFps) FPS!")
            } catch {
                print("[Coordinator] Error starting screen capture: \(error.localizedDescription)")
            }
        }
    }
    
    func networkServerDidDisconnectClient(_ server: NetworkServer) {
        print("\n[Coordinator] 🔌 Client disconnected. Pausing capture...")
        allowSleep()
        AudioManager.shared.setActive(false)
        AudioManager.shared.stopCapturing()
        AudioManager.shared.setDynamicDeviceName("DisplayMac Audio")
        AudioManager.shared.restorePreviousOutputDevice()
        Task {
            await captureEngine.stopCapture()
        }
        isStreaming = false
        print("[Coordinator] ⏸️ Capture paused. Virtual display preserved for instantaneous 0-delay reconnect!")
    }
    
    func networkServerDidRequestKeyframe(_ server: NetworkServer) {
        videoEncoder.requestImmediateKeyframe()
    }
    
    // MARK: - ScreenCaptureEngineDelegate
    func captureEngine(_ engine: ScreenCaptureEngine, didCaptureSampleBuffer sampleBuffer: CMSampleBuffer) {
        videoEncoder.encode(sampleBuffer: sampleBuffer)
    }
    
    func captureEngine(_ engine: ScreenCaptureEngine, didCaptureAudioData data: Data) {
        // Direct CoreAudio HAL in AudioManager handles tablet audio loopback
    }
    
    // MARK: - HardwareVideoEncoderDelegate
    func videoEncoder(_ encoder: HardwareVideoEncoder, didEncodePacket data: Data, isKeyframe: Bool, pts: CMTime) {
        networkServer.broadcastVideoFrame(naluData: data, isKeyframe: isKeyframe, pts: pts)
        
        encodedFrameCount += 1
        let now = Date()
        if now.timeIntervalSince(lastStatsTime) >= 2.0 {
            let fps = Double(encodedFrameCount) / now.timeIntervalSince(lastStatsTime)
            print(String(format: "[Stats] ⚡ Stream active: %.1f FPS | HEVC VideoToolbox Encoded | Packets Sent: %d", fps, encodedFrameCount))
            encodedFrameCount = 0
            lastStatsTime = now
        }
    }
}

// Local IP Address Helper
func getLocalIPs() -> [String] {
    var addresses = [String]()
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return [] }
    defer { freeifaddrs(ifaddr) }
    
    for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
        let flags = Int32(ptr.pointee.ifa_flags)
        let addr = ptr.pointee.ifa_addr.pointee
        if (flags & (IFF_UP|IFF_RUNNING|IFF_LOOPBACK)) == (IFF_UP|IFF_RUNNING) {
            if addr.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(ptr.pointee.ifa_addr, socklen_t(addr.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let name = String(cString: hostname)
                    let ifName = String(cString: ptr.pointee.ifa_name)
                    if ifName.hasPrefix("en") || ifName.hasPrefix("bridge") {
                        addresses.append("\(name) (\(ifName))")
                    }
                }
            }
        }
    }
    return addresses
}

// Global Signal Handling for Graceful Shutdown
signal(SIGINT) { _ in
    print("\n[Host] Shutting down DisplayMac Server gracefully...")
    VirtualDisplayManager.shared.releaseVirtualDisplay()
    AudioManager.shared.restorePreviousOutputDevice()
    AudioManager.shared.restorePhysicalMacAudio()
    exit(0)
}

signal(SIGTERM) { _ in
    VirtualDisplayManager.shared.releaseVirtualDisplay()
    AudioManager.shared.restorePreviousOutputDevice()
    AudioManager.shared.restorePhysicalMacAudio()
    exit(0)
}

func checkAccessibilityPermissions() {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    let isTrusted = AXIsProcessTrustedWithOptions(options)
    if !isTrusted {
        print("⚠️ [Input] Accessibility permission required! macOS prompt has appeared to authorize Terminal/DisplayMacServer in System Settings > Privacy & Security > Accessibility.")
    } else {
        print("✅ [Input] Accessibility permission verified (S-Pen & Mouse injection active).")
    }
}

// Check for command-line helper flags
if CommandLine.arguments.contains("--check-permissions") {
    checkAccessibilityPermissions()
    exit(0)
}

// Start Server Loop
let coordinator = DisplayMacCoordinator()
coordinator.start()
RunLoop.main.run()
