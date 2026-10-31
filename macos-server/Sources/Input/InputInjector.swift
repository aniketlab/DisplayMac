import Foundation
import CoreGraphics

public final class InputInjector {
    public static let shared = InputInjector()
    
    private var originX: CGFloat = 0
    private var originY: CGFloat = 0
    private var screenWidth: CGFloat = 1480
    private var screenHeight: CGFloat = 924
    private var isMouseDown: Bool = false
    
    private init() {}
    
    public func updateScreenBounds(originX: CGFloat, originY: CGFloat, width: CGFloat, height: CGFloat) {
        self.originX = originX
        self.originY = originY
        self.screenWidth = width
        self.screenHeight = height
    }
    
    public func handleStylusPacket(_ packet: StylusPacket) {
        // Calculate point in macOS Global Coordinate Space (taking multi-monitor offset into account)
        let globalX = originX + (CGFloat(packet.normalizedX) * screenWidth)
        let globalY = originY + (CGFloat(packet.normalizedY) * screenHeight)
        let point = CGPoint(x: globalX, y: globalY)
        
        // Warp visible cursor so user sees mouse immediately follow finger or S-Pen
        CGWarpMouseCursorPosition(point)
        
        let isSecondaryButton = (packet.buttons & 0x01) != 0
        
        switch packet.action {
        case StylusAction.down:
            let eventType: CGEventType = isSecondaryButton ? .rightMouseDown : .leftMouseDown
            let button: CGMouseButton = isSecondaryButton ? .right : .left
            if let event = CGEvent(mouseEventSource: nil, mouseType: eventType, mouseCursorPosition: point, mouseButton: button) {
                applyPressure(event, pressure: packet.pressure)
                event.post(tap: .cghidEventTap)
            }
            isMouseDown = true
            
        case StylusAction.move:
            let eventType: CGEventType = isMouseDown ? (isSecondaryButton ? .rightMouseDragged : .leftMouseDragged) : .mouseMoved
            let button: CGMouseButton = isSecondaryButton ? .right : .left
            if let event = CGEvent(mouseEventSource: nil, mouseType: eventType, mouseCursorPosition: point, mouseButton: button) {
                applyPressure(event, pressure: packet.pressure)
                event.post(tap: .cghidEventTap)
            }
            
        case StylusAction.up:
            let eventType: CGEventType = isSecondaryButton ? .rightMouseUp : .leftMouseUp
            let button: CGMouseButton = isSecondaryButton ? .right : .left
            if let event = CGEvent(mouseEventSource: nil, mouseType: eventType, mouseCursorPosition: point, mouseButton: button) {
                event.post(tap: .cghidEventTap)
            }
            isMouseDown = false
            
        case StylusAction.hover:
            // S-Pen hovering over screen without touching
            if let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) {
                event.post(tap: .cghidEventTap)
            }
            
        default:
            break
        }
    }
    
    private func applyPressure(_ event: CGEvent, pressure: Float) {
        // macOS Tablet Point Pressure is represented as a double value
        event.setDoubleValueField(.tabletEventPointPressure, value: Double(pressure))
    }
}
