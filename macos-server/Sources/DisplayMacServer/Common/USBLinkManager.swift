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
            "\(home)/Library/Android/sdk/platform-tools/adb"
        ]

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                cachedAdbPath = path
                return path
            }
        }

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
        print("[USBLink] Auto-bridge watchdog started; monitoring ADB USB connections")

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .seconds(2))
        timer.setEventHandler { [weak self] in
            self?.checkAndBridge()
        }
        timer.resume()
        self.timer = timer
    }

    private func checkAndBridge() {
        guard let adb = resolveAdbPath() else { return }
        tickCount &+= 1
        syncAdbReverse(adbPath: adb)
    }

    private func runAdb(adbPath: String, arguments: [String]) -> (status: Int32, output: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: adbPath)
        proc.arguments = arguments
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return (proc.terminationStatus, output)
        } catch {
            return (-1, "")
        }
    }

    private func syncAdbReverse(adbPath: String) {
        let result = runAdb(adbPath: adbPath, arguments: ["devices"])
        guard result.status == 0 else { return }

        let lines = result.output.components(separatedBy: .newlines)
        let hasDevice = lines.contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.starts(with: "List") && trimmed.contains("\tdevice")
        }

        if hasDevice {
            let shouldReassert = !lastForwardSuccessful || (tickCount % 10 == 0)
            if shouldReassert {
                if !lastForwardSuccessful {
                    for port in ["tcp:7100", "tcp:7101", "tcp:7102"] {
                        _ = runAdb(adbPath: adbPath, arguments: ["reverse", "--remove", port])
                    }
                }

                let ports = ["tcp:7100", "tcp:7101", "tcp:7102"]
                var allOk = true
                for port in ports {
                    let res = runAdb(adbPath: adbPath, arguments: ["reverse", port, port])
                    if res.status != 0 {
                        allOk = false
                    }
                }

                if allOk && !lastForwardSuccessful {
                    print("[USBLink] USB-C ADB reverse tunnels established (ports 7100, 7101, 7102)")
                    lastForwardSuccessful = true
                }
            }
        } else {
            if lastForwardSuccessful {
                print("[USBLink] USB-C device disconnected; waiting for reconnect")
            }
            lastForwardSuccessful = false
        }
    }
}
