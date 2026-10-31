package com.displaymac.client.display

import android.app.Activity
import android.os.Build
import android.util.Log
import android.view.Display
import android.view.Window

class DisplayModeManager(private val activity: Activity) {
    companion object {
        private const val TAG = "DisplayModeManager"
    }

    fun lockToHighestRefreshRate() {
        val window: Window = activity.window
        val display: Display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity.display ?: return
        } else {
            @Suppress("DEPRECATION")
            activity.windowManager.defaultDisplay
        }

        val modes = display.supportedModes
        Log.i(TAG, "Available Display Modes count: ${modes.size}")

        // Find the mode with highest refresh rate (e.g. 120Hz) matching native resolution
        var targetMode: Display.Mode? = null
        var maxFps = 0f

        for (mode in modes) {
            Log.d(TAG, "Mode ID: ${mode.modeId}, ${mode.physicalWidth}x${mode.physicalHeight} @ ${mode.refreshRate}Hz")
            if (mode.refreshRate > maxFps) {
                maxFps = mode.refreshRate
                targetMode = mode
            }
        }

        targetMode?.let {
            Log.i(TAG, "Locking display to Mode ID ${it.modeId}: ${it.physicalWidth}x${it.physicalHeight} @ ${it.refreshRate} FPS")
            val params = window.attributes
            params.preferredDisplayModeId = it.modeId
            window.attributes = params

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                window.setFrameRate(it.refreshRate, SurfaceControlFrameRateCompat())
            }
        }
    }

    private fun SurfaceControlFrameRateCompat(): Int {
        return 0 // Surface.FRAME_RATE_COMPATIBILITY_DEFAULT
    }
}
