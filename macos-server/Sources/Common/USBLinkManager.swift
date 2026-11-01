import Foundation

public final class USBLinkManager {
    public static let shared = USBLinkManager()
    
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.displaymac.usblink", qos: .utility)
    private var lastForwardSuccessful = false
    private var cachedAdbPath: String?
    private var tickCount = 0
    
    private init() {}
    
    private func resolveAdbPath() -> String? {
        if let cached = cachedAdbPath, FileManager.default.isExecutableFile(atPath: cached) {
            return cached
        }
        
        let currentDir = FileManager.default.currentDirectoryPath
        let home = NSHomeDirectory()
        
        let candidates = [
            "/usr/local/bin/adb",
            "/opt/homebrew/bin/adb",
            "\(currentDir)/platform-tools/adb",
            "\(currentDir)/macos-server/platform-tools/adb",
            "\(home)/DisplayMac/macos-server/platform-tools/adb",
            "\(home)/Desktop/DisplayMac-main/macos-server/platform-tools/adb",
            "\(home)/Downloads/DisplayMac-main/macos-server/platform-tools/adb",
            "\(home)/Desktop/DisplayMac/macos-server/platform-tools/adb",
            "\(home)/Downloads/DisplayMac/macos-server/platform-tools/adb"
        ]
        
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                cachedAdbPath = path
                return path
            }
        }
        
        // Check standard PATH
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["adb"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty {
                cachedAdbPath = output
                return output
            }
        } catch {}
        
        return nil
    }
    
    public func startAutoBridge() {
        print("[USBLink] ⚡ Auto-Bridge watchdog initiated. Monitoring USB-C connections...")
        
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .seconds(2))
        timer.setEventHandler { [weak self] in
            self?.checkAndBridge()
        }
        timer.resume()
        self.timer = timer
    }
    
    private func checkAndBridge() {
        guard let adb = resolveAdbPath() else {
            return
        }
        
        tickCount &+= 1
        syncAdbReverse(adbPath: adb)
    }
    
    private func syncAdbReverse(adbPath: String) {
        // 1. Check if device is connected
        let checkProc = Process()
        checkProc.executableURL = URL(fileURLWithPath: adbPath)
        checkProc.arguments = ["devices"]
        let pipe = Pipe()
        checkProc.standardOutput = pipe
        
        do {
            try checkProc.run()
            checkProc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return }
            
            let lines = output.components(separatedBy: .newlines)
            let hasDevice = lines.contains { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.starts(with: "List") && trimmed.contains("device") && !trimmed.contains("unauthorized")
            }
            
            if hasDevice {
                let shouldReassert = !lastForwardSuccessful || (tickCount % 10 == 0)
                if shouldReassert {
                    if !lastForwardSuccessful {
                        // Flush any stale or dead reverse forwards before binding
                        let pClean = Process()
                        pClean.executableURL = URL(fileURLWithPath: adbPath)
                        pClean.arguments = ["reverse", "--remove-all"]
                        try? pClean.run()
                        pClean.waitUntilExit()
                    }

                    // Device connected! Forward ports: 7100 (Control), 7101 (Video), 7102 (Audio)
                    let p1 = Process()
                    p1.executableURL = URL(fileURLWithPath: adbPath)
                    p1.arguments = ["reverse", "tcp:7100", "tcp:7100"]
                    try? p1.run()
                    p1.waitUntilExit()
                    
                    let p2 = Process()
                    p2.executableURL = URL(fileURLWithPath: adbPath)
                    p2.arguments = ["reverse", "tcp:7101", "tcp:7101"]
                    try? p2.run()
                    p2.waitUntilExit()
                    
                    let p3 = Process()
                    p3.executableURL = URL(fileURLWithPath: adbPath)
                    p3.arguments = ["reverse", "tcp:7102", "tcp:7102"]
                    try? p3.run()
                    p3.waitUntilExit()
                    
                    if !lastForwardSuccessful {
                        print("[USBLink] ✅ USB-C Cable link established & ports (7100, 7101, 7102) forwarded!")
                        lastForwardSuccessful = true
                    }
                }
            } else {
                if lastForwardSuccessful {
                    print("[USBLink] 🔌 USB-C Cable disconnected. Waiting for tablet reconnect...")
                }
                lastForwardSuccessful = false
            }
        } catch {}
    }
}
