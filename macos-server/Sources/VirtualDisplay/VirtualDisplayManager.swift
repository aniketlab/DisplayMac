import Foundation
import CoreGraphics
import ObjectiveC

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
        
        // 1. Check if an active, dedicated virtual display is ALREADY allocated and online
        if let existingID = activeDisplayID, virtualDisplayInstance != nil, existingID != CGMainDisplayID() {
            if CGDisplayIsActive(existingID) != 0 {
                print("[VirtualDisplay] ♻️ Reusing existing active virtual display ID: \(existingID)")
                return true
            }
        }
        
        print("[VirtualDisplay] Initializing Virtual Display: \(width)x\(height) @ \(refreshRate)Hz...")
        
        // Ensure CoreDisplay framework is dynamically loaded in process memory
        if NSClassFromString("CGVirtualDisplay") == nil {
            dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_NOW)
        }
        
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
            
            let allocSel = NSSelectorFromString("alloc")
            let displayInitSel = NSSelectorFromString("initWithDescriptor:")
            
            typealias DisplayInitFunc = @convention(c) (AnyObject, Selector, AnyObject) -> AnyObject?
            
            if let displayAlloc = (displayClass as AnyObject).perform(allocSel)?.takeUnretainedValue(),
               let displayMethod = class_getInstanceMethod(displayClass, displayInitSel) {
                
                let displayInit = unsafeBitCast(method_getImplementation(displayMethod), to: DisplayInitFunc.self)
                if let displayObj = displayInit(displayAlloc, displayInitSel, descriptor) {
                    
                    // Mode Init: initWithWidth:height:refreshRate:
                    let modeInitSel = NSSelectorFromString("initWithWidth:height:refreshRate:")
                    typealias ModeInitFunc = @convention(c) (AnyObject, Selector, UInt32, UInt32, Double) -> AnyObject?
                    
                    var modeInstances: [AnyObject] = []
                    
                    // Register HiDPI Retina modes matching 14.6" Tab S10 Ultra (16:10 aspect ratio)
                    // Primary mode is 1480x924 (Exact 2x Retina, identical to MacBook Pro UI scale)
                    let supportedResolutions: [(UInt32, UInt32)] = [
                        (1480, 924),   // 2.0x HiDPI Retina (Default: Comfortable MacBook Pro UI size)
                        (1680, 1050),  // 1.76x HiDPI Retina (More Space)
                        (1920, 1200),  // 1.54x HiDPI Retina (Wide Workspace)
                        (UInt32(width), UInt32(height)) // 1.0x Native Peak Points (2960x1848)
                    ]
                    
                    for (modeW, modeH) in supportedResolutions {
                        if let modeAlloc = (modeClass as AnyObject).perform(allocSel)?.takeUnretainedValue(),
                           let modeMethod = class_getInstanceMethod(modeClass, modeInitSel) {
                            let modeInit = unsafeBitCast(method_getImplementation(modeMethod), to: ModeInitFunc.self)
                            if let modeInstance = modeInit(modeAlloc, modeInitSel, modeW, modeH, Double(refreshRate)) {
                                modeInstances.append(modeInstance)
                            }
                        }
                    }
                    
                    if !modeInstances.isEmpty {
                        let settingsClass = NSClassFromString("CGVirtualDisplaySettings") as? NSObject.Type
                        let settings = settingsClass?.init()
                        settings?.setValue(modeInstances, forKey: "modes")
                        
                        let applySel = NSSelectorFromString("applySettings:")
                        if (displayObj as AnyObject).responds(to: applySel) {
                            _ = (displayObj as AnyObject).perform(applySel, with: settings)
                        }
                    }
                    
                    self.virtualDisplayInstance = displayObj
                    
                    if let displayIDValue = (displayObj as AnyObject).value(forKey: "displayID") as? CGDirectDisplayID {
                        self.activeDisplayID = displayIDValue
                        print("[VirtualDisplay] Successfully spawned CGVirtualDisplay ID: \(displayIDValue)")
                        return true
                    }
                }
            }
        }
        
        // DO NOT FALLBACK TO MAIN DISPLAY! Prevents mirroring of physical BenQ monitor.
        print("[VirtualDisplay] ❌ Error: Failed to spawn CGVirtualDisplay. Main display fallback strictly disabled.")
        self.activeDisplayID = nil
        return false
    }
    
    public func releaseVirtualDisplay() {
        if let display = virtualDisplayInstance {
            print("[VirtualDisplay] Releasing virtual display...")
            let terminateSelector = NSSelectorFromString("terminate")
            if (display as AnyObject).responds(to: terminateSelector) {
                _ = (display as AnyObject).perform(terminateSelector)
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
