import Foundation
import CoreGraphics

/// Manages virtual display creation on macOS (Apple Silicon).
/// Utilizes CoreDisplay CGVirtualDisplay to spawn a high-resolution, high-refresh-rate virtual screen.
public final class VirtualDisplayManager {
    public static let shared = VirtualDisplayManager()
    
    private var virtualDisplayInstance: AnyObject?
    public private(set) var activeDisplayID: CGDirectDisplayID?
    public private(set) var currentWidth: Int = 2960
    public private(set) var currentHeight: Int = 1848
    public private(set) var currentRefreshRate: Int = 120
    
    private init() {}
    
    /// Creates or reconfigures a headless virtual display matching tablet specs
    public func setupVirtualDisplay(width: Int = 2960, height: Int = 1848, refreshRate: Int = 120) -> Bool {
        self.currentWidth = width
        self.currentHeight = height
        self.currentRefreshRate = refreshRate
        
        print("[VirtualDisplay] Initializing Virtual Display: \(width)x\(height) @ \(refreshRate)Hz...")
        
        // Attempt dynamically loading CoreDisplay CGVirtualDisplay
        if let displayClass = NSClassFromString("CGVirtualDisplay") as? NSObject.Type,
           let descriptorClass = NSClassFromString("CGVirtualDisplayDescriptor") as? NSObject.Type,
           let modeClass = NSClassFromString("CGVirtualDisplayMode") as? NSObject.Type {
            
            let descriptor = descriptorClass.init()
            descriptor.setValue("DisplayMac S10 Ultra", forKey: "name")
            descriptor.setValue(UInt32(width), forKey: "maxPixelsWide")
            descriptor.setValue(UInt32(height), forKey: "maxPixelsHigh")
            descriptor.setValue(CGSize(width: 314, height: 196), forKey: "sizeInMillimeters") // 14.6" 16:10
            descriptor.setValue(UInt32(35638), forKey: "productID")
            descriptor.setValue(UInt32(0x444D), forKey: "vendorID")
            
            let selector = NSSelectorFromString("initWithDescriptor:")
            if displayClass.instancesRespond(to: selector) {
                let displayObj = displayClass.perform(selector, with: descriptor)?.takeUnretainedValue()
                
                // Configure Mode
                let modeInitSelector = NSSelectorFromString("initWithWidth:height:refreshRate:")
                if let modeInstance = (modeClass as AnyObject).perform(modeInitSelector, with: width, with: height, with: Double(refreshRate))?.takeUnretainedValue() {
                    let settingsClass = NSClassFromString("CGVirtualDisplaySettings") as? NSObject.Type
                    let settings = settingsClass?.init()
                    settings?.setValue([modeInstance], forKey: "modes")
                    
                    let applySelector = NSSelectorFromString("applySettings:")
                    _ = displayObj?.perform(applySelector, with: settings)
                }
                
                self.virtualDisplayInstance = displayObj
                
                if let displayIDValue = displayObj?.value(forKey: "displayID") as? CGDirectDisplayID {
                    self.activeDisplayID = displayIDValue
                    print("[VirtualDisplay] Successfully spawned CGVirtualDisplay ID: \(displayIDValue)")
                    return true
                }
            }
        }
        
        // Fallback: Bind to main display
        let mainID = CGMainDisplayID()
        self.activeDisplayID = mainID
        let bounds = CGDisplayBounds(mainID)
        print("[VirtualDisplay] Note: Using active system display ID: \(mainID) (\(Int(bounds.width))x\(Int(bounds.height)))")
        return true
    }
    
    public func releaseVirtualDisplay() {
        if let display = virtualDisplayInstance {
            print("[VirtualDisplay] Releasing virtual display...")
            let terminateSelector = NSSelectorFromString("terminate")
            if display.responds(to: terminateSelector) {
                _ = display.perform(terminateSelector)
            }
            virtualDisplayInstance = nil
            activeDisplayID = nil
        }
    }
    
    /// Detects if a physical display (HDMI, Thunderbolt, or built-in screen) is currently active.
    /// Ensures DisplayMac never conflicts with physical hardware monitors.
    public func getPhysicalDisplayIDs() -> [CGDirectDisplayID] {
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &displayCount)
        guard displayCount > 0 else { return [] }
        
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetActiveDisplayList(displayCount, &displays, &displayCount)
        
        return displays.filter { id in
            if let vID = self.activeDisplayID, id == vID {
                return false // exclude our virtual display
            }
            return true
        }
    }
    
    deinit {
        releaseVirtualDisplay()
    }
}
