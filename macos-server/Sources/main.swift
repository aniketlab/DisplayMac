import Foundation
import CoreMedia

final class DisplayMacCoordinator: ScreenCaptureEngineDelegate, HardwareVideoEncoderDelegate, NetworkServerDelegate {
    private let displayManager = VirtualDisplayManager.shared
    private let captureEngine = ScreenCaptureEngine()
    private let videoEncoder = HardwareVideoEncoder()
    private let networkServer = NetworkServer()
    
    private var isStreaming = false
    private var encodedFrameCount: Int = 0
    private var lastStatsTime = Date()
    
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
        
        // Spawn virtual display matching tablet exact resolution
        _ = displayManager.setupVirtualDisplay(width: targetWidth, height: targetHeight, refreshRate: targetFps)
        InputInjector.shared.updateScreenBounds(width: CGFloat(targetWidth), height: CGFloat(targetHeight))
        
        // Send ServerConfig acknowledgement
        let config = ServerConfig(
            selectedCodec: .hevc,
            activeFps: UInt8(targetFps),
            streamWidth: UInt32(targetWidth),
            streamHeight: UInt32(targetHeight),
            targetBitrateKbps: 80_000 // 80 Mbps high fidelity
        )
        server.sendServerConfig(config)
        
        // Setup Hardware HEVC encoder
        _ = videoEncoder.setupSession(width: targetWidth, height: targetHeight, fps: targetFps, bitrateMbps: 80)
        
        // Launch ScreenCaptureKit pipeline
        Task {
            guard let displayID = displayManager.activeDisplayID else { return }
            do {
                try await captureEngine.startCapture(displayID: displayID, width: targetWidth, height: targetHeight, targetFps: targetFps)
                self.isStreaming = true
                print("[Coordinator] 🚀 Active streaming pipeline engaged at \(targetWidth)x\(targetHeight) @ \(targetFps) FPS!")
            } catch {
                print("[Coordinator] Error starting screen capture: \(error.localizedDescription)")
            }
        }
    }
    
    func networkServerDidDisconnectClient(_ server: NetworkServer) {
        print("\n[Coordinator] 🔌 Client disconnected. Releasing virtual display...")
        Task {
            await captureEngine.stopCapture()
        }
        displayManager.releaseVirtualDisplay()
        isStreaming = false
        print("[Coordinator] ✅ Virtual display removed. BenQ monitor is now primary and clean.")
    }
    
    func networkServerDidRequestKeyframe(_ server: NetworkServer) {
        videoEncoder.requestImmediateKeyframe()
    }
    
    // MARK: - ScreenCaptureEngineDelegate
    func captureEngine(_ engine: ScreenCaptureEngine, didCaptureSampleBuffer sampleBuffer: CMSampleBuffer) {
        videoEncoder.encode(sampleBuffer: sampleBuffer)
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
    exit(0)
}

signal(SIGTERM) { _ in
    VirtualDisplayManager.shared.releaseVirtualDisplay()
    exit(0)
}

// Start Server Loop
let coordinator = DisplayMacCoordinator()
coordinator.start()
RunLoop.main.run()
