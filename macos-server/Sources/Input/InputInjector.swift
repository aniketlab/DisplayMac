import Foundation
import CoreGraphics
#if canImport(AppKit)
import AppKit
#endif

public final class InputInjector {
    public static let shared = InputInjector()
    
    // macOS CoreGraphics Tablet Point Subtype (kCGEventMouseSubtypeTabletPoint = 1)
    private let tabletPointSubtype: Int64 = 1
    
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
    
    // MARK: - Native Touch Interaction (Taps, Kinetic Scrolling, Gestures without Mouse Arrow)
    public func handleTouchPacket(_ packet: TouchPacket) {
        guard let displayID = activeDisplayID, displayID != CGMainDisplayID() else {
            return
        }
        
        let bounds = CGDisplayBounds(displayID)
        guard bounds.width > 0 && bounds.height > 0 else { return }
        
        let globalX = bounds.origin.x + (CGFloat(packet.normalizedX) * bounds.width)
        let globalY = bounds.origin.y + (CGFloat(packet.normalizedY) * bounds.height)
        let point = CGPoint(x: globalX, y: globalY)
        
        switch packet.action {
        case TouchAction.tap:
            // Single tap -> Left Click without persistent cursor
            if let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
               let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) {
                down.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
            }
            hideCursorOnTouch()
            
        case TouchAction.doubleTap:
            // Double tap -> Double Click
            for clickCount in 1...2 {
                if let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
                   let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) {
                    down.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
                    up.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
                    down.post(tap: .cghidEventTap)
                    up.post(tap: .cghidEventTap)
                }
            }
            hideCursorOnTouch()
            
        case TouchAction.rightClick:
            // 2-finger tap or long press -> Secondary Click (Context Menu)
            if let down = CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: point, mouseButton: .right),
               let up = CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: point, mouseButton: .right) {
                down.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
            }
            hideCursorOnTouch()
            
        case TouchAction.scroll:
            // Smooth pixel-based kinetic scrolling (NO cursor arrow!)
            let scrollY = Int32(packet.deltaY)
            let scrollX = Int32(packet.deltaX)
            
            if let scroll = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 2,
                wheel1: scrollY,
                wheel2: scrollX,
                wheel3: 0
            ) {
                scroll.location = point
                scroll.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
                
                let phaseVal: Int64
                switch packet.phase {
                case TouchPhase.began:     phaseVal = 1 // kCGScrollPhaseBegan
                case TouchPhase.changed:   phaseVal = 2 // kCGScrollPhaseChanged
                case TouchPhase.ended:     phaseVal = 4 // kCGScrollPhaseEnded
                case TouchPhase.cancelled: phaseVal = 8 // kCGScrollPhaseCancelled
                default:                   phaseVal = 2
                }
                scroll.setIntegerValueField(.scrollWheelEventScrollPhase, value: phaseVal)
                scroll.post(tap: .cghidEventTap)
            }
            
        case TouchAction.dragStart:
            // Double-tap & hold drag start (e.g. dragging windows or desktop files)
            if let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left) {
                down.post(tap: .cghidEventTap)
            }
            isMouseDown = true
            
        case TouchAction.dragMove:
            if let drag = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: point, mouseButton: .left) {
                drag.post(tap: .cghidEventTap)
            }
            
        case TouchAction.dragEnd:
            if let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) {
                up.post(tap: .cghidEventTap)
            }
            isMouseDown = false
            hideCursorOnTouch()
            
        case TouchAction.zoom:
            // Pinch to zoom: In macOS, Command + Scroll zooms in Safari, Preview, etc.
            let zoomDelta = Int32(packet.deltaY)
            if zoomDelta != 0, let zoom = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 1,
                wheel1: zoomDelta,
                wheel2: 0,
                wheel3: 0
            ) {
                zoom.location = point
                zoom.flags = .maskCommand
                zoom.post(tap: .cghidEventTap)
            }
            
        default:
            break
        }
    }
    
    private func hideCursorOnTouch() {
        #if canImport(AppKit)
        DispatchQueue.main.async {
            NSCursor.setHiddenUntilMouseMoves(true)
        }
        #endif
    }
    
    // MARK: - S-Pen Stylus Handling (Wacom Digitizer Precision Drawing)
    public func handleStylusPacket(_ packet: StylusPacket) {
        // Only inject touches if active virtual display exists (NEVER touch primary BenQ monitor)
        guard let displayID = activeDisplayID, displayID != CGMainDisplayID() else {
            return
        }
        
        let bounds = CGDisplayBounds(displayID)
        guard bounds.width > 0 && bounds.height > 0 else { return }
        
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
                    event.setIntegerValueField(.mouseEventSubtype, value: tabletPointSubtype)
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
                event.setIntegerValueField(.mouseEventSubtype, value: tabletPointSubtype)
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
        event.setIntegerValueField(.mouseEventSubtype, value: tabletPointSubtype)
        event.setIntegerValueField(.tabletEventDeviceID, value: 1)
        event.setIntegerValueField(.tabletEventPointButtons, value: isSecondary ? 2 : 1)
    }
}
