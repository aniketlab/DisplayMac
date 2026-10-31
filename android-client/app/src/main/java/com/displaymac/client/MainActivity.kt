package com.displaymac.client

import android.animation.ObjectAnimator
import android.animation.PropertyValuesHolder
import android.animation.ValueAnimator
import android.os.Bundle
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.EditText
import android.widget.ImageView
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.displaymac.client.decoder.LowLatencyVideoDecoder
import com.displaymac.client.display.DisplayModeManager
import com.displaymac.client.input.StylusInputHandler
import com.displaymac.client.network.ConnectionManager

class MainActivity : AppCompatActivity() {

    private lateinit var videoSurface: SurfaceView
    private lateinit var dashboardLayout: View
    private lateinit var hudOverlay: View
    private lateinit var statusText: TextView
    private lateinit var fpsText: TextView
    private lateinit var manualIpInput: EditText
    private lateinit var connectBtn: Button
    private lateinit var radarIcon: ImageView
    private lateinit var dashStatusTitle: TextView
    private lateinit var cardLinkSub: TextView

    private lateinit var displayModeManager: DisplayModeManager
    private var videoDecoder: LowLatencyVideoDecoder? = null
    private var connectionManager: ConnectionManager? = null
    private var pulseAnimator: ObjectAnimator? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Keep screen on indefinitely
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        // Initialize view hierarchy
        setContentView(R.layout.activity_main)

        // Hide system UI safely
        hideSystemUI()

        // Bind Views
        videoSurface = findViewById(R.id.videoSurface)
        dashboardLayout = findViewById(R.id.dashboardLayout)
        hudOverlay = findViewById(R.id.hudOverlay)
        statusText = findViewById(R.id.statusText)
        fpsText = findViewById(R.id.fpsText)
        manualIpInput = findViewById(R.id.manualIpInput)
        connectBtn = findViewById(R.id.connectBtn)
        radarIcon = findViewById(R.id.radarIcon)
        dashStatusTitle = findViewById(R.id.dashStatusTitle)
        cardLinkSub = findViewById(R.id.cardLinkSub)

        // Lock to 120Hz native refresh rate
        displayModeManager = DisplayModeManager(this)
        displayModeManager.lockToHighestRefreshRate()

        // Start subtle breathing pulse animation on Radar Icon
        startRadarPulse()

        // Setup Manual IP button
        connectBtn.setOnClickListener {
            val ip = manualIpInput.text.toString().trim()
            if (ip.isNotEmpty()) {
                dashStatusTitle.text = "Connecting to $ip..."
                cardLinkSub.text = "Connecting to $ip..."
                connectionManager?.connectToHost(ip, "Direct IP")
            }
        }

        setupSurface()
    }

    private fun startRadarPulse() {
        pulseAnimator = ObjectAnimator.ofPropertyValuesHolder(
            radarIcon,
            PropertyValuesHolder.ofFloat(View.SCALE_X, 1.0f, 1.08f),
            PropertyValuesHolder.ofFloat(View.SCALE_Y, 1.0f, 1.08f),
            PropertyValuesHolder.ofFloat(View.ALPHA, 0.85f, 1.0f)
        ).apply {
            duration = 1400
            repeatCount = ValueAnimator.INFINITE
            repeatMode = ValueAnimator.REVERSE
            start()
        }
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
                // Smooth transition: Hide dashboard and reveal live 120Hz Mac desktop!
                dashboardLayout.animate()
                    .alpha(0f)
                    .setDuration(400)
                    .withEndAction { dashboardLayout.visibility = View.GONE }
                    .start()

                hudOverlay.visibility = View.VISIBLE
                hudOverlay.alpha = 0f
                hudOverlay.animate().alpha(1f).setDuration(400).start()

                statusText.text = "Connected ($mode)"
                statusText.setTextColor(getColor(R.color.status_green))
            },
            onDisconnected = {
                runOnUiThread {
                    dashboardLayout.bringToFront()
                    dashboardLayout.alpha = 1f
                    dashboardLayout.visibility = View.VISIBLE
                    hudOverlay.visibility = View.GONE
                    dashStatusTitle.text = "Mac Mini Disconnected"
                    cardLinkSub.text = "Searching for USB / Wi-Fi..."
                }
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
        WindowCompat.setDecorFitsSystemWindows(window, false)
        val controller = WindowCompat.getInsetsController(window, window.decorView)
        controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        controller.hide(WindowInsetsCompat.Type.systemBars())
    }

    override fun onResume() {
        super.onResume()
        hideSystemUI()
    }

    override fun onDestroy() {
        super.onDestroy()
        pulseAnimator?.cancel()
        videoDecoder?.stopDecoder()
        connectionManager?.stop()
    }
}
