import Foundation

public final class USBLinkManager {
    public static let shared = USBLinkManager()
    
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.displaymac.usblink", qos: .utility)
    private var lastForwardSuccessful = false
    
    private init() {}
    
    private func resolveAdbPath() -> String? {
        let currentDir = FileManager.default.currentDirectoryPath
        let candidates = [
            "\(currentDir)/platform-tools/adb",
            "\(NSHomeDirectory())/DisplayMac/macos-server/platform-tools/adb",
            "/usr/local/bin/adb",
            "/opt/homebrew/bin/adb"
        ]
        
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
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
                return output
            }
        } catch {}
        
        return nil
    }
    
    public func startAutoBridge() {
        guard let adb = resolveAdbPath() else {
            print("[USBLink] Standalone ADB not found yet. Run './setup_usb.sh' once.")
            return
        }
        
        print("[USBLink] ⚡ Auto-Bridge watchdog active using: \(adb)")
        
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .seconds(2))
        timer.setEventHandler { [weak self] in
            self?.syncAdbReverse(adbPath: adb)
        }
        timer.resume()
        self.timer = timer
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
                // Device connected! Forward both ports: 7100 and 7101
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
                
                if !lastForwardSuccessful {
                    print("[USBLink] ✅ USB-C Cable link established & ports (7100, 7101) forwarded!")
                    lastForwardSuccessful = true
                }
            } else {
                lastForwardSuccessful = false
            }
        } catch {}
    }
}
