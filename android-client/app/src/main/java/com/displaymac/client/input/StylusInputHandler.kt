package com.displaymac.client.input

import android.os.SystemClock
import android.view.MotionEvent
import android.view.View
import com.displaymac.client.protocol.ProtocolConstants
import kotlin.math.abs

class StylusInputHandler(
    private val sendControlPacket: (ByteArray) -> Unit
) : View.OnTouchListener, View.OnHoverListener {

    private var isStylusActive = false
    private var lastStylusTime = 0L

    private var lastHoverX = -1f
    private var lastHoverY = -1f
    private var lastHoverTime = 0L

    override fun onTouch(view: View, event: MotionEvent): Boolean {
        val width = view.width.toFloat()
        val height = view.height.toFloat()
        if (width <= 0 || height <= 0) return true

        val toolType = event.getToolType(0)
        val isStylus = (toolType == MotionEvent.TOOL_TYPE_STYLUS)
        val now = SystemClock.uptimeMillis()

        // Palm Rejection: When drawing with S-Pen or recently used S-Pen (<300ms), reject accidental palm/finger touches
        if ((isStylusActive || (now - lastStylusTime < 300)) && !isStylus && event.actionMasked != MotionEvent.ACTION_UP) {
            return true
        }

        if (isStylus) {
            lastStylusTime = now
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> isStylusActive = true
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> isStylusActive = false
            }
        }

        val normX = (event.x / width).coerceIn(0f, 1f)
        val normY = (event.y / height).coerceIn(0f, 1f)
        val pressure = if (isStylus) event.pressure.coerceIn(0f, 1f) else 1.0f
        val tilt = event.getAxisValue(MotionEvent.AXIS_TILT)

        // Check if S-Pen side button is pressed (secondary click)
        val isButtonPressed = (event.buttonState and MotionEvent.BUTTON_STYLUS_PRIMARY) != 0
        val buttonByte: Byte = if (isButtonPressed) 0x01 else 0x00

        val actionByte: Byte = when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> 0x01 // Down
            MotionEvent.ACTION_MOVE -> 0x02 // Move / Drag
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> 0x03 // Up
            else -> return true
        }

        val packet = ProtocolConstants.buildStylusPacket(
            action = actionByte,
            buttons = buttonByte,
            normX = normX,
            normY = normY,
            pressure = pressure,
            tilt = tilt
        )

        sendControlPacket(packet)
        return true
    }

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
                // Throttle hover to avoid network saturation
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
