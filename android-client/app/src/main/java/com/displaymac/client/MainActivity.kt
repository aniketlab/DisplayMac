package com.displaymac.client

import android.animation.ObjectAnimator
import android.animation.PropertyValuesHolder
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.res.Configuration
import android.os.Bundle
import android.util.Log
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
import com.displaymac.client.decoder.LowLatencyVideoDecoder
import com.displaymac.client.display.DeviceDisplayProfile
import com.displaymac.client.display.DeviceProfile
import com.displaymac.client.display.DisplayModeManager
import com.displaymac.client.input.StylusInputHandler
import com.displaymac.client.network.ConnectionManager
import java.util.Locale

class MainActivity : AppCompatActivity() {

    companion object {
        private const val TAG = "MainActivity"
    }

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
    private lateinit var chipUsbFps: TextView
    private lateinit var chipWifiFps: TextView
    private lateinit var tvFeatureStylusTitle: TextView
    private lateinit var tvFeatureRefreshTitle: TextView

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
    private var viewUsbManualIpSpacer: View? = null

    // Core Managers & Engines
    private lateinit var displayModeManager: DisplayModeManager
    private lateinit var deviceProfile: DeviceDisplayProfile
    private var videoDecoder: LowLatencyVideoDecoder? = null
    private var audioPlayer: LowLatencyAudioPlayer? = null
    private var connectionManager: ConnectionManager? = null
    private var pulseAnimator: ObjectAnimator? = null
    private var surfaceHolderRef: SurfaceHolder? = null

    private var discoveredBonjourIp: String? = null
    private var isManualIpVisible: Boolean = false
    private var isWifiSearching: Boolean = false
    private var isWideLayout: Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        isWideLayout = resources.configuration.screenWidthDp >= 600

        audioPlayer = LowLatencyAudioPlayer()
        setContentView(R.layout.activity_main)

        hideSystemUI()
        bindViews()

        displayModeManager = DisplayModeManager(this)
        displayModeManager.lockToHighestRefreshRate()

