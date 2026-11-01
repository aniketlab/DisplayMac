package com.displaymac.client.ui.connect

import android.hardware.display.DisplayManager
import android.os.Build
import android.provider.Settings
import android.view.Display
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import kotlin.math.roundToInt

data class DeviceInfo(
    /** Name the user sees, e.g. "Galaxy Tab S10 Ultra". */
    val name: String,
    /** e.g. "2960 × 1848 · 120 Hz". */
    val specLabel: String,
) {
    val pillLabel: String get() = "$name · $specLabel"
}

/** Reads the tablet's own name, native resolution and refresh rate. */
@Composable
fun rememberDeviceInfo(): DeviceInfo {
    val context = LocalContext.current
    return remember(context) {
        val name = Settings.Global.getString(context.contentResolver, Settings.Global.DEVICE_NAME)
            ?.takeIf { it.isNotBlank() }
            ?: Build.MODEL

        val display = context.getSystemService(DisplayManager::class.java)
            .getDisplay(Display.DEFAULT_DISPLAY)
        val mode = display.mode
        val w = maxOf(mode.physicalWidth, mode.physicalHeight)
        val h = minOf(mode.physicalWidth, mode.physicalHeight)
        val hz = display.refreshRate.roundToInt()

        DeviceInfo(name = name, specLabel = "$w × $h · $hz Hz")
    }
}
