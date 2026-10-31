package com.displaymac.client.audio

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.util.Log

/**
 * High-fidelity, ultra-low latency audio renderer for Galaxy Tab S10 Ultra quad AKG speakers.
 * Streams 48kHz 16-bit Stereo PCM directly over the zero-latency USB wire.
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
            // Double buffer size for jitter tolerance while keeping sub-10ms buffer
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
            Log.i(TAG, "⚡ LowLatencyAudioPlayer active: 48kHz Stereo PCM to Tab S10 Ultra speakers")
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
