package com.displaymac.client.input

import android.view.MotionEvent
import android.view.View
import com.displaymac.client.protocol.ProtocolConstants
import java.io.OutputStream

class StylusInputHandler(
    private val sendControlPacket: (ByteArray) -> Unit
) : View.OnTouchListener, View.OnHoverListener {

    override fun onTouch(v: View, event: MotionEvent): Boolean {
        handleMotionEvent(v, event, isHover = false)
        return true
    }

    override fun onHover(v: View, event: MotionEvent): Boolean {
        handleMotionEvent(v, event, isHover = true)
        return true
    }

    private fun handleMotionEvent(view: View, event: MotionEvent, isHover: Boolean) {
        val width = view.width.toFloat()
        val height = view.height.toFloat()
        if (width <= 0 || height <= 0) return

        val normX = (event.x / width).coerceIn(0f, 1f)
        val normY = (event.y / height).coerceIn(0f, 1f)
        val pressure = event.pressure.coerceIn(0f, 1f)
        val tilt = event.getAxisValue(MotionEvent.AXIS_TILT)

        // Check if S-Pen button is pressed
        val isButtonPressed = (event.buttonState and MotionEvent.BUTTON_STYLUS_PRIMARY) != 0
        val buttonByte: Byte = if (isButtonPressed) 0x01 else 0x00

        val actionByte: Byte = if (isHover) {
            when (event.actionMasked) {
                MotionEvent.ACTION_HOVER_MOVE, MotionEvent.ACTION_HOVER_ENTER -> 0x04 // Hover
                else -> return
            }
        } else {
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> 0x01 // Down
                MotionEvent.ACTION_MOVE -> 0x02 // Move
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> 0x03 // Up
                else -> return
            }
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
    }
}
