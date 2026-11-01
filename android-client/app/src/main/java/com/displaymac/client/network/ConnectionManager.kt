package com.displaymac.client.network

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.util.Log
import com.displaymac.client.protocol.ProtocolConstants
import kotlinx.coroutines.*
import java.io.BufferedInputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicBoolean

class ConnectionManager(
    private val context: Context,
    private val onConnected: (mode: String) -> Unit,
    private val onDisconnected: (wasUnexpected: Boolean) -> Unit,
    private val onSearchingStatus: (attempt: Int, mode: String) -> Unit,
    private val onVideoFrame: (nalu: ByteArray, ptsUs: Long, isKeyframe: Boolean) -> Unit,
    private val onAudioFrame: (pcmData: ByteArray) -> Unit,
    private val onSpeedUpdated: ((Float) -> Unit)? = null
) {
    companion object {
        private const val TAG = "ConnectionManager"
    }

    private var controlSocket: Socket? = null
    private var videoSocket: Socket? = null
    private var audioSocket: Socket? = null
    private var controlOutputStream: DataOutputStream? = null

    private val managerScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var probeJob: Job? = null

    private val _isConnected = AtomicBoolean(false)
    val isConnected: Boolean
        get() = _isConnected.get()

    @Volatile
    private var isAutoConnecting = false

    val isSearching: Boolean
        get() = isAutoConnecting && !_isConnected.get()

    private var targetHost: String = "127.0.0.1"
    private var targetMode: String = "USB-C Cable"

    private var nsdManager: NsdManager? = null
    private var discoveryListener: NsdManager.DiscoveryListener? = null

    /**
     * Start background Bonjour/mDNS discovery for Wi-Fi mode.
     */
    fun startMdnsDiscovery(onDiscovered: (ip: String) -> Unit) {
        nsdManager = context.getSystemService(Context.NSD_SERVICE) as? NsdManager ?: return
        stopMdnsDiscovery()

        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(regType: String) {
                Log.d(TAG, "mDNS Discovery started for $regType")
            }

            override fun onServiceFound(service: NsdServiceInfo) {
                if (service.serviceType.contains("displaymac")) {
                    nsdManager?.resolveService(service, object : NsdManager.ResolveListener {
                        override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                            Log.e(TAG, "mDNS Resolve failed: $errorCode")
                        }

                        override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                            val host = serviceInfo.host?.hostAddress ?: return
                            Log.i(TAG, "Discovered DisplayMac Host: $host")
                            managerScope.launch(Dispatchers.Main) {
                                onDiscovered(host)
                            }
                        }
                    })
                }
            }

            override fun onServiceLost(service: NsdServiceInfo) {}
            override fun onDiscoveryStopped(serviceType: String) {}
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {}
            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
        }

        try {
            this.discoveryListener = listener
            nsdManager?.discoverServices(
                ProtocolConstants.BONJOUR_SERVICE_TYPE,
                NsdManager.PROTOCOL_DNS_SD,
                listener
            )
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start mDNS discovery", e)
        }
    }

    fun stopMdnsDiscovery() {
        discoveryListener?.let {
            try {
                nsdManager?.stopServiceDiscovery(it)
            } catch (_: Exception) {}
            discoveryListener = null
        }
    }

    /**
     * Starts continuous background probe loop over USB-C (127.0.0.1).
     * Never gives up or shows dead errors; continuously probes every 1s until Mac connects!
     */
    fun startUsbAutoConnect() {
        startContinuousProbe("127.0.0.1", "USB-C Cable")
    }

    /**
     * Starts continuous background probe loop over Wi-Fi.
     */
    fun startWifiAutoConnect(ip: String) {
        startContinuousProbe(ip, "Wi-Fi ($ip)")
    }

    private fun startContinuousProbe(host: String, mode: String) {
        stopAutoConnect()

        isAutoConnecting = true
        targetHost = host
        targetMode = mode

        probeJob = managerScope.launch {
            var attempt = 0
            Log.i(TAG, "Starting continuous probe engine for $host ($mode)...")

            while (isAutoConnecting && !_isConnected.get() && isActive) {
                attempt++
                withContext(Dispatchers.Main) {
                    onSearchingStatus(attempt, mode)
                }

                try {
                    // 1. Probe Control Port (Port 7100) with quick 1.5s timeout
                    val cSocket = Socket()
                    cSocket.tcpNoDelay = true
                    cSocket.soTimeout = 0
                    cSocket.connect(InetSocketAddress(host, ProtocolConstants.CONTROL_PORT), 1500)
                    controlSocket = cSocket
                    controlOutputStream = DataOutputStream(cSocket.getOutputStream())

                    // 2. Probe Video Port (Port 7101) with quick 1.5s timeout
                    val vSocket = Socket()
                    vSocket.tcpNoDelay = true
                    vSocket.receiveBufferSize = 128 * 1024
                    vSocket.soTimeout = 0
                    vSocket.connect(InetSocketAddress(host, ProtocolConstants.VIDEO_PORT), 1500)
                    videoSocket = vSocket

                    // Connection Established!
                    _isConnected.set(true)
                    Log.i(TAG, "🎉 Connected to Mac host ($host) on attempt #$attempt!")

                    withContext(Dispatchers.Main) {
                        onConnected(mode)
                    }

                    // Send ClientHello Handshake (2960x1848 @ 120Hz)
                    val deviceName = getDeviceMarketingName()
                    val helloPacket = ProtocolConstants.buildClientHello(
                        width = 2960,
                        height = 1848,
                        refreshRate = 120,
                        dpi = 280,
                        deviceName = deviceName
                    )
                    sendControlPacket(helloPacket)

                    // Connect Dedicated Audio Channel (Port 7102) asynchronously
                    launch {
                        try {
                            val aSocket = Socket()
                            aSocket.tcpNoDelay = true
                            aSocket.receiveBufferSize = 512 * 1024
                            aSocket.soTimeout = 0
                            aSocket.connect(InetSocketAddress(host, ProtocolConstants.AUDIO_PORT), 2000)
                            audioSocket = aSocket
                            readAudioStream(aSocket)
                        } catch (_: Exception) {}
                    }

                    // Start active streaming loops and wait until session disconnects
                    val videoJob = launch { readVideoStream(vSocket) }
                    val controlJob = launch { readControlStream(cSocket) }

                    videoJob.join()
                    controlJob.join()

                } catch (e: Exception) {
                    // Socket connection refused or timed out (Mac booting or cable not plugged yet)
                    cleanupSockets()
                    _isConnected.set(false)
                }

                // If connection was lost or failed, pause 1s before next probe
                if (isAutoConnecting && !_isConnected.get() && isActive) {
                    delay(1000)
                }
            }
        }
    }

    /**
     * Stops the search loop and cleanly resets to idle dashboard.
     */
    fun stopAutoConnect() {
        val wasActive = isAutoConnecting || _isConnected.get()
        isAutoConnecting = false
        _isConnected.set(false)
        probeJob?.cancel()
        cleanupSockets()

        if (wasActive) {
            managerScope.launch(Dispatchers.Main) {
                onDisconnected(false)
            }
        }
    }

    fun disconnect() {
        stopAutoConnect()
    }

    fun sendControlPacket(packet: ByteArray) {
        managerScope.launch {
            try {
                controlOutputStream?.write(packet)
                controlOutputStream?.flush()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to send control packet", e)
            }
        }
    }

    fun requestKeyframe() {
        if (!_isConnected.get()) return
        Log.i(TAG, "Requesting immediate IDR keyframe from Mac...")
        val packet = ProtocolConstants.buildControlMessage(ProtocolConstants.MSG_REQUEST_KEYFRAME, ByteArray(0))
        sendControlPacket(packet)
    }

    private fun readControlStream(socket: Socket) {
        try {
            val dis = DataInputStream(socket.getInputStream())
            val headerBuffer = ByteArray(8)
            while (_isConnected.get() && !socket.isClosed) {
                dis.readFully(headerBuffer)
                val bb = ByteBuffer.wrap(headerBuffer).order(ByteOrder.BIG_ENDIAN)
                val magic = bb.short
                val version = bb.get()
                val msgType = bb.get()
                val length = bb.int

                val payload = ByteArray(length)
                if (length > 0) {
                    dis.readFully(payload)
                }

                if (msgType == ProtocolConstants.MSG_SERVER_CONFIG) {
                    Log.i(TAG, "Received ServerConfig confirmation from Mac!")
                }
            }
        } catch (e: Exception) {
            Log.d(TAG, "Control stream disconnected: ${e.message}")
            handleUnexpectedDisconnect()
        }
    }

    private fun readVideoStream(socket: Socket) {
        try {
            val bis = BufferedInputStream(socket.getInputStream(), 128 * 1024)
            val dis = DataInputStream(bis)
            val headerBuffer = ByteArray(20)

            var bytesWindow = 0L
            var lastSpeedCheck = System.currentTimeMillis()

            while (_isConnected.get() && !socket.isClosed) {
                dis.readFully(headerBuffer)
                val bb = ByteBuffer.wrap(headerBuffer).order(ByteOrder.BIG_ENDIAN)
                val magic = bb.short
                val frameType = bb.get()
                val codec = bb.get()
                val seqNum = bb.int
                val ptsNano = bb.long
                val payloadLength = bb.int

                val payloadData = ByteArray(payloadLength)
                dis.readFully(payloadData)

                // Track Real-time Data Read Speed (Mbps)
                bytesWindow += (20 + payloadLength)
                val now = System.currentTimeMillis()
                val elapsed = now - lastSpeedCheck
                if (elapsed >= 500) {
                    val mbps = (bytesWindow * 8f) / (elapsed * 1000f)
                    bytesWindow = 0L
                    lastSpeedCheck = now
                    onSpeedUpdated?.invoke(mbps)
                }

                if (frameType != ProtocolConstants.FRAME_TYPE_AUDIO) {
                    val isKeyframe = (frameType == ProtocolConstants.FRAME_TYPE_KEYFRAME)
                    val ptsUs = ptsNano / 1000L
                    onVideoFrame(payloadData, ptsUs, isKeyframe)
                }
            }
        } catch (e: Exception) {
            Log.d(TAG, "Video stream disconnected: ${e.message}")
            handleUnexpectedDisconnect()
        }
    }

    private fun readAudioStream(socket: Socket) {
        try {
            val dis = DataInputStream(BufferedInputStream(socket.getInputStream(), 16384))
            val headerBuffer = ByteArray(8)
            while (_isConnected.get() && !socket.isClosed) {
                dis.readFully(headerBuffer)
                val bb = ByteBuffer.wrap(headerBuffer).order(ByteOrder.BIG_ENDIAN)
                val magic = bb.short
                if (magic != ProtocolConstants.MAGIC) continue
                val type = bb.get()
                val reserved = bb.get()
                val length = bb.int
                if (length in 1..65536) {
                    val pcmData = ByteArray(length)
                    dis.readFully(pcmData)
                    onAudioFrame(pcmData)
                }
            }
        } catch (e: Exception) {
            Log.i(TAG, "Audio stream ended: ${e.message}")
        } finally {
            try { socket.close() } catch (_: Exception) {}
        }
    }

    private fun handleUnexpectedDisconnect() {
        if (_isConnected.compareAndSet(true, false)) {
            Log.i(TAG, "Remote session closed unexpectedly. Resetting sockets...")
            cleanupSockets()
            managerScope.launch(Dispatchers.Main) {
                onDisconnected(true)
            }
        }
    }

    private fun cleanupSockets() {
        try {
            controlSocket?.close()
        } catch (_: Exception) {}
        try {
            videoSocket?.close()
        } catch (_: Exception) {}
        try {
            audioSocket?.close()
        } catch (_: Exception) {}
        controlSocket = null
        videoSocket = null
        audioSocket = null
        controlOutputStream = null
    }

    private fun getDeviceMarketingName(): String {
        try {
            val name = android.provider.Settings.Global.getString(context.contentResolver, "device_name")
            if (!name.isNullOrBlank()) {
                return name
            }
        } catch (_: Exception) {}

        val manufacturer = android.os.Build.MANUFACTURER.replaceFirstChar { 
            if (it.isLowerCase()) it.titlecase(java.util.Locale.getDefault()) else it.toString() 
        }
        val model = android.os.Build.MODEL
        val friendlyModel = when {
            model.equals("SM-X920", ignoreCase = true) || model.equals("SM-X926B", ignoreCase = true) -> "Galaxy Tab S10 Ultra"
            model.equals("SM-X910", ignoreCase = true) || model.equals("SM-X916B", ignoreCase = true) -> "Galaxy Tab S9 Ultra"
            model.equals("SM-X820", ignoreCase = true) -> "Galaxy Tab S10+"
            model.equals("SM-X810", ignoreCase = true) -> "Galaxy Tab S9+"
            model.equals("SM-X710", ignoreCase = true) -> "Galaxy Tab S9"
            else -> model
        }

        return if (friendlyModel.startsWith(manufacturer, ignoreCase = true)) {
            friendlyModel
        } else {
            "$manufacturer $friendlyModel"
        }
    }

    fun shutdown() {
        stopAutoConnect()
        stopMdnsDiscovery()
        managerScope.cancel()
    }
}
