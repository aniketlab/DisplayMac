import Foundation
import CoreGraphics
import DisplayMacProtocol
#if canImport(AppKit)
import AppKit
#endif

public final class InputInjector {
    public static let shared = InputInjector()

    private let tabletPointSubtype: Int64 = 1

    private var activeDisplayID: CGDirectDisplayID?
    private var originX: CGFloat = 0
    private var originY: CGFloat = 0
    private var screenWidth: CGFloat = 1920
    private var screenHeight: CGFloat = 1080
    private var isMouseDown: Bool = false
    private var isPenInProximity = false

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

    // MARK: - Touch Interaction (Taps, Scrolling, Dragging, Pinch Zoom)
    public func handleTouchPacket(_ packet: TouchPacket) {
        guard let displayID = activeDisplayID else { return }

        let bounds = CGDisplayBounds(displayID)
        guard bounds.width > 0 && bounds.height > 0 else { return }

        let globalX = bounds.origin.x + (CGFloat(packet.normalizedX) * bounds.width)
        let globalY = bounds.origin.y + (CGFloat(packet.normalizedY) * bounds.height)
        let point = CGPoint(x: globalX, y: globalY)

        switch packet.action {
        case TouchAction.tap:
            if let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
               let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) {
                down.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
            }
            hideCursorOnTouch()

        case TouchAction.doubleTap:
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
            if let down = CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: point, mouseButton: .right),
               let up = CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: point, mouseButton: .right) {
                down.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
            }
            hideCursorOnTouch()

        case TouchAction.scroll:
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
                case TouchPhase.began:     phaseVal = 1
                case TouchPhase.changed:   phaseVal = 2
                case TouchPhase.ended:     phaseVal = 4
                case TouchPhase.cancelled: phaseVal = 8
                default:                   phaseVal = 2
                }
                scroll.setIntegerValueField(.scrollWheelEventScrollPhase, value: phaseVal)
                scroll.post(tap: .cghidEventTap)
            }

        case TouchAction.dragStart:
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

    // MARK: - Stylus Input (Tablet Proximity, Pressure, Tilt)
    private func sendTabletProximity(entering: Bool, point: CGPoint) {
        if let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) {
            event.type = .tabletProximity
            event.setIntegerValueField(.tabletProximityEventEnterProximity, value: entering ? 1 : 0)
            event.setIntegerValueField(.tabletProximityEventVendorID, value: 0x056a)
            event.setIntegerValueField(.tabletProximityEventTabletID, value: 1)
            event.setIntegerValueField(.tabletProximityEventPointerID, value: 1)
            event.setIntegerValueField(.tabletProximityEventDeviceID, value: 1)
            event.setIntegerValueField(.tabletProximityEventPointerType, value: 1)
            event.setIntegerValueField(.tabletProximityEventCapabilityMask, value: 0x000F)
            event.post(tap: .cghidEventTap)
        }
    }

    public func handleStylusPacket(_ packet: StylusPacket) {
        guard let displayID = activeDisplayID else { return }

        let bounds = CGDisplayBounds(displayID)
        guard bounds.width > 0 && bounds.height > 0 else { return }

        let globalX = bounds.origin.x + (CGFloat(packet.normalizedX) * bounds.width)
        let globalY = bounds.origin.y + (CGFloat(packet.normalizedY) * bounds.height)
        let point = CGPoint(x: globalX, y: globalY)

        let isSecondaryButton = (packet.buttons & 0x01) != 0

        if !isPenInProximity && packet.action != StylusAction.hoverExit {
            sendTabletProximity(entering: true, point: point)
            isPenInProximity = true
        }

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
            if let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) {
                event.setIntegerValueField(.mouseEventSubtype, value: tabletPointSubtype)
                event.post(tap: .cghidEventTap)
            }

        case StylusAction.hoverExit:
            if isPenInProximity {
                sendTabletProximity(entering: false, point: point)
                isPenInProximity = false
            }

        default:
            break
        }
    }

    private func applyStylusAttributes(_ event: CGEvent, pressure: Float, tilt: Float, isSecondary: Bool) {
        let p = Double(max(0.01, min(1.0, pressure)))
        event.setDoubleValueField(.tabletEventPointPressure, value: p)
        event.setDoubleValueField(.mouseEventPressure, value: p)

        let t = Double(max(-1.0, min(1.0, tilt)))
        event.setDoubleValueField(.tabletEventTiltX, value: t)

        event.setIntegerValueField(.mouseEventSubtype, value: tabletPointSubtype)
        event.setIntegerValueField(.tabletEventDeviceID, value: 1)
        event.setIntegerValueField(.tabletEventPointButtons, value: isSecondary ? 2 : 1)
    }
}
