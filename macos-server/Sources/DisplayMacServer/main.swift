import Foundation
import CoreMedia
import ApplicationServices
import IOKit.pwr_mgt
import DisplayMacProtocol

final class DisplayMacCoordinator: ScreenCaptureEngineDelegate, HardwareVideoEncoderDelegate, NetworkServerDelegate {
    private let displayManager = VirtualDisplayManager.shared
    private let captureEngine = ScreenCaptureEngine()
    private let videoEncoder = HardwareVideoEncoder()
    private let networkServer = NetworkServer()

    private var isStreaming = false
    private var encodedFrameCount: Int = 0
    private var lastStatsTime = Date()
    private var powerAssertionID: IOPMAssertionID = 0

    init() {
        captureEngine.delegate = self
        videoEncoder.delegate = self
        networkServer.delegate = self
    }

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
            print("[Power] Idle system sleep prevention enabled while streaming")
        }
    }

    private func allowSleep() {
        guard powerAssertionID != 0 else { return }
        IOPMAssertionRelease(powerAssertionID)
        powerAssertionID = 0
        print("[Power] Idle system sleep prevention released")
    }

    func start(usbOnly: Bool = false) {
        print("""
        ============================================================
          DisplayMac Server (macOS Host)
        ============================================================
        """)

        do {
            try networkServer.start(bindLocalhostOnly: usbOnly)
        } catch {
            print("[Host] Fatal: Failed to bind network server: \(error)")
            exit(1)
        }

        USBLinkManager.shared.startAutoBridge()

        AudioManager.shared.setActive(false)
        AudioManager.shared.setDynamicDeviceName("DisplayMac Audio")

        checkAccessibilityPermissions()

        if usbOnly {
            print("[Host] USB-only mode enabled (bound exclusively to 127.0.0.1)")
        } else {
            let ips = getLocalIPs()
            let ipList = ips.isEmpty ? "127.0.0.1" : ips.joined(separator: ", ")
            print("[Host] Local interface(s): \(ipList)")
        }
        print("[Host] Listening on ports \(ProtocolConstants.controlPort), \(ProtocolConstants.videoPort), \(ProtocolConstants.audioPort)")
        print("[Host] Virtual display spawns only when a client connects.")
    }

    // MARK: - NetworkServerDelegate
    func networkServer(_ server: NetworkServer, didConnectClient hello: ClientHello, isLoopback: Bool) {
        print("\n[Coordinator] Client connected: \(hello.displayWidth)x\(hello.displayHeight) @ \(hello.maxRefreshRate)Hz")

        let targetWidth = Int(hello.displayWidth)
        let targetHeight = Int(hello.displayHeight)
        let targetFps = Int(hello.maxRefreshRate)
        let targetDpi = Int(hello.dpi)

        let targetBitrateMbps = isLoopback ? 60 : 35
        print("[Coordinator] Transport: \(isLoopback ? "USB-C loopback (60 Mbps)" : "Wi-Fi LAN (35 Mbps)")")

        guard displayManager.setupVirtualDisplay(
            width: targetWidth,
            height: targetHeight,
            refreshRate: targetFps,
            dpi: targetDpi
        ), let displayID = displayManager.activeDisplayID else {
            print("[Coordinator] Error: Could not acquire virtual display; aborting capture")
            return
        }

        preventSleep()

        let physicalDisplays = displayManager.getPhysicalDisplayIDs()
        if physicalDisplays.isEmpty {
            print("[Coordinator] Headless mode active: virtual display ID \(displayID) is primary")
        } else {
            print("[Coordinator] Extended mode active: virtual display ID \(displayID) added")
        }

        InputInjector.shared.updateActiveDisplay(displayID: displayID)
        let bounds = CGDisplayBounds(displayID)
        InputInjector.shared.updateScreenBounds(
            originX: bounds.origin.x,
            originY: bounds.origin.y,
            width: bounds.width,
            height: bounds.height
        )
        print("[Coordinator] Input bounds: (\(Int(bounds.origin.x)), \(Int(bounds.origin.y)), \(Int(bounds.width))x\(Int(bounds.height)))")

        let config = ServerConfig(
            selectedCodec: .hevc,
            activeFps: UInt8(min(targetFps, 255)),
            streamWidth: UInt32(targetWidth),
            streamHeight: UInt32(targetHeight),
            targetBitrateKbps: UInt32(targetBitrateMbps * 1000)
        )
        server.sendServerConfig(config)

        _ = videoEncoder.setupSession(width: targetWidth, height: targetHeight, fps: targetFps, bitrateMbps: targetBitrateMbps)

        AudioManager.shared.setActive(true)
        AudioManager.shared.saveCurrentOutputDevice()

        let deviceModel = hello.deviceName.isEmpty ? "Android Tablet" : hello.deviceName
        let dynamicName = "\(deviceModel) (DisplayMac)"
        AudioManager.shared.setDynamicDeviceName(dynamicName)

        if let tabletAudio = AudioManager.shared.findTabletAudioDevice() {
            _ = AudioManager.shared.startCapturing(deviceID: tabletAudio.id) { [weak self] pcmData in
                self?.networkServer.broadcastAudioFrame(pcmData: pcmData)
            }
            let activePhysical = AudioManager.shared.getPhysicalDefaultDeviceName()
            print("[Audio] Virtual speaker ready as '\(dynamicName)' (system audio remains on '\(activePhysical)')")
        } else {
            print("[Audio] Virtual driver not installed; run './macos-server/setup_dynamic_audio.sh' to enable audio routing")
        }

        Task {
            if captureEngine.isRunning {
                await captureEngine.stopCapture()
            }
            do {
                try await captureEngine.startCapture(
                    displayID: displayID,
                    width: targetWidth,
                    height: targetHeight,
                    targetFps: targetFps
                )
                self.isStreaming = true
                self.videoEncoder.requestImmediateKeyframe()
                print("[Coordinator] Streaming pipeline engaged at \(targetWidth)x\(targetHeight) @ \(targetFps) FPS")
            } catch {
                print("[Coordinator] Error starting screen capture: \(error.localizedDescription)")
            }
        }
    }

    func networkServerDidDisconnectClient(_ server: NetworkServer) {
        print("\n[Coordinator] Client disconnected; pausing capture")
        allowSleep()
        AudioManager.shared.setActive(false)
        AudioManager.shared.stopCapturing()
        AudioManager.shared.setDynamicDeviceName("DisplayMac Audio")
        AudioManager.shared.restorePreviousOutputDevice()
        Task {
            await captureEngine.stopCapture()
        }
        isStreaming = false
    }

    func networkServerDidRequestKeyframe(_ server: NetworkServer) {
        videoEncoder.requestImmediateKeyframe()
    }

    func shutdown() {
        allowSleep()
        networkServer.stop()
        VirtualDisplayManager.shared.releaseVirtualDisplay()
        AudioManager.shared.stopCapturing()
        AudioManager.shared.restorePreviousOutputDevice()
        AudioManager.shared.restorePhysicalMacAudio()
    }

    // MARK: - ScreenCaptureEngineDelegate
    func captureEngine(_ engine: ScreenCaptureEngine, didCaptureSampleBuffer sampleBuffer: CMSampleBuffer) {
        videoEncoder.encode(sampleBuffer: sampleBuffer)
    }

    func captureEngine(_ engine: ScreenCaptureEngine, didCaptureAudioData data: Data) {}

    // MARK: - HardwareVideoEncoderDelegate
    func videoEncoder(_ encoder: HardwareVideoEncoder, didEncodePacket data: Data, isKeyframe: Bool, pts: CMTime) {
        networkServer.broadcastVideoFrame(naluData: data, isKeyframe: isKeyframe, pts: pts)

        encodedFrameCount += 1
        let now = Date()
        let interval = now.timeIntervalSince(lastStatsTime)
        if interval >= 2.0 {
            let fps = Double(encodedFrameCount) / interval
            print(String(format: "[Stats] %.1f FPS | HEVC packets: %d", fps, encodedFrameCount))
            encodedFrameCount = 0
            lastStatsTime = now
        }
    }
}

