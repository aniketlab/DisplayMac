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

        // Prepare SurfaceView
        setupSurface()
    }

    private fun bindViews() {
        videoSurface = findViewById(R.id.videoSurface)
        dashboardLayout = findViewById(R.id.dashboardLayout)
        hudOverlay = findViewById(R.id.hudOverlay)
        statusText = findViewById(R.id.statusText)
        fpsText = findViewById(R.id.fpsText)
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
                } else {
                    // On dashboard, minimize app smoothly without killing process
                    moveTaskToBack(true)
                }
            }
        })
    }

    private fun setupActionButtons() {
        // 1. USB-C Cable Connection Button
        btnConnectUsb.setOnClickListener {
            connectUsingUsb()
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
        val holder = surfaceHolderRef
        if (holder == null) {
            showStatusMessage("Video surface not ready yet. Please wait a second.", isError = true)
            return
        }

        showLoading("Connecting to Mac via USB Cable (127.0.0.1)...")
        ensureDecoderActive(holder)

        connectionManager?.connectToHost(
            host = "127.0.0.1",
            connectionMode = "USB 5 Gbps",
            onError = { error ->
                hideLoading()
                showStatusMessage(
                    "⚠️ USB Cable Connection Failed!\n1. Plug USB-C cable between Mac and Tablet.\n2. Run './setup_usb.sh' in macos-server on Mac.\n3. Verify Samsung Auto Blocker is OFF.",
                    isError = true
                )
            }
        )
    }

    private fun connectUsingWifi(ip: String) {
        val holder = surfaceHolderRef
        if (holder == null) {
            showStatusMessage("Video surface not ready yet. Please wait a second.", isError = true)
            return
        }

        showLoading("Connecting to Mac at $ip over Wi-Fi...")
        ensureDecoderActive(holder)

        connectionManager?.connectToHost(
            host = ip,
            connectionMode = "Wi-Fi (Wireless)",
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
            val decoder = LowLatencyVideoDecoder(holder.surface) { _ ->
                runOnUiThread {
                    fpsText.text = "120 Hz"
                }
            }
            decoder.initDecoder(width = 2960, height = 1848)
            this.videoDecoder = decoder
        }
    }

    private fun showLoading(message: String) {
        searchProgress.visibility = View.VISIBLE
        tvStatusMessage.visibility = View.VISIBLE
        tvStatusMessage.text = message
        tvStatusMessage.setTextColor(getColor(R.color.status_cyan))
        btnConnectUsb.isEnabled = false
        btnConnectWifi.isEnabled = false
    }

    private fun hideLoading() {
        searchProgress.visibility = View.GONE
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
                initPipeline(holder)
            }

            override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {}

            override fun surfaceDestroyed(holder: SurfaceHolder) {
                surfaceHolderRef = null
                videoDecoder?.stopDecoder()
                videoDecoder = null
                connectionManager?.disconnect()
            }
        })
    }

    private fun initPipeline(holder: SurfaceHolder) {
        // Initialize Connection Manager
        val connManager = ConnectionManager(
            context = this,
            onConnected = { mode ->
                hideLoading()
                
                // Start low-latency audio playback to Galaxy Tab AKG quad speakers
                audioPlayer?.start()
                videoSurface.visibility = View.VISIBLE
                
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
                fpsText.text = "120 Hz"
            },
            onDisconnected = {
                // Stop audio playback
                audioPlayer?.stop()
                
                // Return to Dashboard cleanly
                dashboardLayout.bringToFront()
                dashboardLayout.alpha = 1f
                dashboardLayout.visibility = View.VISIBLE
                videoSurface.visibility = View.INVISIBLE
                hudOverlay.visibility = View.GONE
                hideLoading()

                // Release decoder session to ensure fresh keyframe on next connect
                videoDecoder?.stopDecoder()
                videoDecoder = null

                showStatusMessage("Session disconnected. Select USB or Wi-Fi to reconnect.", isError = false)
            },
            onVideoFrame = { nalu, ptsUs, isKeyframe ->
                videoDecoder?.decodeNalu(nalu, ptsUs, isKeyframe)
            },
            onAudioFrame = { pcm ->
                audioPlayer?.playAudio(pcm)
            },
            onBrightness = { brightness ->
                runOnUiThread {
                    applyHardwareBrightness(brightness)
                }
            }
        )
        this.connectionManager = connManager

        // Attach S-Pen Stylus & Multi-Touch Input Handler (Precision Pencil + Palm Rejection + Smooth Hover)
        val stylusHandler = StylusInputHandler(
            sendControlPacket = { controlPacket ->
                connManager.sendControlPacket(controlPacket)
            },
            onEdgeBrightnessChange = { delta ->
                runOnUiThread {
                    val current = window.attributes.screenBrightness.let { if (it < 0) 0.8f else it }
                    val newBright = (current + delta).coerceIn(0.01f, 1.0f)
                    applyHardwareBrightness(newBright)
                    connManager.sendBrightness(newBright)
                }
            }
        )
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

    private var brightnessHudRunnable: Runnable? = null
    private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())

    private fun applyHardwareBrightness(value: Float) {
        val clamped = value.coerceIn(0.01f, 1.0f)
        val lp = window.attributes
        lp.screenBrightness = clamped
        window.attributes = lp
        showBrightnessToast((clamped * 100).toInt())
    }

    private fun showBrightnessToast(percent: Int) {
        statusText.text = "☀️ AMOLED Brightness: $percent%"
        statusText.setTextColor(getColor(R.color.white))
        hudOverlay.visibility = View.VISIBLE
        hudOverlay.alpha = 1f

        brightnessHudRunnable?.let { mainHandler.removeCallbacks(it) }
        val r = Runnable {
            hudOverlay.animate().alpha(0f).setDuration(400).withEndAction {
                statusText.text = "120 FPS • Wire Active"
                statusText.setTextColor(getColor(R.color.status_green))
                hudOverlay.alpha = 1f
            }.start()
        }
        brightnessHudRunnable = r
        mainHandler.postDelayed(r, 1400)
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
