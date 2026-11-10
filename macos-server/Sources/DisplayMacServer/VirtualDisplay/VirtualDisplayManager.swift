import Foundation
import CoreGraphics
import ObjectiveC

/// Manages headless virtual display creation via CoreDisplay CGVirtualDisplay.
public final class VirtualDisplayManager {
    public static let shared = VirtualDisplayManager()

    private var virtualDisplayInstance: AnyObject?
    public private(set) var activeDisplayID: CGDirectDisplayID?
    public private(set) var currentWidth: Int = 2960
    public private(set) var currentHeight: Int = 1848
    public private(set) var currentRefreshRate: Int = 120
    private var currentProductID: UInt32 = 35638

    private init() {}

    /// Creates or reuses a virtual display matching the client's resolution, aspect ratio, and refresh rate.
    public func setupVirtualDisplay(width: Int, height: Int, refreshRate: Int, dpi: Int = 264) -> Bool {
        if let existingID = activeDisplayID,
           virtualDisplayInstance != nil,
           currentWidth == width,
           currentHeight == height,
           currentRefreshRate == refreshRate,
           CGDisplayIsActive(existingID) != 0 {
            print("[VirtualDisplay] Reusing active virtual display ID: \(existingID)")
            return true
        }

        if virtualDisplayInstance != nil {
            releaseVirtualDisplay()
        }

        self.currentWidth = width
        self.currentHeight = height
        self.currentRefreshRate = refreshRate

        print("[VirtualDisplay] Initializing virtual display: \(width)x\(height) @ \(refreshRate)Hz")

        if NSClassFromString("CGVirtualDisplay") == nil {
            dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_NOW)
        }

        if let displayClass = NSClassFromString("CGVirtualDisplay") as? NSObject.Type,
           let descriptorClass = NSClassFromString("CGVirtualDisplayDescriptor") as? NSObject.Type,
           let modeClass = NSClassFromString("CGVirtualDisplayMode") as? NSObject.Type {

            let safeDpi = Double(max(dpi, 96))
            let widthMm = max(100.0, (Double(width) / safeDpi) * 25.4)
            let heightMm = max(60.0, (Double(height) / safeDpi) * 25.4)

            let descriptor = descriptorClass.init()
            descriptor.setValue("DisplayMac Display", forKey: "name")
            descriptor.setValue(UInt32(width), forKey: "maxPixelsWide")
            descriptor.setValue(UInt32(height), forKey: "maxPixelsHigh")
            descriptor.setValue(CGSize(width: widthMm, height: heightMm), forKey: "sizeInMillimeters")
            descriptor.setValue(currentProductID, forKey: "productID")
            currentProductID &+= 1
            descriptor.setValue(UInt32(0x444D), forKey: "vendorID")

            let allocSel = NSSelectorFromString("alloc")
            let displayInitSel = NSSelectorFromString("initWithDescriptor:")
            typealias DisplayInitFunc = @convention(c) (AnyObject, Selector, AnyObject) -> AnyObject?

            if let displayAlloc = (displayClass as AnyObject).perform(allocSel)?.takeUnretainedValue(),
               let displayMethod = class_getInstanceMethod(displayClass, displayInitSel) {

                let displayInit = unsafeBitCast(method_getImplementation(displayMethod), to: DisplayInitFunc.self)
                if let displayObj = displayInit(displayAlloc, displayInitSel, descriptor) {

                    let modeInitSel = NSSelectorFromString("initWithWidth:height:refreshRate:")
                    typealias ModeInitFunc = @convention(c) (AnyObject, Selector, UInt32, UInt32, Double) -> AnyObject?

                    var modeInstances: [AnyObject] = []
                    let supportedResolutions = buildModeList(width: width, height: height)

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
                        print("[VirtualDisplay] Spawned CGVirtualDisplay ID: \(displayIDValue)")
                        return true
                    }
                }
            }
        }

        print("[VirtualDisplay] Error: Failed to initialize CGVirtualDisplay; refusing physical display fallback")
        self.activeDisplayID = nil
        return false
    }

    private func buildModeList(width: Int, height: Int) -> [(UInt32, UInt32)] {
        var modes: [(UInt32, UInt32)] = []
        var seen = Set<String>()

        for scale in [2.0, 1.75, 1.5] {
            let scaledW = UInt32((Double(width) / scale).rounded()) & ~1
            let scaledH = UInt32((Double(height) / scale).rounded()) & ~1
            if scaledW >= 640 && scaledH >= 400 {
                let key = "\(scaledW)x\(scaledH)"
                if seen.insert(key).inserted {
                    modes.append((scaledW, scaledH))
                }
            }
        }

        let nativeW = UInt32(width)
        let nativeH = UInt32(height)
        let nativeKey = "\(nativeW)x\(nativeH)"
        if seen.insert(nativeKey).inserted {
            modes.append((nativeW, nativeH))
        }
        return modes
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

    public func getPhysicalDisplayIDs() -> [CGDirectDisplayID] {
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &displayCount)
        guard displayCount > 0 else { return [] }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetActiveDisplayList(displayCount, &displays, &displayCount)

        return displays.filter { id in
            if let vID = self.activeDisplayID, id == vID {
                return false
            }
            return true
        }
    }

    deinit {
        releaseVirtualDisplay()
    }
}