        updateDeviceProfileUI()
        startRadarPulse()
        setupBackNavigation()
        setupActionButtons()
        initConnectionManager()
        setupSurface()
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
        chipUsbFps = findViewById(R.id.chipUsbFps)
        chipWifiFps = findViewById(R.id.chipWifiFps)
        tvFeatureStylusTitle = findViewById(R.id.tvFeatureStylusTitle)
        tvFeatureRefreshTitle = findViewById(R.id.tvFeatureRefreshTitle)

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
        viewUsbManualIpSpacer = findViewById(R.id.viewUsbManualIpSpacer)
    }

    private fun updateDeviceProfileUI() {
        deviceProfile = DeviceProfile.inspect(this)
        panelSpecsBadge.text = getString(
            R.string.device_specs_format,
            deviceProfile.marketingName,
            deviceProfile.widthPx,
            deviceProfile.heightPx,
            deviceProfile.refreshRateHz
        )
        dashStatusSub.text = getString(R.string.hero_subtitle_format, deviceProfile.marketingName)

        val fpsChipLabel = getString(R.string.chip_fps_format, deviceProfile.refreshRateHz)
        chipUsbFps.text = fpsChipLabel
        chipWifiFps.text = fpsChipLabel
        tvFeatureRefreshTitle.text = getString(R.string.feature_refresh_format, deviceProfile.refreshRateHz)
        tvFeatureStylusTitle.text = getString(
            if (deviceProfile.isSamsung) R.string.feature_spen_title else R.string.feature_stylus_title
        )
        fpsText.text = fpsChipLabel
    }

    private fun setupBackNavigation() {
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (connectionManager?.isConnected == true) {
                    connectionManager?.disconnect()
                } else if (connectionManager?.isSearching == true) {
                    connectionManager?.stopAutoConnect()
                    hideSearchingUI()
                    showStatusMessage(getString(R.string.usb_status_paused), isError = false)
                } else {
                    moveTaskToBack(true)
                }
            }
        })
    }

    private fun setupActionButtons() {
        btnConnectUsb.setOnClickListener {
            if (connectionManager?.isSearching == true && !isWifiSearching) {
                connectionManager?.stopAutoConnect()
                hideSearchingUI()
                showStatusMessage(getString(R.string.usb_status_ready), isError = false)
            } else {
                startUsbSearch()
            }
        }

        btnConnectWifi.setOnClickListener {
            if (isWifiSearching) {
                connectionManager?.stopAutoConnect()
                hideWifiSearchingUI()
                return@setOnClickListener
            }

            val ip = if (isManualIpVisible) {
                manualIpInput.text.toString().trim()
            } else {
                discoveredBonjourIp ?: manualIpInput.text.toString().trim()
            }

            if (ip.isEmpty()) {
                manualIpInput.visibility = View.VISIBLE
                isManualIpVisible = true
                viewUsbManualIpSpacer?.visibility = View.VISIBLE
                btnToggleManualIp.text = getString(R.string.btn_use_found_mac)
                manualIpInput.requestFocus()
                tvWifiDiscoveryStatus.text = getString(R.string.wifi_error_enter_ip)
                tvWifiDiscoveryStatus.setTextColor(getColor(R.color.aurora_error))
                return@setOnClickListener
            }
            startWifiSearch(ip)
        }

        btnToggleManualIp.setOnClickListener {
            isManualIpVisible = !isManualIpVisible
            manualIpInput.visibility = if (isManualIpVisible) View.VISIBLE else View.GONE
            viewUsbManualIpSpacer?.visibility = if (isManualIpVisible) View.VISIBLE else View.GONE
            btnToggleManualIp.text = getString(
                if (isManualIpVisible) R.string.btn_use_found_mac else R.string.btn_enter_ip_manually
            )
        }

        btnDisconnect.setOnClickListener {
            connectionManager?.disconnect()
        }
    }

    private fun startUsbSearch() {
        val holder = surfaceHolderRef ?: videoSurface.holder
        if (holder.surface.isValid) {
            ensureDecoderActive(holder)
        }
        showSearchingUI(getString(R.string.usb_status_searching))
        connectionManager?.startUsbAutoConnect(deviceProfile)
    }

    private fun startWifiSearch(ip: String) {
        val holder = surfaceHolderRef ?: videoSurface.holder
        if (holder.surface.isValid) {
            ensureDecoderActive(holder)
        }
        showWifiSearchingUI(ip)
        connectionManager?.startWifiAutoConnect(ip, deviceProfile)
    }

    private fun ensureDecoderActive(holder: SurfaceHolder) {
        if (videoDecoder == null) {
            val decoder = LowLatencyVideoDecoder(holder.surface) { liveFps ->
                runOnUiThread {
                    fpsText.text = getString(R.string.chip_fps_format, liveFps.toInt())
                }
            }
            decoder.initDecoder(
                width = deviceProfile.widthPx,
                height = deviceProfile.heightPx,
                operatingFps = deviceProfile.refreshRateHz
            )
            this.videoDecoder = decoder
        }
    }

    private fun showSearchingUI(message: String) {
        searchProgress.visibility = View.VISIBLE
        ivUsbStatusIcon.visibility = View.GONE
        tvStatusMessage.visibility = View.VISIBLE
        tvStatusMessage.text = message
        tvStatusMessage.setTextColor(getColor(R.color.aurora_ink_tertiary))

        btnConnectUsb.text = getString(R.string.btn_stop_searching)
        btnConnectUsb.setBackgroundResource(R.drawable.btn_aurora_outlined)
        btnConnectUsb.setTextColor(getColor(R.color.aurora_blue))
        btnConnectUsb.isEnabled = true
        btnConnectWifi.isEnabled = false
    }

    private fun hideSearchingUI() {
        searchProgress.visibility = View.GONE
        ivUsbStatusIcon.visibility = View.VISIBLE
        ivUsbStatusIcon.setImageResource(R.drawable.ic_usb)

        btnConnectUsb.text = getString(R.string.btn_connect_usb)
        btnConnectUsb.setBackgroundResource(R.drawable.btn_aurora_primary)
        btnConnectUsb.setTextColor(getColor(R.color.white))
        btnConnectUsb.isEnabled = true
        if (!isWifiSearching) {
            btnConnectWifi.isEnabled = true
        }
    }

    private fun showWifiSearchingUI(ip: String) {
        isWifiSearching = true
        tvWifiDiscoveryStatus.text = getString(R.string.wifi_status_connecting, ip)
        tvWifiDiscoveryStatus.setTextColor(getColor(R.color.aurora_blue))

        btnConnectWifi.text = getString(R.string.btn_stop_searching)
        btnConnectWifi.setBackgroundResource(R.drawable.btn_aurora_outlined)
        btnConnectWifi.setTextColor(getColor(R.color.aurora_blue))
        btnConnectWifi.isEnabled = true
        btnConnectUsb.isEnabled = false
    }

    private fun hideWifiSearchingUI() {
        isWifiSearching = false
        val displayIp = discoveredBonjourIp
        if (displayIp != null) {
            tvWifiDiscoveryStatus.text = getString(R.string.wifi_status_found_bonjour, displayIp)
            tvWifiDiscoveryStatus.setTextColor(getColor(R.color.aurora_ink_secondary))
            ivWifiFoundCheck.visibility = View.VISIBLE
        } else {
            tvWifiDiscoveryStatus.text = getString(R.string.wifi_status_searching_bonjour)
            tvWifiDiscoveryStatus.setTextColor(getColor(R.color.aurora_ink_secondary))
            ivWifiFoundCheck.visibility = View.GONE
        }

        btnConnectWifi.text = getString(R.string.btn_connect_wifi)
        btnConnectWifi.setBackgroundResource(R.drawable.btn_aurora_tonal)
        btnConnectWifi.setTextColor(getColor(R.color.aurora_blue_dark))
        btnConnectWifi.isEnabled = true
        btnConnectUsb.isEnabled = true
    }

    private fun showStatusMessage(message: String, isError: Boolean) {
        tvStatusMessage.visibility = View.VISIBLE
        tvStatusMessage.text = message
        tvStatusMessage.setTextColor(
            if (isError) getColor(R.color.aurora_error) else getColor(R.color.aurora_ink_tertiary)
        )
    }

    private fun setupSurface() {
        videoSurface.holder.addCallback(object : SurfaceHolder.Callback {
            override fun surfaceCreated(holder: SurfaceHolder) {
                surfaceHolderRef = holder
                if (connectionManager?.isConnected == true) {
                    Log.i(TAG, "Resuming video pipeline after surface recreation")
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
                hideWifiSearchingUI()

                if (mode.contains("Wi-Fi")) {
                    tvWifiDiscoveryStatus.text =
                        getString(R.string.wifi_status_streaming_hz, deviceProfile.refreshRateHz)
                    ivWifiFoundCheck.visibility = View.VISIBLE
                } else {
                    searchProgress.visibility = View.GONE
                    ivUsbStatusIcon.visibility = View.VISIBLE
                    ivUsbStatusIcon.setImageResource(R.drawable.ic_check_circle)
                    tvStatusMessage.text =
                        getString(R.string.usb_status_streaming_hz, deviceProfile.refreshRateHz)
                }

                val holder = surfaceHolderRef ?: videoSurface.holder
                if (holder.surface.isValid) {
                    ensureDecoderActive(holder)
                }

                audioPlayer?.start()
                connectionManager?.requestKeyframe()

                dashboardLayout.animate()
                    .alpha(0f)
                    .setDuration(250)
                    .withEndAction { dashboardLayout.visibility = View.GONE }
                    .start()

                hudOverlay.visibility = View.VISIBLE
                hudOverlay.alpha = 0f
                hudOverlay.animate().alpha(1f).setDuration(250).start()

                statusText.text = getString(R.string.hud_connected_format, mode)
                statusText.setTextColor(getColor(R.color.aurora_success))
                fpsText.text = getString(R.string.chip_fps_format, deviceProfile.refreshRateHz)
            },
            onDisconnected = { wasUnexpected ->
                audioPlayer?.stop()

                dashboardLayout.bringToFront()
                dashboardLayout.alpha = 1f
                dashboardLayout.visibility = View.VISIBLE
                hudOverlay.visibility = View.GONE

                videoDecoder?.stopDecoder()
                videoDecoder = null

                hideSearchingUI()
                hideWifiSearchingUI()

                if (wasUnexpected) {
                    showStatusMessage(getString(R.string.usb_status_disconnected_unexpected), isError = true)
                } else {
                    showStatusMessage(getString(R.string.usb_status_ready), isError = false)
                }
            },
            onSearchingStatus = { attempt, mode ->
                if (mode.contains("Wi-Fi")) {
                    tvWifiDiscoveryStatus.text = getString(R.string.wifi_status_connecting_attempt, attempt)
                    tvWifiDiscoveryStatus.setTextColor(getColor(R.color.aurora_blue))
                    btnConnectWifi.text = getString(R.string.btn_stop_searching)
                } else {
                    tvStatusMessage.visibility = View.VISIBLE
                    tvStatusMessage.text = getString(R.string.usb_status_searching_attempt, attempt)
                    tvStatusMessage.setTextColor(getColor(R.color.aurora_ink_tertiary))
                    searchProgress.visibility = View.VISIBLE
                    ivUsbStatusIcon.visibility = View.GONE
                    btnConnectUsb.text = getString(R.string.btn_stop_searching)
                }
            },
            onVideoFrame = { nalu, ptsUs, isKeyframe ->
                videoDecoder?.decodeNalu(nalu, ptsUs, isKeyframe)
            },
            onAudioFrame = { pcm ->
                audioPlayer?.playAudio(pcm)
            },
            onSpeedUpdated = { mbps ->
                runOnUiThread {
                    speedText.text = String.format(Locale.US, "%.1f Mbps", mbps)
                }
            }
        )
        this.connectionManager = connManager

        attachInputListeners(connManager)

        connManager.startMdnsDiscovery { discovered ->
            this.discoveredBonjourIp = discovered.hostAddress
            if (manualIpInput.text.isNullOrEmpty()) {
                manualIpInput.setText(discovered.hostAddress)
            }
            tvDiscoveredMacTitle.text = discovered.displayName
            dashStatusTitle.text = getString(R.string.hero_title_format, discovered.displayName)
            tvWifiDiscoveryStatus.text = getString(R.string.wifi_status_found_bonjour, discovered.hostAddress)
            ivWifiFoundCheck.visibility = View.VISIBLE
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun attachInputListeners(connManager: ConnectionManager) {
        val stylusHandler = StylusInputHandler { controlPacket ->
            connManager.sendControlPacket(controlPacket)
        }
        videoSurface.setOnTouchListener(stylusHandler)
        videoSurface.setOnHoverListener(stylusHandler)
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

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        hideSystemUI()
        updateDeviceProfileUI()

        val nowWide = newConfig.screenWidthDp >= 600
        if (connectionManager?.isConnected == true) {
            val holder = surfaceHolderRef ?: videoSurface.holder
            if (holder.surface.isValid) {
                ensureDecoderActive(holder)
                connectionManager?.requestKeyframe()
            }
        } else if (nowWide != isWideLayout && connectionManager?.isSearching != true) {
            isWideLayout = nowWide
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
