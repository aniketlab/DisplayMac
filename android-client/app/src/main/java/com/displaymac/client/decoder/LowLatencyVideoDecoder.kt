package com.displaymac.client.decoder

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import android.os.Build
import android.util.Log
import android.view.Surface

class LowLatencyVideoDecoder(
    private val surface: Surface,
    private val onFrameRendered: (fps: Float) -> Unit
) {
    companion object {
        private const val TAG = "LowLatencyDecoder"
        private const val MIME_TYPE = MediaFormat.MIMETYPE_VIDEO_HEVC
    }

    private val codecLock = Any()
    private var codec: MediaCodec? = null
    private var isRunning = false
    private var waitingForKeyframe = true
    private var frameCount = 0
    private var lastFpsTimestamp = System.currentTimeMillis()

    fun initDecoder(width: Int, height: Int, operatingFps: Int) {
        synchronized(codecLock) {
            stopDecoderLocked()
            waitingForKeyframe = true
            frameCount = 0
            lastFpsTimestamp = System.currentTimeMillis()

            val decoderName = selectBestLowLatencyCodec(MIME_TYPE)
            Log.i(TAG, "Selected hardware HEVC decoder: $decoderName for ${width}x${height} @ ${operatingFps}Hz")

            val format = MediaFormat.createVideoFormat(MIME_TYPE, width, height).apply {
                setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
                setInteger(MediaFormat.KEY_PRIORITY, 0)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    setInteger(MediaFormat.KEY_LOW_LATENCY, 1)
                }
                setInteger(MediaFormat.KEY_OPERATING_RATE, operatingFps)
                try { setInteger("vendor.qcom-ext-dec-low-latency.enable", 1) } catch (_: Exception) {}
                try { setInteger("vendor.low-latency.enable", 1) } catch (_: Exception) {}
                try { setInteger("vendor.media.codec.low-latency", 1) } catch (_: Exception) {}
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
                Log.i(TAG, "Hardware HEVC MediaCodec initialized and active")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start MediaCodec", e)
            }
        }
    }

    fun decodeNalu(naluData: ByteArray, @Suppress("UNUSED_PARAMETER") presentationTimeUs: Long, isKeyframe: Boolean) {
        synchronized(codecLock) {
            val currentCodec = codec ?: return
            if (!isRunning) return

            if (waitingForKeyframe) {
                if (!isKeyframe) {
                    return
                }
                waitingForKeyframe = false
                Log.i(TAG, "Initial IDR keyframe received; starting hardware decode")
            }

            try {
                var inputIndex = currentCodec.dequeueInputBuffer(0)
                if (inputIndex < 0) {
                    drainOutput(currentCodec)
                    inputIndex = currentCodec.dequeueInputBuffer(1000)
                }

                if (inputIndex >= 0) {
                    val inputBuffer = currentCodec.getInputBuffer(inputIndex)
                    inputBuffer?.clear()
                    inputBuffer?.put(naluData)

                    val flags = if (isKeyframe) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0
                    // Pass PTS 0 to render immediately without VSYNC pacing queue delay.
                    currentCodec.queueInputBuffer(inputIndex, 0, naluData.size, 0, flags)
                }

                drainOutput(currentCodec)
            } catch (e: Exception) {
                Log.e(TAG, "Error during NALU decode", e)
            }
        }
    }

    private fun drainOutput(currentCodec: MediaCodec) {
        val bufferInfo = MediaCodec.BufferInfo()
        var outputIndex = currentCodec.dequeueOutputBuffer(bufferInfo, 0)
        while (outputIndex >= 0) {
            currentCodec.releaseOutputBuffer(outputIndex, true)
            updateStats()
            outputIndex = currentCodec.dequeueOutputBuffer(bufferInfo, 0)
        }
    }

    private fun updateStats() {
        frameCount++
        val now = System.currentTimeMillis()
        val elapsed = now - lastFpsTimestamp
        if (elapsed >= 500) {
            val fps = (frameCount * 1000f) / elapsed
            onFrameRendered(fps)
            frameCount = 0
            lastFpsTimestamp = now
        }
    }

    private fun selectBestLowLatencyCodec(mimeType: String): String? {
        val codecList = MediaCodecList(MediaCodecList.ALL_CODECS)
        var hardwareCandidate: String? = null

        for (codecInfo in codecList.codecInfos) {
            if (codecInfo.isEncoder) continue

            for (type in codecInfo.supportedTypes) {
                if (type.equals(mimeType, ignoreCase = true)) {
                    val name = codecInfo.name
                    if (name.contains("lowlatency", ignoreCase = true)) {
                        return name
                    }
                    val isHardware = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        codecInfo.isHardwareAccelerated
                    } else {
                        !name.startsWith("OMX.google.", ignoreCase = true) &&
                            !name.startsWith("c2.android.", ignoreCase = true)
                    }
                    if (isHardware && hardwareCandidate == null) {
                        hardwareCandidate = name
                    }
                }
            }
        }
        return hardwareCandidate
    }

    fun stopDecoder() {
        synchronized(codecLock) {
            stopDecoderLocked()
        }
    }

    private fun stopDecoderLocked() {
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
