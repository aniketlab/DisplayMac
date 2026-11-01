package com.displaymac.client.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.displaymac.client.ui.theme.AuroraBlue
import com.displaymac.client.ui.theme.AuroraPink
import com.displaymac.client.ui.theme.AuroraSky
import com.displaymac.client.ui.theme.AuroraSurface

/** Small version of the app icon: a Mac display with a tablet in front. */
@Composable
fun LogoMark(modifier: Modifier = Modifier, size: Dp = 26.dp) {
    Canvas(modifier.size(size)) {
        val u = this.size.width / 24f
        fun box(x: Float, y: Float, w: Float, h: Float, r: Float, color: Color) {
            drawRoundRect(
                color = color,
                topLeft = Offset(x * u, y * u),
                size = Size(w * u, h * u),
                cornerRadius = CornerRadius(r * u),
            )
        }
        box(1f, 4f, 16f, 11f, 3f, Color(0xFF2A2A2E))
        box(2.5f, 5.5f, 13f, 8f, 1.8f, Color(0xFFEC6BB7))
        box(11f, 10f, 11f, 8f, 2.5f, Color(0xFF101015))
        box(12f, 11f, 9f, 6f, 1.6f, Color(0xFF58BDFB))
    }
}

/** Light surface with three soft color blobs, like the icon's wallpaper. */
@Composable
fun AuroraBackdrop(
    modifier: Modifier = Modifier,
    content: @Composable BoxScope.() -> Unit,
) {
    Box(
        modifier = modifier
            .fillMaxSize()
            .background(AuroraSurface)
            .drawBehind {
                val m = size.minDimension
                drawCircle(
                    color = AuroraPink.copy(alpha = 0.14f),
                    radius = m * 0.45f,
                    center = Offset(size.width, 0f),
                )
                drawCircle(
                    color = AuroraSky.copy(alpha = 0.20f),
                    radius = m * 0.55f,
                    center = Offset(0f, size.height),
                )
                drawCircle(
                    color = AuroraBlue.copy(alpha = 0.07f),
                    radius = m * 0.30f,
                    center = Offset(size.width * 0.45f, size.height * 0.9f),
                )
            },
        content = content,
    )
}
