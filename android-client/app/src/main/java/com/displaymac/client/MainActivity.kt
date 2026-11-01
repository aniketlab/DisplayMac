package com.displaymac.client

import android.animation.ObjectAnimator
import android.animation.PropertyValuesHolder
import android.animation.ValueAnimator
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.Display
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
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
import com.displaymac.client.input.StylusInputHandler
import com.displaymac.client.network.ConnectionManager
import com.displaymac.client.decoder.LowLatencyVideoDecoder
import com.displaymac.client.display.DisplayModeManager
import kotlin.math.roundToInt

class MainActivity : AppCompatActivity() {

    // Streaming Layer Views
    private lateinit var videoSurface: SurfaceView
    private lateinit var dashboardLayout: ViewGroup
    private lateinit var hudOverlay: View
    private lateinit var statusText: TextView
    private lateinit var fpsText: TextView
    private lateinit var speedText: TextView
    private lateinit var btnDisconnect: AppCompatButton

    // Dashboard Hero & Status Views
    private lateinit var radarIcon: View
    private lateinit var dashStatusTitle: TextView
    private lateinit var dashStatusSub: TextView
    private lateinit var panelSpecsBadge: TextView

    // USB Connection Card Views
    private lateinit var btnConnectUsb: AppCompatButton
    private lateinit var searchProgress: ProgressBar
    private lateinit var ivUsbStatusIcon: ImageView
    private lateinit var tvStatusMessage: TextView

    // Wi-Fi Connection Card Views
    private lateinit var btnConnectWifi: AppCompatButton
    private lateinit var tvDiscoveredMacTitle: TextView
    private lateinit var tvWifiDiscoveryStatus: TextView
    private lateinit var ivWifiFoundCheck: ImageView
    private lateinit var manualIpInput: EditText
    private lateinit var btnToggleManualIp: TextView

    // Core Managers & Engines
    private lateinit var displayModeManager: DisplayModeManager
    private var videoDecoder: LowLatencyVideoDecoder? = null
    private var audioPlayer: LowLatencyAudioPlayer? = null
    private var connectionManager: ConnectionManager? = null
    private var pulseAnimator: ObjectAnimator? = null
    private var surfaceHolderRef: SurfaceHolder? = null

    private var discoveredBonjourIp: String? = null
    private var isManualIpVisible: Boolean = false

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

