import Foundation
import AppKit

public final class DisplayMacMenuManager: NSObject {
    public static let shared = DisplayMacMenuManager()
    
    private var statusItem: NSStatusItem?
    private var brightnessSlider: NSSlider?
    private var currentBrightness: Float = 0.80
    private var lastFileModTime: Date?
    
    public var onBrightnessChanged: ((Float) -> Void)?
    
    private override init() {
        super.init()
    }
    
    public func setupMenu() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Set as accessory app (Menu bar presence without dock clutter)
            NSApplication.shared.setActivationPolicy(.accessory)
            
            let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = statusItem.button {
                button.title = "🖥️ DisplayMac"
            }
            
            let menu = NSMenu()
            
            // 1. Header
            let titleItem = NSMenuItem(title: "DisplayMac • 120Hz AMOLED", action: nil, keyEquivalent: "")
            titleItem.isEnabled = false
            menu.addItem(titleItem)
            
            // 2. Connected Device
            let deviceItem = NSMenuItem(title: "📱 Ready to Connect", action: nil, keyEquivalent: "")
            deviceItem.tag = 100
            deviceItem.isEnabled = false
            menu.addItem(deviceItem)
            
            menu.addItem(NSMenuItem.separator())
            
            // 3. Brightness Section Title
            let bTitle = NSMenuItem(title: "☀️ AMOLED Brightness: 80%", action: nil, keyEquivalent: "")
            bTitle.tag = 200
            bTitle.isEnabled = false
            menu.addItem(bTitle)
            
            // 4. Brightness Slider View
            let sliderItem = NSMenuItem()
            let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 230, height: 32))
            
            let slider = NSSlider(value: 80, minValue: 5, maxValue: 100, target: self, action: #selector(self.sliderMoved(_:)))
            slider.frame = NSRect(x: 15, y: 6, width: 200, height: 20)
            slider.isContinuous = true
            containerView.addSubview(slider)
            sliderItem.view = containerView
            menu.addItem(sliderItem)
            self.brightnessSlider = slider
            
            // 5. Presets (25%, 50%, 75%, Max)
            let presetsItem = NSMenuItem()
            let presetView = NSView(frame: NSRect(x: 0, y: 0, width: 230, height: 28))
            
            let p25 = NSButton(title: "25%", target: self, action: #selector(self.setPreset25))
            p25.frame = NSRect(x: 15, y: 2, width: 44, height: 24)
            p25.bezelStyle = .roundRect
            
            let p50 = NSButton(title: "50%", target: self, action: #selector(self.setPreset50))
            p50.frame = NSRect(x: 65, y: 2, width: 44, height: 24)
            p50.bezelStyle = .roundRect
            
            let p75 = NSButton(title: "75%", target: self, action: #selector(self.setPreset75))
            p75.frame = NSRect(x: 115, y: 2, width: 44, height: 24)
            p75.bezelStyle = .roundRect
            
            let p100 = NSButton(title: "Max", target: self, action: #selector(self.setPreset100))
            p100.frame = NSRect(x: 165, y: 2, width: 50, height: 24)
            p100.bezelStyle = .roundRect
            
            presetView.addSubview(p25)
            presetView.addSubview(p50)
            presetView.addSubview(p75)
            presetView.addSubview(p100)
            presetsItem.view = presetView
            menu.addItem(presetsItem)
            
            menu.addItem(NSMenuItem.separator())
            
            // 6. Audio Info
            let audioItem = NSMenuItem(title: "🔊 AKG Quad Audio: Port 7102", action: nil, keyEquivalent: "")
            audioItem.isEnabled = false
            menu.addItem(audioItem)
            
            // 7. Hotkey Hint
            let hintItem = NSMenuItem(title: "⌨️ Hotkeys: Ctrl+F1 (Down) • Ctrl+F2 (Up)", action: nil, keyEquivalent: "")
            hintItem.isEnabled = false
            menu.addItem(hintItem)
            
            menu.addItem(NSMenuItem.separator())
            
            // 8. Quit
            let quitItem = NSMenuItem(title: "Quit DisplayMac", action: #selector(self.quitApp), keyEquivalent: "q")
            quitItem.target = self
            menu.addItem(quitItem)
            
            statusItem.menu = menu
            self.statusItem = statusItem
            
            self.startHotkeyListener()
            self.startFileWatcher()
            print("[MenuManager] ☀️ DisplayMac Menu Bar Item active! (Control brightness from top bar or Ctrl+F1/F2)")
        }
    }
    
    @objc private func sliderMoved(_ sender: NSSlider) {
        let val = Float(sender.doubleValue) / 100.0
        updateBrightness(val, fromUI: false)
    }
    
    @objc private func setPreset25()  { updateBrightness(0.25) }
    @objc private func setPreset50()  { updateBrightness(0.50) }
    @objc private func setPreset75()  { updateBrightness(0.75) }
    @objc private func setPreset100() { updateBrightness(1.00) }
    
    @objc private func quitApp() {
        VirtualDisplayManager.shared.releaseVirtualDisplay()
        exit(0)
    }
    
    public func updateConnectedDevice(_ name: String) {
        DispatchQueue.main.async { [weak self] in
            if let item = self?.statusItem?.menu?.item(withTag: 100) {
                item.title = "📱 \(name) (120Hz)"
            }
        }
    }
    
    public func updateBrightness(_ val: Float, fromUI: Bool = true) {
        let clamped = max(0.01, min(1.0, val))
        self.currentBrightness = clamped
        let pct = Int(clamped * 100)
        
        DispatchQueue.main.async { [weak self] in
            if fromUI {
                self?.brightnessSlider?.doubleValue = Double(pct)
            }
            if let item = self?.statusItem?.menu?.item(withTag: 200) {
                item.title = "☀️ AMOLED Brightness: \(pct)%"
            }
        }
        
        print("[Brightness] ☀️ AMOLED Brightness set to: \(pct)%")
        onBrightnessChanged?(clamped)
    }
    
    public func adjustBrightness(delta: Float) {
        updateBrightness(currentBrightness + delta)
    }
    
    private func startHotkeyListener() {
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Check for Ctrl + F1 / Ctrl + F2
            if event.modifierFlags.contains(.control) {
                if event.keyCode == 122 || event.keyCode == 145 { // F1 / Brightness Down
                    self?.adjustBrightness(delta: -0.10)
                } else if event.keyCode == 120 || event.keyCode == 144 { // F2 / Brightness Up
                    self?.adjustBrightness(delta: 0.10)
                }
            }
            // Check for Cmd + Option + Up / Down arrows
            if event.modifierFlags.contains([.command, .option]) {
                if event.keyCode == 125 { // Down arrow
                    self?.adjustBrightness(delta: -0.10)
                } else if event.keyCode == 126 { // Up arrow
                    self?.adjustBrightness(delta: 0.10)
                }
            }
        }
    }
    
    private func startFileWatcher() {
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            let path = "/tmp/displaymac_brightness"
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                  let modTime = attrs[.modificationDate] as? Date else { return }
            
            if self?.lastFileModTime == nil || modTime > self!.lastFileModTime! {
                self?.lastFileModTime = modTime
                if let str = try? String(contentsOfFile: path, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) {
                    if str == "+" || str == "up" {
                        self?.adjustBrightness(delta: 0.10)
                    } else if str == "-" || str == "down" {
                        self?.adjustBrightness(delta: -0.10)
                    } else if let num = Float(str) {
                        let target = num > 1.0 ? (num / 100.0) : num
                        self?.updateBrightness(target)
                    }
                }
            }
        }
    }
}
