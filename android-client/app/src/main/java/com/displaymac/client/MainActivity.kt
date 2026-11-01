package com.displaymac.client

import android.animation.ObjectAnimator
import android.animation.PropertyValuesHolder
import android.animation.ValueAnimator
import android.os.Bundle
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.WindowManager
import android.widget.EditText
import android.widget.ImageView
import android.widget.ProgressBar
import android.widget.TextView
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.widget.AppCompatButton
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.displaymac.client.audio.LowLatencyAudioPlayer
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
    private lateinit var speedText: TextView
    private lateinit var btnDisconnect: AppCompatButton

    private lateinit var radarIcon: ImageView
    private lateinit var dashStatusTitle: TextView
    private lateinit var dashStatusSub: TextView
    private lateinit var btnConnectUsb: AppCompatButton
    private lateinit var btnConnectWifi: AppCompatButton
    private lateinit var manualIpInput: EditText
    private lateinit var tvWifiDiscoveryStatus: TextView
    private lateinit var searchProgress: ProgressBar
    private lateinit var tvStatusMessage: TextView

    private lateinit var displayModeManager: DisplayModeManager
    private var videoDecoder: LowLatencyVideoDecoder? = null
    private var audioPlayer: LowLatencyAudioPlayer? = null
    private var connectionManager: ConnectionManager? = null
    private var pulseAnimator: ObjectAnimator? = null
    private var surfaceHolderRef: SurfaceHolder? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Keep screen active indefinitely
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        // Initialize low-latency audio renderer
        audioPlayer = LowLatencyAudioPlayer()

        // Inflate view hierarchy
        setContentView(R.layout.activity_main)

        // Hide system status and navigation bars safely
        hideSystemUI()

        // Bind all UI Views
        bindViews()

        // Lock to Samsung Galaxy Tab S10 Ultra 120Hz native refresh rate
        displayModeManager = DisplayModeManager(this)
        displayModeManager.lockToHighestRefreshRate()

        // Setup subtle breathing pulse animation on Radar Icon
        startRadarPulse()

        // Register Hardware Back Navigation / Gesture Handler
        setupBackNavigation()

        // Wire Action Buttons
        setupActionButtons()

        // Prepare Connection Manager & Input Handlers
        initConnectionManager()

        // Prepare SurfaceView
        setupSurface()

        // Auto-search and connect over USB-C on launch (Headless Ready)
        videoSurface.postDelayed({
            if (connectionManager?.isConnected != true && !isFinishing) {
                connectUsingUsb()
            }
        }, 600)
    }

    private fun bindViews() {
        videoSurface = findViewById(R.id.videoSurface)
        dashboardLayout = findViewById(R.id.dashboardLayout)
        hudOverlay = findViewById(R.id.hudOverlay)
        statusText = findViewById(R.id.statusText)
        fpsText = findViewById(R.id.fpsText)
        speedText = findViewById(R.id.speedText)
        btnDisconnect = findViewById(R.id.btnDisconnect)

        radarIcon = findViewById(R.id.radarIcon)
        dashStatusTitle = findViewById(R.id.dashStatusTitle)
        dashStatusSub = findViewById(R.id.dashStatusSub)
        btnConnectUsb = findViewById(R.id.btnConnectUsb)
        btnConnectWifi = findViewById(R.id.btnConnectWifi)
        manualIpInput = findViewById(R.id.manualIpInput)
        tvWifiDiscoveryStatus = findViewById(R.id.tvWifiDiscoveryStatus)
        searchProgress = findViewById(R.id.searchProgress)
        tvStatusMessage = findViewById(R.id.tvStatusMessage)
    }

    private fun setupBackNavigation() {
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (connectionManager?.isConnected == true) {
                    // If streaming, back button immediately disconnects and returns to dashboard
                    connectionManager?.disconnect()
                } else if (connectionManager?.isReconnecting == true) {
                    connectionManager?.cancelReconnect()
                    hideLoading()
                    showStatusMessage("Auto-connection stopped.", isError = false)
                } else {
                    // On dashboard, minimize app smoothly without killing process
                    moveTaskToBack(true)
                }
            }
        })
    }

    private fun setupActionButtons() {
        // 1. USB-C Cable Connection Button (Toggles connect or cancel auto-connect)
        btnConnectUsb.setOnClickListener {
            if (connectionManager?.isReconnecting == true) {
                connectionManager?.cancelReconnect()
                hideLoading()
                showStatusMessage("Auto-connection stopped. Tap button to reconnect.", isError = false)
            } else {
                connectUsingUsb()
            }
        }

        // 2. Wi-Fi Wireless Connection Button
        btnConnectWifi.setOnClickListener {
            val ip = manualIpInput.text.toString().trim()
            if (ip.isEmpty()) {
                showStatusMessage("⚠️ Please enter Mac mini IP address", isError = true)
                return@setOnClickListener
            }
            connectUsingWifi(ip)
        }

        // 3. Floating HUD Disconnect Button
        btnDisconnect.setOnClickListener {
            connectionManager?.disconnect()
        }
    }

    private fun connectUsingUsb() {
        val holder = surfaceHolderRef ?: videoSurface.holder
        showConnectingState("Connecting to Mac via USB Cable (127.0.0.1)...")
        if (holder.surface.isValid) {
            ensureDecoderActive(holder)
        }

        connectionManager?.connectToHost(
            host = "127.0.0.1",
            connectionMode = "USB 5 Gbps",
            autoRetry = true,
            onError = { error ->
                hideLoading()
                showStatusMessage(
                    "⚠️ USB Cable Connection Failed!\n1. Plug USB-C cable between Mac and Tablet.\n2. Ensure Mac background service is running.\n3. Verify Samsung Auto Blocker is OFF.",
                    isError = true
                )
            }
        )
    }

    private fun connectUsingWifi(ip: String) {
        val holder = surfaceHolderRef ?: videoSurface.holder
        showConnectingState("Connecting to Mac at $ip over Wi-Fi...")
        if (holder.surface.isValid) {
            ensureDecoderActive(holder)
        }

        connectionManager?.connectToHost(
            host = ip,
            connectionMode = "Wi-Fi (Wireless)",
            autoRetry = false,
            onError = { error ->
                hideLoading()
                showStatusMessage(
                    "⚠️ Wi-Fi Connection Failed to $ip!\n1. Make sure Mac DisplayMacServer is running.\n2. Check that both Mac and Tablet are on the same Wi-Fi network.",
                    isError = true
                )
            }
        )
    }

    private fun ensureDecoderActive(holder: SurfaceHolder) {
        if (videoDecoder == null) {
            val decoder = LowLatencyVideoDecoder(holder.surface) { liveFps ->
                runOnUiThread {
                    fpsText.text = String.format(java.util.Locale.US, "%.0f FPS", liveFps)
                }
            }
            decoder.initDecoder(width = 2960, height = 1848)
            this.videoDecoder = decoder
        }
    }

    private fun showConnectingState(message: String) {
        searchProgress.visibility = View.VISIBLE
        tvStatusMessage.visibility = View.VISIBLE
        tvStatusMessage.text = message
        tvStatusMessage.setTextColor(getColor(R.color.status_cyan))
        btnConnectUsb.text = "✕ Stop Connecting"
        btnConnectUsb.isEnabled = true
        btnConnectWifi.isEnabled = false
    }

    private fun hideLoading() {
        searchProgress.visibility = View.GONE
        btnConnectUsb.text = "⚡ Connect via USB Cable"
        btnConnectUsb.isEnabled = true
        btnConnectWifi.isEnabled = true
    }

    private fun showStatusMessage(message: String, isError: Boolean) {
        tvStatusMessage.visibility = View.VISIBLE
        tvStatusMessage.text = message
        tvStatusMessage.setTextColor(if (isError) getColor(R.color.status_red) else getColor(R.color.status_cyan))
    }

    private fun setupSurface() {
        videoSurface.holder.addCallback(object : SurfaceHolder.Callback {
            override fun surfaceCreated(holder: SurfaceHolder) {
                surfaceHolderRef = holder
                if (connectionManager?.isConnected == true) {
                    // Resumed from background/minimize while connected!
                    android.util.Log.i("MainActivity", "Resuming video pipeline after minimize/resume...")
                    ensureDecoderActive(holder)
                    connectionManager?.requestKeyframe()
                    videoSurface.visibility = View.VISIBLE
                    hudOverlay.visibility = View.VISIBLE
                    dashboardLayout.visibility = View.GONE
                }
            }

            override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {}

            override fun surfaceDestroyed(holder: SurfaceHolder) {
                surfaceHolderRef = null
                // Stop decoder since surface is destroyed, but DO NOT disconnect network!
                // TCP socket & audio playback remain alive in background.
                videoDecoder?.stopDecoder()
                videoDecoder = null
            }
        })
    }

    private fun initConnectionManager() {
        // Initialize Connection Manager with Smart Auto-Reconnect Watchdog
        val connManager = ConnectionManager(
            context = this,
            onConnected = { mode ->
                hideLoading()
                
                // Ensure decoder is active and surface is ready
                val holder = surfaceHolderRef ?: videoSurface.holder
                if (holder.surface.isValid) {
                    ensureDecoderActive(holder)
                }

                // Start low-latency audio playback to Galaxy Tab AKG quad speakers
                audioPlayer?.start()
                
                // Request immediate keyframe
                connectionManager?.requestKeyframe()
                
                // Hide Dashboard and reveal 120Hz Mac desktop stream
                dashboardLayout.animate()
                    .alpha(0f)
                    .setDuration(250)
                    .withEndAction { dashboardLayout.visibility = View.GONE }
                    .start()

                hudOverlay.visibility = View.VISIBLE
                hudOverlay.alpha = 0f
                hudOverlay.animate().alpha(1f).setDuration(250).start()

                statusText.text = "Connected ($mode)"
                statusText.setTextColor(getColor(R.color.status_green))
                fpsText.text = "120 FPS"
            },
            onDisconnected = { wasUnexpected ->
                // Stop audio playback
                audioPlayer?.stop()
                
                // Return to Dashboard cleanly
                dashboardLayout.bringToFront()
                dashboardLayout.alpha = 1f
                dashboardLayout.visibility = View.VISIBLE
                hudOverlay.visibility = View.GONE

                // Release decoder session to ensure fresh keyframe on next connect
                videoDecoder?.stopDecoder()
                videoDecoder = null

                if (wasUnexpected) {
                    showConnectingState("⚡ Cable disconnected or Mac sleeping. Reconnecting automatically...")
                } else {
                    hideLoading()
                    showStatusMessage("Session ended. Connect via USB or Wi-Fi to resume.", isError = false)
                }
            },
            onReconnecting = { attempt, mode ->
                showConnectingState("🔄 Waiting for Mac mini over $mode... (Auto-retrying #$attempt)")
            },
            onVideoFrame = { nalu, ptsUs, isKeyframe ->
                videoDecoder?.decodeNalu(nalu, ptsUs, isKeyframe)
            },
            onAudioFrame = { pcm ->
                audioPlayer?.playAudio(pcm)
            },
            onSpeedUpdated = { mbps ->
                runOnUiThread {
                    speedText.text = String.format(java.util.Locale.US, "⚡ %.1f Mbps", mbps)
                }
            }
        )
        this.connectionManager = connManager

        // Attach S-Pen Stylus & Multi-Touch Input Handler (Precision Pencil + Palm Rejection + Smooth Hover)
        val stylusHandler = StylusInputHandler { controlPacket ->
            connManager.sendControlPacket(controlPacket)
        }
        videoSurface.setOnTouchListener(stylusHandler)
        videoSurface.setOnHoverListener(stylusHandler)

        // Start Background Bonjour mDNS Discovery (Discovers Mac IP without auto-connecting)
        connManager.startMdnsDiscovery { discoveredIp ->
            if (manualIpInput.text.isNullOrEmpty()) {
                manualIpInput.setText(discoveredIp)
            }
            tvWifiDiscoveryStatus.text = "• Both devices on same Wi-Fi router\n• ✅ Discovered Mac: $discoveredIp\n• Tap 'Connect via Wi-Fi' below"
        }
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

    private fun hideSystemUI() {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        val controller = WindowCompat.getInsetsController(window, window.decorView)
        controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        controller.hide(WindowInsetsCompat.Type.systemBars())
    }

    override fun onResume() {
        super.onResume()
        hideSystemUI()
        if (connectionManager?.isConnected == true) {
            val holder = surfaceHolderRef ?: videoSurface.holder
            if (holder.surface.isValid) {
                ensureDecoderActive(holder)
                connectionManager?.requestKeyframe()
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        pulseAnimator?.cancel()
        videoDecoder?.stopDecoder()
        videoDecoder = null
        audioPlayer?.stop()
        audioPlayer = null
        connectionManager?.shutdown()
    }
}
