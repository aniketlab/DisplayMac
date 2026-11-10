package com.displaymac.client.protocol

import java.nio.ByteBuffer
import java.nio.ByteOrder

object ProtocolConstants {
    const val MAGIC: Short = 0x444D // "DM"
    const val VERSION: Byte = 0x01

    const val CONTROL_PORT = 7100
    const val VIDEO_PORT = 7101
    const val AUDIO_PORT = 7102
    const val BONJOUR_SERVICE_TYPE = "_displaymac._tcp."

    // Upper bounds to guard against corrupted or malformed frame length headers
    const val MAX_CONTROL_PAYLOAD_BYTES = 64 * 1024
    const val MAX_VIDEO_FRAME_BYTES = 16 * 1024 * 1024
    const val MAX_AUDIO_FRAME_BYTES = 256 * 1024

    // Control Message Types
    const val MSG_CLIENT_HELLO: Byte = 0x01
    const val MSG_SERVER_CONFIG: Byte = 0x02
    const val MSG_PING: Byte = 0x03
    const val MSG_PONG: Byte = 0x04
    const val MSG_REQUEST_KEYFRAME: Byte = 0x05
    const val MSG_TOUCH_EVENT: Byte = 0x10
    const val MSG_STYLUS_EVENT: Byte = 0x11

    // Stream Frame Types
    const val FRAME_TYPE_KEYFRAME: Byte = 0x01
    const val FRAME_TYPE_P_FRAME: Byte = 0x02
    const val FRAME_TYPE_AUDIO: Byte = 0x03

    const val CODEC_HEVC: Byte = 0x02
    const val CLIENT_FLAGS_STYLUS_AND_HDR: Byte = 0x03

    object TouchAction {
        const val TAP: Byte = 0x01
        const val DOUBLE_TAP: Byte = 0x02
        const val RIGHT_CLICK: Byte = 0x03
        const val SCROLL: Byte = 0x04
        const val DRAG_START: Byte = 0x05
        const val DRAG_MOVE: Byte = 0x06
        const val DRAG_END: Byte = 0x07
        const val ZOOM: Byte = 0x08
    }

    object TouchPhase {
        const val BEGAN: Byte = 0x01
        const val CHANGED: Byte = 0x02
        const val ENDED: Byte = 0x03
        const val CANCELLED: Byte = 0x04
    }

    object StylusAction {
        const val DOWN: Byte = 0x01
        const val MOVE: Byte = 0x02
        const val UP: Byte = 0x03
        const val HOVER: Byte = 0x04
        const val HOVER_EXIT: Byte = 0x05
    }

    fun buildClientHello(
        width: Int,
        height: Int,
        refreshRate: Int,
        dpi: Int,
        deviceName: String = ""
    ): ByteArray {
        val nameBytes = deviceName.toByteArray(Charsets.UTF_8)
        val payload = ByteBuffer.allocate(18 + nameBytes.size).order(ByteOrder.BIG_ENDIAN)
        payload.putInt(width)
        payload.putInt(height)
        payload.putInt(refreshRate)
        payload.putInt(dpi)
        payload.put(CODEC_HEVC)
        payload.put(CLIENT_FLAGS_STYLUS_AND_HDR)
        if (nameBytes.isNotEmpty()) {
            payload.put(nameBytes)
        }
        return buildControlMessage(MSG_CLIENT_HELLO, payload.array())
    }

    fun buildControlMessage(type: Byte, payload: ByteArray): ByteArray {
        val buffer = ByteBuffer.allocate(8 + payload.size).order(ByteOrder.BIG_ENDIAN)
        buffer.putShort(MAGIC)
        buffer.put(VERSION)
        buffer.put(type)
        buffer.putInt(payload.size)
        buffer.put(payload)
        return buffer.array()
    }

    fun buildStylusPacket(
        action: Byte,
        buttons: Byte,
        normX: Float,
        normY: Float,
        pressure: Float,
        tilt: Float
    ): ByteArray {
        val payload = ByteBuffer.allocate(18).order(ByteOrder.BIG_ENDIAN)
        payload.put(action)
        payload.put(buttons)
        payload.putFloat(normX)
        payload.putFloat(normY)
        payload.putFloat(pressure)
        payload.putFloat(tilt)
        return buildControlMessage(MSG_STYLUS_EVENT, payload.array())
    }

    fun buildTouchPacket(
        action: Byte,
        phase: Byte,
        normX: Float,
        normY: Float,
        deltaX: Float = 0f,
        deltaY: Float = 0f
    ): ByteArray {
        val payload = ByteBuffer.allocate(18).order(ByteOrder.BIG_ENDIAN)
        payload.put(action)
        payload.put(phase)
        payload.putFloat(normX)
        payload.putFloat(normY)
        payload.putFloat(deltaX)
        payload.putFloat(deltaY)
        return buildControlMessage(MSG_TOUCH_EVENT, payload.array())
    }
}
