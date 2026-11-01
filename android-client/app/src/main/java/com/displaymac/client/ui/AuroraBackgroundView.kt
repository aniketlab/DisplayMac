package com.displaymac.client.ui

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.util.AttributeSet
import android.view.View

/**
 * Native hardware-accelerated Aurora backdrop:
 * Renders a light surface with three soft, organic ambient color blobs matching the Aurora design prototype.
 */
class AuroraBackgroundView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : View(context, attrs, defStyleAttr) {

    private val bgPaint = Paint().apply { color = 0xFFF6F7FC.toInt() }
    private val pinkPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0x24FF6AB5.toInt() } // 14% alpha
    private val skyPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0x335AD1FF.toInt() }  // 20% alpha
    private val bluePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0x123B4DE0.toInt() } // 7% alpha

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), bgPaint)

        val m = minOf(width, height).toFloat()
        // Top right pink blob
        canvas.drawCircle(width.toFloat(), 0f, m * 0.45f, pinkPaint)
        // Bottom left sky blue blob
        canvas.drawCircle(0f, height.toFloat(), m * 0.55f, skyPaint)
        // Center bottom blue blob
        canvas.drawCircle(width * 0.45f, height * 0.9f, m * 0.30f, bluePaint)
    }
}
