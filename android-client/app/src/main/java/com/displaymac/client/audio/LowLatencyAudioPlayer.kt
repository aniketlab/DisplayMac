package com.displaymac.client.audio

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.util.Log

/**
 * Low-latency 48 kHz 16-bit stereo PCM audio renderer backed by AudioTrack.
 */
class LowLatencyAudioPlayer {
    companion object {
        private const val TAG = "AudioPlayer"
        private const val SAMPLE_RATE = 48000
    }

    private var audioTrack: AudioTrack? = null
    private var isPlaying = false

    fun start() {
        if (isPlaying) return
        try {
            val minBufferSize = AudioTrack.getMinBufferSize(
                SAMPLE_RATE,
                AudioFormat.CHANNEL_OUT_STEREO,
                AudioFormat.ENCODING_PCM_16BIT
            )
            val bufferSize = (minBufferSize * 2).coerceAtLeast(4096)

            val track = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(SAMPLE_RATE)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
                        .build()
                )
                .setBufferSizeInBytes(bufferSize)
                .setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()

            track.play()
            this.audioTrack = track
            this.isPlaying = true
            Log.i(TAG, "LowLatencyAudioPlayer active: 48 kHz stereo PCM")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start AudioTrack", e)
        }
    }

    fun playAudio(pcmData: ByteArray) {
        if (!isPlaying) return
        try {
            audioTrack?.write(pcmData, 0, pcmData.size, AudioTrack.WRITE_NON_BLOCKING)
        } catch (e: Exception) {
            Log.e(TAG, "Error writing audio buffer", e)
        }
    }

    fun stop() {
        isPlaying = false
        try {
            audioTrack?.pause()
            audioTrack?.flush()
            audioTrack?.stop()
            audioTrack?.release()
        } catch (_: Exception) {}
        audioTrack = null
    }
}
