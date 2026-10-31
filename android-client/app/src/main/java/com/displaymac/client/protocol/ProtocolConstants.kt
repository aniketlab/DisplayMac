package com.displaymac.client.protocol

import java.nio.ByteBuffer
import java.nio.ByteOrder

object ProtocolConstants {
    const val MAGIC: Short = 0x444D // "DM"
    const val VERSION: Byte = 0x01
    const val CONTROL_PORT = 7100
    const val VIDEO_PORT = 7101
    const val BONJOUR_SERVICE_TYPE = "_displaymac._tcp."

    // Message Types
    const val MSG_CLIENT_HELLO: Byte = 0x01
    const val MSG_SERVER_CONFIG: Byte = 0x02
    const val MSG_PING: Byte = 0x03
    const val MSG_PONG: Byte = 0x04
    const val MSG_REQUEST_KEYFRAME: Byte = 0x05
    const val MSG_STYLUS_EVENT: Byte = 0x11

    // Stream Frame Types
    const val FRAME_TYPE_KEYFRAME: Byte = 0x01
    const val FRAME_TYPE_P_FRAME: Byte = 0x02
    const val FRAME_TYPE_AUDIO: Byte = 0x03

    fun buildClientHello(width: Int, height: Int, refreshRate: Int, dpi: Int): ByteArray {
        val payload = ByteBuffer.allocate(18).order(ByteOrder.BIG_ENDIAN)
        payload.putInt(width)
        payload.putInt(height)
        payload.putInt(refreshRate)
        payload.putInt(dpi)
        payload.put(0x02.toByte()) // Codec: HEVC
        payload.put(0x03.toByte()) // Flags: Stylus + HDR
        
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
}
