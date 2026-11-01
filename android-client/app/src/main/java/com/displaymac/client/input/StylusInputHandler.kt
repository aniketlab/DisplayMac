package com.displaymac.client.input

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import com.displaymac.client.protocol.ProtocolConstants
import kotlin.math.abs
import kotlin.math.hypot

class StylusInputHandler(
    private val sendControlPacket: (ByteArray) -> Unit
) : View.OnTouchListener, View.OnHoverListener {

    // S-Pen Stylus State
    private var isStylusActive = false
    private var lastStylusTime = 0L
    private var lastHoverX = -1f
    private var lastHoverY = -1f
    private var lastHoverTime = 0L

    // Finger Touch Gesture State
    private var downX = 0f
    private var downY = 0f
    private var lastTouchX = 0f
    private var lastTouchY = 0f
    private var downTime = 0L

    private var isScrolling = false
    private var isDragging = false
    private var isLongPressTriggered = false
    private var isPotentialDoubleTapDrag = false

    private var lastTapUpTime = 0L
    private var lastTapUpX = 0f
    private var lastTapUpY = 0f

    // Two-Finger Gesture State
    private var twoFingerDownTime = 0L
    private var initialSpan = 0f
    private var lastSpan = 0f
    private var twoFingerMoved = false

    private val longPressHandler = Handler(Looper.getMainLooper())
    private var pendingLongPressRunnable: Runnable? = null

    override fun onTouch(view: View, event: MotionEvent): Boolean {
        val width = view.width.toFloat()
        val height = view.height.toFloat()
        if (width <= 0 || height <= 0) return true

        val toolType = event.getToolType(0)
        val isStylus = (toolType == MotionEvent.TOOL_TYPE_STYLUS)
        val now = SystemClock.uptimeMillis()

        // 1. Palm Rejection: If drawing with S-Pen or recently used (<300ms), reject accidental palm/finger touches
        if ((isStylusActive || (now - lastStylusTime < 300)) && !isStylus && event.actionMasked != MotionEvent.ACTION_UP) {
            return true
        }

        // 2. Delegate S-Pen to Wacom Digitizer Mode
        if (isStylus) {
            return handleStylusTouch(width, height, event, now)
        }

        // 3. Handle Finger Touch Gestures (Taps, Kinetic Scrolling, Pinch Zoom, Long Press)
        return handleFingerTouch(view, width, height, event, now)
    }

    // MARK: - S-Pen Stylus Touch Handling (Drawing, Pressure, Tilt)
    private fun handleStylusTouch(width: Float, height: Float, event: MotionEvent, now: Long): Boolean {
        lastStylusTime = now
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> isStylusActive = true
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> isStylusActive = false
        }

        val normX = (event.x / width).coerceIn(0f, 1f)
        val normY = (event.y / height).coerceIn(0f, 1f)
        val pressure = event.pressure.coerceIn(0f, 1f)
        val tilt = event.getAxisValue(MotionEvent.AXIS_TILT)

        // S-Pen side button (secondary click)
        val isButtonPressed = (event.buttonState and MotionEvent.BUTTON_STYLUS_PRIMARY) != 0
        val buttonByte: Byte = if (isButtonPressed) 0x01 else 0x00

        val actionByte: Byte = when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> ProtocolConstants.TouchAction.TAP // Down
            MotionEvent.ACTION_MOVE -> ProtocolConstants.TouchAction.DOUBLE_TAP // Move / Drag
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> ProtocolConstants.TouchAction.RIGHT_CLICK // Up
            else -> return true
        }

        // Action byte matches StylusAction constants (1=down, 2=move, 3=up)
        val stylusAction: Byte = when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> 0x01
            MotionEvent.ACTION_MOVE -> 0x02
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> 0x03
            else -> return true
        }

        val packet = ProtocolConstants.buildStylusPacket(
            action = stylusAction,
            buttons = buttonByte,
            normX = normX,
            normY = normY,
            pressure = pressure,
            tilt = tilt
        )
        sendControlPacket(packet)
        return true
    }

    // MARK: - Finger Touch Gesture Handling (Trackpad Emulation, No Mouse Cursor Arrow)
    private fun handleFingerTouch(view: View, width: Float, height: Float, event: MotionEvent, now: Long): Boolean {
        val touchSlop = ViewConfiguration.get(view.context).scaledTouchSlop.toFloat()
        val doubleTapTimeout = ViewConfiguration.getDoubleTapTimeout().toLong()

        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downX = event.x
                downY = event.y
                lastTouchX = event.x
                lastTouchY = event.y
                downTime = now
                isScrolling = false
                isDragging = false
                isLongPressTriggered = false
                twoFingerMoved = false

                // Check for potential double-tap drag (e.g. dragging a window or selecting text)
                val timeSinceLastTap = now - lastTapUpTime
                val distFromLastTap = hypot(event.x - lastTapUpX, event.y - lastTapUpY)
                if (timeSinceLastTap < doubleTapTimeout && distFromLastTap < touchSlop * 2) {
                    isPotentialDoubleTapDrag = true
                } else {
                    isPotentialDoubleTapDrag = false
                    // Schedule Long Press timer (450ms) for Right-Click
                    pendingLongPressRunnable?.let { longPressHandler.removeCallbacks(it) }
                    val runnable = Runnable {
                        if (!isScrolling && !isDragging) {
                            isLongPressTriggered = true
                            view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                            val normX = (downX / width).coerceIn(0f, 1f)
                            val normY = (downY / height).coerceIn(0f, 1f)
                            sendControlPacket(
                                ProtocolConstants.buildTouchPacket(
                                    action = ProtocolConstants.TouchAction.RIGHT_CLICK,
                                    phase = ProtocolConstants.TouchPhase.ENDED,
                                    normX = normX,
                                    normY = normY
                                )
                            )
                        }
                    }
                    pendingLongPressRunnable = runnable
                    longPressHandler.postDelayed(runnable, 450)
                }
            }

            MotionEvent.ACTION_POINTER_DOWN -> {
                // Second finger touched down -> cancel single finger timers & scrolls
                pendingLongPressRunnable?.let { longPressHandler.removeCallbacks(it) }
                if (isScrolling) {
                    val normX = (lastTouchX / width).coerceIn(0f, 1f)
                    val normY = (lastTouchY / height).coerceIn(0f, 1f)
                    sendControlPacket(
                        ProtocolConstants.buildTouchPacket(
                            action = ProtocolConstants.TouchAction.SCROLL,
                            phase = ProtocolConstants.TouchPhase.ENDED,
                            normX = normX,
                            normY = normY
                        )
                    )
                    isScrolling = false
                }
                if (event.pointerCount >= 2) {
                    twoFingerDownTime = now
                    initialSpan = hypot(event.getX(0) - event.getX(1), event.getY(0) - event.getY(1))
                    lastSpan = initialSpan
                    twoFingerMoved = false
                }
            }

            MotionEvent.ACTION_MOVE -> {
                if (event.pointerCount == 1) {
                    val dx = event.x - lastTouchX
                    val dy = event.y - lastTouchY
                    val distFromDown = hypot(event.x - downX, event.y - downY)

                    if (distFromDown > touchSlop) {
                        pendingLongPressRunnable?.let { longPressHandler.removeCallbacks(it) }

                        if (isPotentialDoubleTapDrag) {
                            // Double-Tap and Hold Drag: moves windows or drags files
                            val normX = (event.x / width).coerceIn(0f, 1f)
                            val normY = (event.y / height).coerceIn(0f, 1f)
                            if (!isDragging) {
                                isDragging = true
                                sendControlPacket(
                                    ProtocolConstants.buildTouchPacket(
                                        action = ProtocolConstants.TouchAction.DRAG_START,
                                        phase = ProtocolConstants.TouchPhase.BEGAN,
                                        normX = normX,
                                        normY = normY
                                    )
                                )
                            }
                            sendControlPacket(
                                ProtocolConstants.buildTouchPacket(
                                    action = ProtocolConstants.TouchAction.DRAG_MOVE,
                                    phase = ProtocolConstants.TouchPhase.CHANGED,
                                    normX = normX,
                                    normY = normY
                                )
                            )
                        } else if (!isLongPressTriggered) {
                            // Natural Kinetic Touch Scrolling (No cursor arrow!)
                            val normX = (event.x / width).coerceIn(0f, 1f)
                            val normY = (event.y / height).coerceIn(0f, 1f)

                            val scrollDeltaX = dx * 1.5f
                            val scrollDeltaY = dy * 1.5f

                            if (!isScrolling) {
                                isScrolling = true
                                sendControlPacket(
                                    ProtocolConstants.buildTouchPacket(
                                        action = ProtocolConstants.TouchAction.SCROLL,
                                        phase = ProtocolConstants.TouchPhase.BEGAN,
                                        normX = normX,
                                        normY = normY,
                                        deltaX = scrollDeltaX,
                                        deltaY = scrollDeltaY
                                    )
                                )
                            } else {
                                sendControlPacket(
                                    ProtocolConstants.buildTouchPacket(
                                        action = ProtocolConstants.TouchAction.SCROLL,
                                        phase = ProtocolConstants.TouchPhase.CHANGED,
                                        normX = normX,
                                        normY = normY,
                                        deltaX = scrollDeltaX,
                                        deltaY = scrollDeltaY
                                    )
                                )
                            }
                        }
                    }
                    lastTouchX = event.x
                    lastTouchY = event.y
                } else if (event.pointerCount >= 2) {
                    // Two-Finger Pinch to Zoom
                    val currentSpan = hypot(event.getX(0) - event.getX(1), event.getY(0) - event.getY(1))
                    val spanDelta = currentSpan - lastSpan
                    if (abs(currentSpan - initialSpan) > touchSlop * 2) {
                        twoFingerMoved = true
                        val midX = (event.getX(0) + event.getX(1)) / 2f
                        val midY = (event.getY(0) + event.getY(1)) / 2f
                        val normX = (midX / width).coerceIn(0f, 1f)
                        val normY = (midY / height).coerceIn(0f, 1f)

                        sendControlPacket(
                            ProtocolConstants.buildTouchPacket(
                                action = ProtocolConstants.TouchAction.ZOOM,
                                phase = ProtocolConstants.TouchPhase.CHANGED,
                                normX = normX,
                                normY = normY,
                                deltaX = 0f,
                                deltaY = spanDelta
                            )
                        )
                        lastSpan = currentSpan
                    }
                }
            }

            MotionEvent.ACTION_POINTER_UP -> {
                if (event.pointerCount == 2 && !twoFingerMoved && (now - twoFingerDownTime < 350)) {
                    // Two-Finger Quick Tap -> Right-Click Context Menu!
                    val midX = (event.getX(0) + event.getX(1)) / 2f
                    val midY = (event.getY(0) + event.getY(1)) / 2f
                    val normX = (midX / width).coerceIn(0f, 1f)
                    val normY = (midY / height).coerceIn(0f, 1f)

                    view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                    sendControlPacket(
                        ProtocolConstants.buildTouchPacket(
                            action = ProtocolConstants.TouchAction.RIGHT_CLICK,
                            phase = ProtocolConstants.TouchPhase.ENDED,
                            normX = normX,
                            normY = normY
                        )
                    )
                    twoFingerMoved = true
                }
            }

            MotionEvent.ACTION_UP -> {
                pendingLongPressRunnable?.let { longPressHandler.removeCallbacks(it) }

                val normX = (event.x / width).coerceIn(0f, 1f)
                val normY = (event.y / height).coerceIn(0f, 1f)

                if (isDragging) {
                    sendControlPacket(
                        ProtocolConstants.buildTouchPacket(
                            action = ProtocolConstants.TouchAction.DRAG_END,
                            phase = ProtocolConstants.TouchPhase.ENDED,
                            normX = normX,
                            normY = normY
                        )
                    )
                    isDragging = false
                    isPotentialDoubleTapDrag = false
                } else if (isScrolling) {
                    sendControlPacket(
                        ProtocolConstants.buildTouchPacket(
                            action = ProtocolConstants.TouchAction.SCROLL,
                            phase = ProtocolConstants.TouchPhase.ENDED,
                            normX = normX,
                            normY = normY
                        )
                    )
                    isScrolling = false
                } else if (!isLongPressTriggered && !twoFingerMoved) {
                    // Tap or Double Tap
                    val timeSinceLastTap = now - lastTapUpTime
                    val distFromLastTap = hypot(event.x - lastTapUpX, event.y - lastTapUpY)

                    if (timeSinceLastTap < doubleTapTimeout && distFromLastTap < touchSlop * 2) {
                        // Double Tap
                        sendControlPacket(
                            ProtocolConstants.buildTouchPacket(
                                action = ProtocolConstants.TouchAction.DOUBLE_TAP,
                                phase = ProtocolConstants.TouchPhase.ENDED,
                                normX = normX,
                                normY = normY
                            )
                        )
                        lastTapUpTime = 0L
                    } else {
                        // Single Tap (Instant Click + Hide Mouse Cursor)
                        sendControlPacket(
                            ProtocolConstants.buildTouchPacket(
                                action = ProtocolConstants.TouchAction.TAP,
                                phase = ProtocolConstants.TouchPhase.ENDED,
                                normX = normX,
                                normY = normY
                            )
                        )
                        lastTapUpTime = now
                        lastTapUpX = event.x
                        lastTapUpY = event.y
                    }
                }

                isPotentialDoubleTapDrag = false
                isLongPressTriggered = false
            }

            MotionEvent.ACTION_CANCEL -> {
                pendingLongPressRunnable?.let { longPressHandler.removeCallbacks(it) }
                if (isDragging) {
                    val normX = (event.x / width).coerceIn(0f, 1f)
                    val normY = (event.y / height).coerceIn(0f, 1f)
                    sendControlPacket(
                        ProtocolConstants.buildTouchPacket(
                            action = ProtocolConstants.TouchAction.DRAG_END,
                            phase = ProtocolConstants.TouchPhase.CANCELLED,
                            normX = normX,
                            normY = normY
                        )
                    )
                    isDragging = false
                }
                if (isScrolling) {
                    val normX = (event.x / width).coerceIn(0f, 1f)
                    val normY = (event.y / height).coerceIn(0f, 1f)
                    sendControlPacket(
                        ProtocolConstants.buildTouchPacket(
                            action = ProtocolConstants.TouchAction.SCROLL,
                            phase = ProtocolConstants.TouchPhase.CANCELLED,
                            normX = normX,
                            normY = normY
                        )
                    )
                    isScrolling = false
                }
                isPotentialDoubleTapDrag = false
                isLongPressTriggered = false
            }
        }
        return true
    }

    // MARK: - S-Pen Hover Tracking
    override fun onHover(view: View, event: MotionEvent): Boolean {
        val toolType = event.getToolType(0)
        if (toolType != MotionEvent.TOOL_TYPE_STYLUS) return false

        val width = view.width.toFloat()
        val height = view.height.toFloat()
        if (width <= 0 || height <= 0) return false

        val now = SystemClock.uptimeMillis()
        lastStylusTime = now

        when (event.actionMasked) {
            MotionEvent.ACTION_HOVER_MOVE, MotionEvent.ACTION_HOVER_ENTER -> {
                val dx = abs(event.x - lastHoverX)
                val dy = abs(event.y - lastHoverY)
                if (dx < 2f && dy < 2f && (now - lastHoverTime < 16)) {
                    return true
                }
                lastHoverX = event.x
                lastHoverY = event.y
                lastHoverTime = now

                val normX = (event.x / width).coerceIn(0f, 1f)
                val normY = (event.y / height).coerceIn(0f, 1f)

                val packet = ProtocolConstants.buildStylusPacket(
                    action = 0x04, // Hover
                    buttons = 0x00,
                    normX = normX,
                    normY = normY,
                    pressure = 0f,
                    tilt = 0f
                )
                sendControlPacket(packet)
                return true
            }
            MotionEvent.ACTION_HOVER_EXIT -> {
                return true
            }
            else -> return false
        }
    }
}