        // Read dynamic tablet specifications & update top pill
        detectAndShowDeviceInfo()

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
                startUsbSearch()
            }
        }, 500)
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
        panelSpecsBadge = findViewById(R.id.panelSpecsBadge)

        btnConnectUsb = findViewById(R.id.btnConnectUsb)
        searchProgress = findViewById(R.id.searchProgress)
        ivUsbStatusIcon = findViewById(R.id.ivUsbStatusIcon)
        tvStatusMessage = findViewById(R.id.tvStatusMessage)

        btnConnectWifi = findViewById(R.id.btnConnectWifi)
        tvDiscoveredMacTitle = findViewById(R.id.tvDiscoveredMacTitle)
        tvWifiDiscoveryStatus = findViewById(R.id.tvWifiDiscoveryStatus)
        ivWifiFoundCheck = findViewById(R.id.ivWifiFoundCheck)
        manualIpInput = findViewById(R.id.manualIpInput)
        btnToggleManualIp = findViewById(R.id.btnToggleManualIp)
    }

    /**
     * Reads the tablet's friendly name, physical resolution, and native refresh rate.
     */
    private fun detectAndShowDeviceInfo() {
        try {
            var friendlyName: String? = null

            // 1. Check System and Global settings
            try {
                friendlyName = Settings.Global.getString(contentResolver, "device_name")
                    ?.takeIf { it.isNotBlank() && !it.equals("unknown", ignoreCase = true) }
            } catch (_: Exception) {}

            if (friendlyName == null) {
                try {
                    friendlyName = Settings.Secure.getString(contentResolver, "bluetooth_name")
                        ?.takeIf { it.isNotBlank() }
                } catch (_: Exception) {}
            }

            if (friendlyName == null) {
                try {
                    friendlyName = Settings.System.getString(contentResolver, "device_name")
                        ?.takeIf { it.isNotBlank() }
                } catch (_: Exception) {}
            }

            // 2. Map known raw model codes to friendly commercial names
            val model = Build.MODEL.trim()
            val mappedName = when {
                model.equals("PGFM10", ignoreCase = true) -> "OPPO Find X6"
                model.equals("PGEM10", ignoreCase = true) -> "OPPO Find X6 Pro"
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
                model.startsWith("SM-X21", ignoreCase = true) || model.startsWith("SM-X20", ignoreCase = true) -> "Galaxy Tab A9+"
                model.contains("Pixel Tablet", ignoreCase = true) -> "Pixel Tablet"
                model.startsWith("OPD", ignoreCase = true) -> "OnePlus Pad"
                else -> null
            }

            val finalName = when {
                !friendlyName.isNullOrBlank() && !friendlyName.matches(Regex("^[A-Z0-9_-]{4,10}$")) -> friendlyName
                mappedName != null -> mappedName
                !friendlyName.isNullOrBlank() -> "${Build.MANUFACTURER.replaceFirstChar { it.uppercase() }} $friendlyName"
                else -> {
                    val mfg = Build.MANUFACTURER.replaceFirstChar { it.uppercase() }
                    if (model.startsWith(mfg, ignoreCase = true)) model else "$mfg $model"
                }
            }

            val display = getSystemService(DisplayManager::class.java).getDisplay(Display.DEFAULT_DISPLAY)
            val mode = display.mode
            val w = maxOf(mode.physicalWidth, mode.physicalHeight)
            val h = minOf(mode.physicalWidth, mode.physicalHeight)
            val hz = display.refreshRate.roundToInt()

            panelSpecsBadge.text = "$finalName · $w × $h · $hz Hz"
            dashStatusSub.text = "Pick how to connect your $finalName"
        } catch (_: Exception) {
            panelSpecsBadge.text = "Galaxy Tab S10 Ultra · 2960 × 1848 · 120 Hz"
        }
    }

    private fun setupBackNavigation() {
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (connectionManager?.isConnected == true) {
                    // If streaming, back button immediately disconnects and returns to dashboard
                    connectionManager?.disconnect()
                } else if (connectionManager?.isSearching == true) {
                    connectionManager?.stopAutoConnect()
                    hideSearchingUI()
                    showStatusMessage("Auto-search paused.", isError = false)
                } else {
                    // On dashboard, minimize app smoothly without killing process
                    moveTaskToBack(true)
                }
            }
        })
    }

    private fun setupActionButtons() {
        // 1. USB-C Cable Connection Button (Toggles search or stop search)
        btnConnectUsb.setOnClickListener {
            if (connectionManager?.isSearching == true) {
                connectionManager?.stopAutoConnect()
                hideSearchingUI()
                showStatusMessage("Search paused. Tap button to search again.", isError = false)
            } else {
                startUsbSearch()
            }
        }

        // 2. Wi-Fi Wireless Connection Button
        btnConnectWifi.setOnClickListener {
            val ip = if (isManualIpVisible) {
                manualIpInput.text.toString().trim()
            } else {
                discoveredBonjourIp ?: manualIpInput.text.toString().trim()
            }

            if (ip.isEmpty()) {
                showStatusMessage("⚠️ Please enter Mac mini IP address", isError = true)
                manualIpInput.visibility = View.VISIBLE
                isManualIpVisible = true
                btnToggleManualIp.text = "Use found Mac"
                return@setOnClickListener
            }
            startWifiSearch(ip)
        }

        // 3. Manual IP Toggle Button
        btnToggleManualIp.setOnClickListener {
            isManualIpVisible = !isManualIpVisible
            manualIpInput.visibility = if (isManualIpVisible) View.VISIBLE else View.GONE
            btnToggleManualIp.text = if (isManualIpVisible) "Use the found Mac" else "Enter IP manually"
        }

        // 4. Floating HUD Disconnect Button
        btnDisconnect.setOnClickListener {
            connectionManager?.disconnect()
        }
    }

    private fun startUsbSearch() {
        val holder = surfaceHolderRef ?: videoSurface.holder
        if (holder.surface.isValid) {
            ensureDecoderActive(holder)
        }
        showSearchingUI("Looking for your Mac over USB-C...")
        connectionManager?.startUsbAutoConnect()
    }

    private fun startWifiSearch(ip: String) {
        val holder = surfaceHolderRef ?: videoSurface.holder
        if (holder.surface.isValid) {
            ensureDecoderActive(holder)
        }
        showSearchingUI("Connecting to Mac at $ip over Wi-Fi...")
        connectionManager?.startWifiAutoConnect(ip)
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

    private fun showSearchingUI(message: String) {
        searchProgress.visibility = View.VISIBLE
        ivUsbStatusIcon.visibility = View.GONE
        tvStatusMessage.visibility = View.VISIBLE
        tvStatusMessage.text = message
        tvStatusMessage.setTextColor(getColor(R.color.aurora_ink_tertiary))

        btnConnectUsb.text = "Stop searching"
        btnConnectUsb.setBackgroundResource(R.drawable.btn_aurora_outlined)
        btnConnectUsb.setTextColor(getColor(R.color.aurora_blue))
        btnConnectUsb.isEnabled = true
        btnConnectWifi.isEnabled = false
    }

    private fun hideSearchingUI() {
        searchProgress.visibility = View.GONE
        ivUsbStatusIcon.visibility = View.VISIBLE
        ivUsbStatusIcon.setImageResource(R.drawable.ic_pause)

        btnConnectUsb.text = "Connect with USB-C"
        btnConnectUsb.setBackgroundResource(R.drawable.btn_aurora_primary)
        btnConnectUsb.setTextColor(getColor(R.color.white))
        btnConnectUsb.isEnabled = true
        btnConnectWifi.isEnabled = true
    }

    private fun showStatusMessage(message: String, isError: Boolean) {
        tvStatusMessage.visibility = View.VISIBLE
        tvStatusMessage.text = message
        tvStatusMessage.setTextColor(if (isError) getColor(R.color.aurora_error) else getColor(R.color.aurora_ink_tertiary))
    }

    private fun setupSurface() {
        videoSurface.holder.addCallback(object : SurfaceHolder.Callback {
            override fun surfaceCreated(holder: SurfaceHolder) {
                surfaceHolderRef = holder
                if (connectionManager?.isConnected == true) {
                    android.util.Log.i("MainActivity", "Resuming video pipeline after surface recreation...")
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
                videoDecoder?.stopDecoder()
                videoDecoder = null
            }
        })
    }

    private fun initConnectionManager() {
        val connManager = ConnectionManager(
            context = this,
            onConnected = { mode ->
                hideSearchingUI()

                // Update USB card status to connected
                searchProgress.visibility = View.GONE
                ivUsbStatusIcon.visibility = View.VISIBLE
                ivUsbStatusIcon.setImageResource(R.drawable.ic_check_circle)
                tvStatusMessage.text = "Streaming at 120 Hz"

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
                statusText.setTextColor(getColor(R.color.aurora_success))
                fpsText.text = "120 FPS"
            },
            onDisconnected = { wasUnexpected ->
                audioPlayer?.stop()

                dashboardLayout.bringToFront()
                dashboardLayout.alpha = 1f
                dashboardLayout.visibility = View.VISIBLE
                hudOverlay.visibility = View.GONE

                videoDecoder?.stopDecoder()
                videoDecoder = null

                if (wasUnexpected) {
                    showSearchingUI("Waiting for Mac to reconnect...")
                } else {
                    hideSearchingUI()
                    showStatusMessage("Session ended. Ready to connect.", isError = false)
                }
            },
            onSearchingStatus = { attempt, mode ->
                tvStatusMessage.visibility = View.VISIBLE
                tvStatusMessage.text = "Looking for your Mac over USB-C... (#$attempt)"
                tvStatusMessage.setTextColor(getColor(R.color.aurora_ink_tertiary))
                searchProgress.visibility = View.VISIBLE
                ivUsbStatusIcon.visibility = View.GONE
                btnConnectUsb.text = "Stop searching"
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
            this.discoveredBonjourIp = discoveredIp
            if (manualIpInput.text.isNullOrEmpty()) {
                manualIpInput.setText(discoveredIp)
            }
            tvWifiDiscoveryStatus.text = "$discoveredIp · found via Bonjour"
            ivWifiFoundCheck.visibility = View.VISIBLE
        }
    }

    private fun startRadarPulse() {
        pulseAnimator = ObjectAnimator.ofPropertyValuesHolder(
            radarIcon,
            PropertyValuesHolder.ofFloat(View.SCALE_X, 1.0f, 1.06f),
            PropertyValuesHolder.ofFloat(View.SCALE_Y, 1.0f, 1.06f)
        ).apply {
            duration = 1600
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

    override fun onConfigurationChanged(newConfig: android.content.res.Configuration) {
        super.onConfigurationChanged(newConfig)
        hideSystemUI()
        detectAndShowDeviceInfo()

        if (connectionManager?.isConnected == true) {
            // While streaming: keep socket & video pipeline alive without interruption
            val holder = surfaceHolderRef ?: videoSurface.holder
            if (holder.surface.isValid) {
                ensureDecoderActive(holder)
                connectionManager?.requestKeyframe()
            }
        } else {
            // On dashboard: recreate to seamlessly switch between compact (1-col) and wide (2-col) layout
            recreate()
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
