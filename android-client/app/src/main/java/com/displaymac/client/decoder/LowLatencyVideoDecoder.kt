package com.displaymac.client.decoder

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import android.util.Log
import android.view.Surface
import java.nio.ByteBuffer

class LowLatencyVideoDecoder(
    private val surface: Surface,
    private val onFrameRendered: (fps: Float) -> Unit
) {
    companion object {
        private const val TAG = "LowLatencyDecoder"
        private const val MIME_TYPE = MediaFormat.MIMETYPE_VIDEO_HEVC
    }

    private var codec: MediaCodec? = null
    private var isRunning = false
    private var frameCount = 0
    private var lastFpsTimestamp = System.currentTimeMillis()

    fun initDecoder(width: Int = 2960, height: Int = 1848) {
        stopDecoder()

        val decoderName = selectBestLowLatencyCodec(MIME_TYPE)
        Log.i(TAG, "Selected Hardware HEVC Decoder: $decoderName for ${width}x${height}")

        val format = MediaFormat.createVideoFormat(MIME_TYPE, width, height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_PRIORITY, 0) // Real-time priority
            setInteger(MediaFormat.KEY_LOW_LATENCY, 1) // Android low-latency flag
            setInteger(MediaFormat.KEY_OPERATING_RATE, 120)
        }

        try {
            val mediaCodec = if (decoderName != null) {
                MediaCodec.createByCodecName(decoderName)
            } else {
                MediaCodec.createDecoderByType(MIME_TYPE)
            }

            mediaCodec.configure(format, surface, null, 0)
            mediaCodec.start()

            this.codec = mediaCodec
            this.isRunning = true
            Log.i(TAG, "Hardware HEVC MediaCodec initialized & active!")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start MediaCodec", e)
        }
    }

    fun decodeNalu(naluData: ByteArray, presentationTimeUs: Long, isKeyframe: Boolean) {
        val currentCodec = codec ?: return
        if (!isRunning) return

        try {
            val inputIndex = currentCodec.dequeueInputBuffer(4000) // 4ms wait to prevent frame drops
            if (inputIndex >= 0) {
                val inputBuffer: ByteBuffer? = currentCodec.getInputBuffer(inputIndex)
                inputBuffer?.clear()
                inputBuffer?.put(naluData)

                val flags = if (isKeyframe) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0
                // Pass PTS 0 to disable Surface timestamp pacing so frames display instantly with zero delay
                currentCodec.queueInputBuffer(inputIndex, 0, naluData.size, 0, flags)
            }

            // Drain output buffers directly to Surface immediately
            val bufferInfo = MediaCodec.BufferInfo()
            var outputIndex = currentCodec.dequeueOutputBuffer(bufferInfo, 0)
            while (outputIndex >= 0) {
                currentCodec.releaseOutputBuffer(outputIndex, true)
                updateStats()
                outputIndex = currentCodec.dequeueOutputBuffer(bufferInfo, 0)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error during NALU decode", e)
        }
    }

    private fun updateStats() {
        frameCount++
        val now = System.currentTimeMillis()
        val elapsed = now - lastFpsTimestamp
        if (elapsed >= 1000) {
            val fps = (frameCount * 1000f) / elapsed
            onFrameRendered(fps)
            frameCount = 0
            lastFpsTimestamp = now
        }
    }

    private fun selectBestLowLatencyCodec(mimeType: String): String? {
        val codecList = MediaCodecList(MediaCodecList.ALL_CODECS)
        var lowLatencyCandidate: String? = null
        var hardwareCandidate: String? = null

        for (codecInfo in codecList.codecInfos) {
            if (codecInfo.isEncoder) continue

            val types = codecInfo.supportedTypes
            for (type in types) {
                if (type.equals(mimeType, ignoreCase = true)) {
                    val name = codecInfo.name
                    // Prioritize lowlatency hardware codec on Dimensity / MTK / Qualcomm
                    if (name.contains("lowlatency", ignoreCase = true)) {
                        return name
                    }
                    if (codecInfo.isHardwareAccelerated && hardwareCandidate == null) {
                        hardwareCandidate = name
                    }
                }
            }
        }
        return lowLatencyCandidate ?: hardwareCandidate
    }

    fun stopDecoder() {
        isRunning = false
        try {
            codec?.stop()
            codec?.release()
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping decoder", e)
        }
        codec = null
    }
}
