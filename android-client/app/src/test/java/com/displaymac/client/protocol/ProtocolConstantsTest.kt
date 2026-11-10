package com.displaymac.client.protocol

import org.junit.Assert.assertEquals
import org.junit.Test
import java.nio.ByteBuffer
import java.nio.ByteOrder

class ProtocolConstantsTest {

    @Test
    fun buildClientHelloEncodesHeaderDimensionsAndDeviceName() {
        val packet = ProtocolConstants.buildClientHello(
            width = 2560,
            height = 1600,
            refreshRate = 120,
            dpi = 320,
            deviceName = "Galaxy Tab S9"
        )

        val expectedNameBytes = "Galaxy Tab S9".toByteArray(Charsets.UTF_8)
        assertEquals(8 + 18 + expectedNameBytes.size, packet.size)

        val bb = ByteBuffer.wrap(packet).order(ByteOrder.BIG_ENDIAN)
        assertEquals(ProtocolConstants.MAGIC, bb.short)
        assertEquals(ProtocolConstants.VERSION, bb.get())
        assertEquals(ProtocolConstants.MSG_CLIENT_HELLO, bb.get())
        assertEquals(18 + expectedNameBytes.size, bb.int)

        assertEquals(2560, bb.int)
        assertEquals(1600, bb.int)
        assertEquals(120, bb.int)
        assertEquals(320, bb.int)
        assertEquals(ProtocolConstants.CODEC_HEVC, bb.get())
        assertEquals(ProtocolConstants.CLIENT_FLAGS_STYLUS_AND_HDR, bb.get())

        val decodedName = ByteArray(expectedNameBytes.size)
        bb.get(decodedName)
        assertEquals("Galaxy Tab S9", String(decodedName, Charsets.UTF_8))
    }

    @Test
    fun buildStylusPacketEncodesBigEndianFloats() {
        val packet = ProtocolConstants.buildStylusPacket(
            action = ProtocolConstants.StylusAction.MOVE,
            buttons = 0x01,
            normX = 0.25f,
            normY = 0.75f,
            pressure = 0.5f,
            tilt = 0.125f
        )

        assertEquals(26, packet.size)
        val bb = ByteBuffer.wrap(packet).order(ByteOrder.BIG_ENDIAN)
        assertEquals(ProtocolConstants.MAGIC, bb.short)
        assertEquals(ProtocolConstants.VERSION, bb.get())
        assertEquals(ProtocolConstants.MSG_STYLUS_EVENT, bb.get())
        assertEquals(18, bb.int)
        assertEquals(ProtocolConstants.StylusAction.MOVE, bb.get())
        assertEquals(0x01.toByte(), bb.get())
        assertEquals(0.25f, bb.float, 0.0001f)
        assertEquals(0.75f, bb.float, 0.0001f)
        assertEquals(0.5f, bb.float, 0.0001f)
        assertEquals(0.125f, bb.float, 0.0001f)
    }

    @Test
    fun buildTouchPacketEncodesActionPhaseAndDeltas() {
        val packet = ProtocolConstants.buildTouchPacket(
            action = ProtocolConstants.TouchAction.SCROLL,
            phase = ProtocolConstants.TouchPhase.CHANGED,
            normX = 0.5f,
            normY = 0.5f,
            deltaX = -12.5f,
            deltaY = 24.0f
        )

        assertEquals(26, packet.size)
        val bb = ByteBuffer.wrap(packet).order(ByteOrder.BIG_ENDIAN)
        assertEquals(ProtocolConstants.MAGIC, bb.short)
        assertEquals(ProtocolConstants.VERSION, bb.get())
        assertEquals(ProtocolConstants.MSG_TOUCH_EVENT, bb.get())
        assertEquals(18, bb.int)
        assertEquals(ProtocolConstants.TouchAction.SCROLL, bb.get())
        assertEquals(ProtocolConstants.TouchPhase.CHANGED, bb.get())
        assertEquals(0.5f, bb.float, 0.0001f)
        assertEquals(0.5f, bb.float, 0.0001f)
        assertEquals(-12.5f, bb.float, 0.0001f)
        assertEquals(24.0f, bb.float, 0.0001f)
    }
}
