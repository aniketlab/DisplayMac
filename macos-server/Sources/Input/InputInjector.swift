import Foundation
import CoreGraphics

public final class InputInjector {
    public static let shared = InputInjector()
    
    private var activeDisplayID: CGDirectDisplayID?
    private var originX: CGFloat = 0
    private var originY: CGFloat = 0
    private var screenWidth: CGFloat = 1480
    private var screenHeight: CGFloat = 924
    private var isMouseDown: Bool = false
    
    private init() {}
    
    public func updateActiveDisplay(displayID: CGDirectDisplayID?) {
        self.activeDisplayID = displayID
        if let id = displayID {
            let bounds = CGDisplayBounds(id)
            if bounds.width > 0 && bounds.height > 0 {
                self.originX = bounds.origin.x
                self.originY = bounds.origin.y
                self.screenWidth = bounds.width
                self.screenHeight = bounds.height
            }
        }
    }
    
    public func updateScreenBounds(originX: CGFloat, originY: CGFloat, width: CGFloat, height: CGFloat) {
        self.originX = originX
        self.originY = originY
        self.screenWidth = width
        self.screenHeight = height
    }
    
    public func handleStylusPacket(_ packet: StylusPacket) {
        // Dynamically query live display bounds to guarantee 100% coordinate precision
        var bounds = CGRect(x: originX, y: originY, width: screenWidth, height: screenHeight)
        if let displayID = activeDisplayID {
            let liveBounds = CGDisplayBounds(displayID)
            if liveBounds.width > 0 && liveBounds.height > 0 {
                bounds = liveBounds
            }
        }
        
        let globalX = bounds.origin.x + (CGFloat(packet.normalizedX) * bounds.width)
        let globalY = bounds.origin.y + (CGFloat(packet.normalizedY) * bounds.height)
        let point = CGPoint(x: globalX, y: globalY)
        
        let isSecondaryButton = (packet.buttons & 0x01) != 0
        
        switch packet.action {
        case StylusAction.down:
            let eventType: CGEventType = isSecondaryButton ? .rightMouseDown : .leftMouseDown
            let button: CGMouseButton = isSecondaryButton ? .right : .left
            if let event = CGEvent(mouseEventSource: nil, mouseType: eventType, mouseCursorPosition: point, mouseButton: button) {
                applyStylusAttributes(event, pressure: packet.pressure, tilt: packet.tilt, isSecondary: isSecondaryButton)
                event.post(tap: .cghidEventTap)
            }
            isMouseDown = true
            
        case StylusAction.move:
            let eventType: CGEventType
            let button: CGMouseButton = isSecondaryButton ? .right : .left
            if isMouseDown {
                eventType = isSecondaryButton ? .rightMouseDragged : .leftMouseDragged
            } else {
                eventType = .mouseMoved
            }
            if let event = CGEvent(mouseEventSource: nil, mouseType: eventType, mouseCursorPosition: point, mouseButton: button) {
                if isMouseDown {
                    applyStylusAttributes(event, pressure: packet.pressure, tilt: packet.tilt, isSecondary: isSecondaryButton)
                } else {
                    event.setIntegerValueField(.mouseEventSubtype, value: Int64(kCGEventMouseSubtypeTabletPoint.rawValue))
                }
                event.post(tap: .cghidEventTap)
            }
            
        case StylusAction.up:
            let eventType: CGEventType = isSecondaryButton ? .rightMouseUp : .leftMouseUp
            let button: CGMouseButton = isSecondaryButton ? .right : .left
            if let event = CGEvent(mouseEventSource: nil, mouseType: eventType, mouseCursorPosition: point, mouseButton: button) {
                applyStylusAttributes(event, pressure: 0.0, tilt: packet.tilt, isSecondary: isSecondaryButton)
                event.post(tap: .cghidEventTap)
            }
            isMouseDown = false
            
        case StylusAction.hover:
            // S-Pen hover: Smoothly tracks cursor right under the pen tip without hardware warping
            if let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) {
                event.setIntegerValueField(.mouseEventSubtype, value: Int64(kCGEventMouseSubtypeTabletPoint.rawValue))
                event.post(tap: .cghidEventTap)
            }
            
        default:
            break
        }
    }
    
    private func applyStylusAttributes(_ event: CGEvent, pressure: Float, tilt: Float, isSecondary: Bool) {
        let p = Double(max(0.01, min(1.0, pressure)))
        // Apple Pencil & Wacom digitizer pressure
        event.setDoubleValueField(.tabletEventPointPressure, value: p)
        event.setDoubleValueField(.mouseEventPressure, value: p)
        
        // Tilt
        let t = Double(max(-1.0, min(1.0, tilt)))
        event.setDoubleValueField(.tabletEventTiltX, value: t)
        
        // Native macOS Tablet Point Subtype
        event.setIntegerValueField(.mouseEventSubtype, value: Int64(kCGEventMouseSubtypeTabletPoint.rawValue))
        event.setIntegerValueField(.tabletEventDeviceID, value: 1)
        event.setIntegerValueField(.tabletEventPointButtons, value: isSecondary ? 2 : 1)
    }
}
