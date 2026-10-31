package com.displaymac.client

import android.os.Build
import android.os.Bundle
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.displaymac.client.decoder.LowLatencyVideoDecoder
import com.displaymac.client.display.DisplayModeManager
import com.displaymac.client.input.StylusInputHandler
import com.displaymac.client.network.ConnectionManager

class MainActivity : AppCompatActivity() {

    private lateinit var videoSurface: SurfaceView
    private lateinit var statusText: TextView
    private lateinit var fpsText: TextView

    private lateinit var displayModeManager: DisplayModeManager
    private var videoDecoder: LowLatencyVideoDecoder? = null
    private var connectionManager: ConnectionManager? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        hideSystemUI()

        // Keep screen on indefinitely
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        setContentView(R.layout.activity_main)

        videoSurface = findViewById(R.id.videoSurface)
        statusText = findViewById(R.id.statusText)
        fpsText = findViewById(R.id.fpsText)

        // Lock to 120Hz native refresh rate
        displayModeManager = DisplayModeManager(this)
        displayModeManager.lockToHighestRefreshRate()

        setupSurface()
    }

    private fun setupSurface() {
        videoSurface.holder.addCallback(object : SurfaceHolder.Callback {
            override fun surfaceCreated(holder: SurfaceHolder) {
                initPipeline(holder)
            }

            override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {}

            override fun surfaceDestroyed(holder: SurfaceHolder) {
                videoDecoder?.stopDecoder()
                connectionManager?.stop()
            }
        })
    }

    private fun initPipeline(holder: SurfaceHolder) {
        // 1. Initialize Hardware Low-Latency Decoder
        val decoder = LowLatencyVideoDecoder(holder.surface) { currentFps ->
            runOnUiThread {
                fpsText.text = String.format("%.0f FPS", currentFps)
            }
        }
        decoder.initDecoder(width = 2960, height = 1848)
        this.videoDecoder = decoder

        // 2. Setup Connection Manager
        val connManager = ConnectionManager(
            context = this,
            onConnected = { mode ->
                statusText.text = "Connected ($mode)"
                statusText.setTextColor(getColor(R.color.status_green))
            },
            onDisconnected = {
                statusText.text = getString(R.string.status_disconnected)
                statusText.setTextColor(getColor(R.color.white))
            },
            onVideoFrame = { nalu, ptsUs, isKeyframe ->
                decoder.decodeNalu(nalu, ptsUs, isKeyframe)
            }
        )
        this.connectionManager = connManager

        // 3. Attach S-Pen & Multi-touch Input Handler
        val stylusHandler = StylusInputHandler { controlPacket ->
            connManager.sendControlPacket(controlPacket)
        }
        videoSurface.setOnTouchListener(stylusHandler)
        videoSurface.setOnHoverListener(stylusHandler)

        // 4. Start Auto Discovery (USB Priority -> Wi-Fi mDNS)
        connManager.startAutoDiscoveryAndConnect()
    }

    private fun hideSystemUI() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.let { controller ->
                controller.hide(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())
                controller.systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                    or View.SYSTEM_UI_FLAG_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
            )
        }
    }

    override fun onResume() {
        super.onResume()
        hideSystemUI()
    }

    override fun onDestroy() {
        super.onDestroy()
        videoDecoder?.stopDecoder()
        connectionManager?.stop()
    }
}
