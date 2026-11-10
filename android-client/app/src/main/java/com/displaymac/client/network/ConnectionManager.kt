package com.displaymac.client.network

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.util.Log
import com.displaymac.client.display.DeviceDisplayProfile
import com.displaymac.client.display.DeviceProfile
import com.displaymac.client.protocol.ProtocolConstants
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.BufferedInputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.IOException
import java.net.InetSocketAddress
import java.net.Socket
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicBoolean

data class DiscoveredHost(
    val hostAddress: String,
    val displayName: String
)

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
        private const val CONNECT_TIMEOUT_MS = 1500
        private const val AUDIO_CONNECT_TIMEOUT_MS = 2000
        private const val HEARTBEAT_INTERVAL_MS = 4000L
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
    private var targetMode: String = "USB-C"

    private var nsdManager: NsdManager? = null
    private var discoveryListener: NsdManager.DiscoveryListener? = null

    /**
     * Starts background Bonjour/mDNS discovery for Wi-Fi mode.
     */
    @Suppress("DEPRECATION")
    fun startMdnsDiscovery(onDiscovered: (DiscoveredHost) -> Unit) {
        nsdManager = context.getSystemService(Context.NSD_SERVICE) as? NsdManager ?: return
        stopMdnsDiscovery()

        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(regType: String) {
                Log.d(TAG, "mDNS discovery started for $regType")
            }

            override fun onServiceFound(service: NsdServiceInfo) {
                if (!service.serviceType.contains("displaymac")) return

                nsdManager?.resolveService(service, object : NsdManager.ResolveListener {
                    override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                        Log.w(TAG, "mDNS resolve failed: error=$errorCode")
                    }

                    override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                        val host = serviceInfo.host?.hostAddress ?: return
                        val rawName = serviceInfo.serviceName?.trim().orEmpty()
                        val displayName = rawName.ifEmpty { host }
                        Log.i(TAG, "Discovered DisplayMac host '$displayName' at $host")
                        managerScope.launch(Dispatchers.Main) {
                            onDiscovered(DiscoveredHost(hostAddress = host, displayName = displayName))
                        }
                    }
                })
            }

            override fun onServiceLost(service: NsdServiceInfo) {}
            override fun onDiscoveryStopped(serviceType: String) {}
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                Log.w(TAG, "mDNS start discovery failed: error=$errorCode")
            }

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
     * Starts continuous background probe loop over USB-C (ADB reverse on 127.0.0.1).
     */
    fun startUsbAutoConnect(profile: DeviceDisplayProfile = DeviceProfile.inspect(context)) {
        startContinuousProbe("127.0.0.1", "USB-C", profile)
    }

    /**
     * Starts continuous background probe loop over Wi-Fi.
     */
    fun startWifiAutoConnect(ip: String, profile: DeviceDisplayProfile = DeviceProfile.inspect(context)) {
        startContinuousProbe(ip, "Wi-Fi ($ip)", profile)
    }

    private fun startContinuousProbe(host: String, mode: String, profile: DeviceDisplayProfile) {
        stopAutoConnect()

        isAutoConnecting = true
        targetHost = host
        targetMode = mode

        probeJob = managerScope.launch {
            var attempt = 0
            Log.i(TAG, "Starting probe engine for $host ($mode) [${profile.widthPx}x${profile.heightPx} @ ${profile.refreshRateHz}Hz]")

            while (isAutoConnecting && !_isConnected.get() && isActive) {
                attempt++
                withContext(Dispatchers.Main) {
                    onSearchingStatus(attempt, mode)
                }

                try {
                    val cSocket = Socket().apply {
                        tcpNoDelay = true
                        soTimeout = 0
                        connect(InetSocketAddress(host, ProtocolConstants.CONTROL_PORT), CONNECT_TIMEOUT_MS)
                    }
                    controlSocket = cSocket
                    controlOutputStream = DataOutputStream(cSocket.getOutputStream())

                    val vSocket = Socket().apply {
                        tcpNoDelay = true
                        receiveBufferSize = 128 * 1024
                        soTimeout = 0
                        connect(InetSocketAddress(host, ProtocolConstants.VIDEO_PORT), CONNECT_TIMEOUT_MS)
                    }
                    videoSocket = vSocket

                    _isConnected.set(true)
                    Log.i(TAG, "Connected to DisplayMac host $host ($mode) on attempt #$attempt")

                    withContext(Dispatchers.Main) {
                        onConnected(mode)
                    }

                    val helloPacket = ProtocolConstants.buildClientHello(
                        width = profile.widthPx,
                        height = profile.heightPx,
                        refreshRate = profile.refreshRateHz,
                        dpi = profile.densityDpi,
                        deviceName = profile.marketingName
                    )
                    sendControlPacket(helloPacket)

                    // Connect dedicated audio channel asynchronously
                    launch {
                        try {
                            val aSocket = Socket().apply {
                                tcpNoDelay = true
                                receiveBufferSize = 512 * 1024
                                soTimeout = 0
                                connect(InetSocketAddress(host, ProtocolConstants.AUDIO_PORT), AUDIO_CONNECT_TIMEOUT_MS)
                            }
                            audioSocket = aSocket
                            readAudioStream(aSocket)
                        } catch (_: Exception) {
                            // Audio channel is optional; video session continues if unavailable.
                        }
                    }

                    // Periodic keepalive ping on control socket
                    val heartbeatJob = launch {
                        while (_isConnected.get() && !cSocket.isClosed && isActive) {
                            delay(HEARTBEAT_INTERVAL_MS)
                            if (_isConnected.get()) {
                                sendControlPacket(
                                    ProtocolConstants.buildControlMessage(ProtocolConstants.MSG_PING, ByteArray(0))
                                )
                            }
                        }
                    }

                    val videoJob = launch { readVideoStream(vSocket) }
                    val controlJob = launch { readControlStream(cSocket) }

                    videoJob.join()
                    controlJob.join()
                    heartbeatJob.cancel()
                } catch (_: Exception) {
                    cleanupSockets()
                    _isConnected.set(false)
                }

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
                synchronized(this@ConnectionManager) {
                    controlOutputStream?.write(packet)
                    controlOutputStream?.flush()
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to send control packet: ${e.message}")
            }
        }
    }

    fun requestKeyframe() {
        if (!_isConnected.get()) return
        Log.i(TAG, "Requesting immediate IDR keyframe from host")
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

                if (magic != ProtocolConstants.MAGIC || version != ProtocolConstants.VERSION) {
                    throw IOException("Invalid control header (magic=$magic version=$version)")
                }
                if (length < 0 || length > ProtocolConstants.MAX_CONTROL_PAYLOAD_BYTES) {
                    throw IOException("Control payload out of bounds: $length bytes")
                }

                val payload = if (length > 0) {
                    ByteArray(length).also { dis.readFully(it) }
                } else {
                    ByteArray(0)
                }

                if (msgType == ProtocolConstants.MSG_SERVER_CONFIG) {
                    Log.i(TAG, "Received ServerConfig acknowledgement (${payload.size} bytes)")
                }
            }
        } catch (e: Exception) {
            Log.d(TAG, "Control stream ended: ${e.message}")
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
                bb.get() // codec
                bb.int // sequence number
                val ptsNano = bb.long
                val payloadLength = bb.int

                if (magic != ProtocolConstants.MAGIC) {
                    throw IOException("Invalid video frame magic: $magic")
                }
                if (payloadLength <= 0 || payloadLength > ProtocolConstants.MAX_VIDEO_FRAME_BYTES) {
                    throw IOException("Video payload length out of bounds: $payloadLength bytes")
                }

                val payloadData = ByteArray(payloadLength)
                dis.readFully(payloadData)

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
            Log.d(TAG, "Video stream ended: ${e.message}")
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
                if (magic != ProtocolConstants.MAGIC) {
                    throw IOException("Invalid audio frame magic: $magic")
                }
                bb.get() // frame type
                bb.get() // reserved
                val length = bb.int
                if (length <= 0 || length > ProtocolConstants.MAX_AUDIO_FRAME_BYTES) {
                    throw IOException("Audio payload length out of bounds: $length bytes")
                }
                val pcmData = ByteArray(length)
                dis.readFully(pcmData)
                onAudioFrame(pcmData)
            }
        } catch (e: Exception) {
            Log.i(TAG, "Audio stream ended: ${e.message}")
        } finally {
            try { socket.close() } catch (_: Exception) {}
        }
    }

    private fun handleUnexpectedDisconnect() {
        if (_isConnected.compareAndSet(true, false)) {
            Log.i(TAG, "Remote session closed unexpectedly; resetting sockets")
            cleanupSockets()
            managerScope.launch(Dispatchers.Main) {
                onDisconnected(true)
            }
        }
    }

    private fun cleanupSockets() {
        try { controlSocket?.close() } catch (_: Exception) {}
        try { videoSocket?.close() } catch (_: Exception) {}
        try { audioSocket?.close() } catch (_: Exception) {}
        controlSocket = null
        videoSocket = null
        audioSocket = null
        controlOutputStream = null
    }

    fun shutdown() {
        stopMdnsDiscovery()
        stopAutoConnect()
        managerScope.cancel()
    }
}
