package com.displaymac.client.display

import android.content.Context
import android.hardware.display.DisplayManager
import android.os.Build
import android.provider.Settings
import android.view.Display
import java.util.Locale
import kotlin.math.roundToInt

data class DeviceDisplayProfile(
    val marketingName: String,
    val widthPx: Int,
    val heightPx: Int,
    val refreshRateHz: Int,
    val densityDpi: Int,
    val isSamsung: Boolean
)

/**
 * Resolves device display metrics and human-readable model naming cleanly
 * without duplicating lookup tables across activities and networking code.
 */
object DeviceProfile {

    private val rawModelCodePattern = Regex("^[A-Z0-9_-]{4,10}$")

    fun inspect(context: Context): DeviceDisplayProfile {
        val systemSettingsName = readSystemDeviceName(context)
        val marketingName = resolveMarketingName(
            manufacturer = Build.MANUFACTURER,
            model = Build.MODEL,
            systemDeviceName = systemSettingsName
        )

        val metrics = context.resources.displayMetrics
        val densityDpi = metrics.densityDpi.coerceAtLeast(160)

        var widthPx = maxOf(metrics.widthPixels, metrics.heightPixels).coerceAtLeast(1280)
        var heightPx = minOf(metrics.widthPixels, metrics.heightPixels).coerceAtLeast(720)
        var refreshRateHz = 60

        try {
            val displayManager = context.getSystemService(DisplayManager::class.java)
            val display = displayManager?.getDisplay(Display.DEFAULT_DISPLAY)
            if (display != null) {
                val highestMode = display.supportedModes.maxByOrNull { it.refreshRate } ?: display.mode
                widthPx = maxOf(highestMode.physicalWidth, highestMode.physicalHeight)
                heightPx = minOf(highestMode.physicalWidth, highestMode.physicalHeight)
                refreshRateHz = highestMode.refreshRate.roundToInt().coerceAtLeast(30)
            }
        } catch (_: Exception) {
            // Fall back to DisplayMetrics dimensions above.
        }

        return DeviceDisplayProfile(
            marketingName = marketingName,
            widthPx = widthPx,
            heightPx = heightPx,
            refreshRateHz = refreshRateHz,
            densityDpi = densityDpi,
            isSamsung = Build.MANUFACTURER.equals("samsung", ignoreCase = true)
        )
    }

    internal fun resolveMarketingName(
        manufacturer: String,
        model: String,
        systemDeviceName: String?
    ): String {
        val cleanModel = model.trim()
        val mappedModel = mapKnownModel(cleanModel)
        val cleanSystemName = systemDeviceName?.trim()?.takeIf {
            it.isNotEmpty() && !it.equals("unknown", ignoreCase = true)
        }
        val capitalizedMfg = manufacturer.trim().replaceFirstChar {
            if (it.isLowerCase()) it.titlecase(Locale.US) else it.toString()
        }

        return when {
            cleanSystemName != null && !cleanSystemName.matches(rawModelCodePattern) -> cleanSystemName
            mappedModel != null -> mappedModel
            cleanSystemName != null -> {
                if (cleanSystemName.startsWith(capitalizedMfg, ignoreCase = true)) {
                    cleanSystemName
                } else {
                    "$capitalizedMfg $cleanSystemName".trim()
                }
            }
            cleanModel.isNotEmpty() -> {
                if (cleanModel.startsWith(capitalizedMfg, ignoreCase = true)) {
                    cleanModel
                } else {
                    "$capitalizedMfg $cleanModel".trim()
                }
            }
            else -> "Android Tablet"
        }
    }

    private fun mapKnownModel(model: String): String? = when {
        model.startsWith("SM-X92", ignoreCase = true) -> "Galaxy Tab S10 Ultra"
        model.startsWith("SM-X82", ignoreCase = true) -> "Galaxy Tab S10+"
        model.startsWith("SM-X91", ignoreCase = true) -> "Galaxy Tab S9 Ultra"
        model.startsWith("SM-X81", ignoreCase = true) -> "Galaxy Tab S9+"
        model.startsWith("SM-X71", ignoreCase = true) -> "Galaxy Tab S9"
        model.startsWith("SM-X90", ignoreCase = true) -> "Galaxy Tab S8 Ultra"
        model.startsWith("SM-X80", ignoreCase = true) -> "Galaxy Tab S8+"
        model.startsWith("SM-X70", ignoreCase = true) -> "Galaxy Tab S8"
        model.startsWith("SM-T97", ignoreCase = true) -> "Galaxy Tab S7+"
        model.startsWith("SM-T87", ignoreCase = true) -> "Galaxy Tab S7"
        model.startsWith("SM-X21", ignoreCase = true) ||
            model.startsWith("SM-X20", ignoreCase = true) -> "Galaxy Tab A9+"
        model.contains("Pixel Tablet", ignoreCase = true) -> "Pixel Tablet"
        model.startsWith("OPD", ignoreCase = true) -> "OnePlus Pad"
        else -> null
    }

    private fun readSystemDeviceName(context: Context): String? {
        val resolver = context.contentResolver
        val queries = listOf(
            { Settings.Global.getString(resolver, "device_name") },
            { Settings.Secure.getString(resolver, "bluetooth_name") },
            { Settings.System.getString(resolver, "device_name") }
        )
        for (query in queries) {
            try {
                val value = query()?.trim()
                if (!value.isNullOrEmpty() && !value.equals("unknown", ignoreCase = true)) {
                    return value
                }
            } catch (_: Exception) {
                // Ignore restricted settings keys on vendor ROMs.
            }
        }
        return null
    }
}
