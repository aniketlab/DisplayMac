package com.displaymac.client.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val AuroraColorScheme = lightColorScheme(
    primary = AuroraBlue,
    onPrimary = Color.White,
    primaryContainer = AuroraBlueContainer,
    onPrimaryContainer = AuroraBlueDark,
    secondary = AuroraSky,
    onSecondary = Color.White,
    secondaryContainer = AuroraSkyContainer,
    onSecondaryContainer = AuroraSkyDark,
    tertiary = AuroraPink,
    background = AuroraSurface,
    onBackground = AuroraInk,
    surface = AuroraCard,
    onSurface = AuroraInk,
    surfaceVariant = AuroraChip,
    onSurfaceVariant = AuroraInkSecondary,
    outline = AuroraOutline,
    outlineVariant = AuroraBorder,
    error = AuroraError,
)

/**
 * Light-only on purpose: the Aurora look is a light, wallpaper-style theme.
 * Dynamic color (Material You) is NOT used so the app always matches the logo.
 */
@Composable
fun DisplayMacTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = AuroraColorScheme,
        typography = DisplayMacTypography,
        content = content,
    )
}