func getLocalIPs() -> [String] {
    var addresses = [String]()
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return [] }
    defer { freeifaddrs(ifaddr) }

    for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
        let flags = Int32(ptr.pointee.ifa_flags)
        let addr = ptr.pointee.ifa_addr.pointee
        if (flags & (IFF_UP | IFF_RUNNING | IFF_LOOPBACK)) == (IFF_UP | IFF_RUNNING),
           addr.sa_family == UInt8(AF_INET) {
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
    return addresses
}

func checkAccessibilityPermissions() {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    let isTrusted = AXIsProcessTrustedWithOptions(options)
    if !isTrusted {
        print("[Input] Accessibility permission required; authorize DisplayMacServer in System Settings > Privacy & Security > Accessibility")
    } else {
        print("[Input] Accessibility permission verified")
    }
}

if CommandLine.arguments.contains("--check-permissions") {
    checkAccessibilityPermissions()
    exit(0)
}

let usbOnlyMode = CommandLine.arguments.contains("--usb-only")
let coordinator = DisplayMacCoordinator()

// Safe POSIX signal handling via GCD DispatchSource (async-signal-safe).
signal(SIGINT, SIG_IGN)
signal(SIGTERM, SIG_IGN)

let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
sigintSource.setEventHandler {
    print("\n[Host] Shutting down DisplayMacServer...")
    coordinator.shutdown()
    exit(0)
}
sigintSource.resume()

let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
sigtermSource.setEventHandler {
    coordinator.shutdown()
    exit(0)
}
sigtermSource.resume()

coordinator.start(usbOnly: usbOnlyMode)
RunLoop.main.run()
