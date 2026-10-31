package com.displaymac.client.network

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.util.Log
import com.displaymac.client.protocol.ProtocolConstants
import kotlinx.coroutines.*
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
    private val onDisconnected: () -> Unit,
    private val onVideoFrame: (nalu: ByteArray, ptsUs: Long, isKeyframe: Boolean) -> Unit
) {
    companion object {
        private const val TAG = "ConnectionManager"
    }

    private var controlSocket: Socket? = null
    private var videoSocket: Socket? = null
    private var controlOutputStream: DataOutputStream? = null

    private val managerScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var connectionJob: Job? = null

    private val _isConnected = AtomicBoolean(false)
    val isConnected: Boolean
        get() = _isConnected.get()

    private var nsdManager: NsdManager? = null
    private var discoveryListener: NsdManager.DiscoveryListener? = null

    /**
     * Start background Bonjour/mDNS discovery.
     * Only updates the UI with the discovered IP — DOES NOT auto-connect.
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
     * Connect to target host (127.0.0.1 for USB cable, or local Wi-Fi IP).
     */
    fun connectToHost(host: String, connectionMode: String, onError: (String) -> Unit) {
        if (_isConnected.get()) return

        connectionJob?.cancel()
        connectionJob = managerScope.launch {
            try {
                Log.i(TAG, "Connecting to Control Channel $host:${ProtocolConstants.CONTROL_PORT}...")
                val cSocket = Socket()
                cSocket.tcpNoDelay = true
                cSocket.soTimeout = 0 // Infinite read timeout during streaming
                cSocket.connect(InetSocketAddress(host, ProtocolConstants.CONTROL_PORT), 3500)
                controlSocket = cSocket
                controlOutputStream = DataOutputStream(cSocket.getOutputStream())

                Log.i(TAG, "Connecting to Video Channel $host:${ProtocolConstants.VIDEO_PORT}...")
                val vSocket = Socket()
                vSocket.tcpNoDelay = true
                vSocket.receiveBufferSize = 4 * 1024 * 1024 // 4MB buffer
                vSocket.soTimeout = 0
                vSocket.connect(InetSocketAddress(host, ProtocolConstants.VIDEO_PORT), 3500)
                videoSocket = vSocket

                _isConnected.set(true)
                withContext(Dispatchers.Main) {
                    onConnected(connectionMode)
                }

                // Send ClientHello Handshake (2960x1848 @ 120Hz)
                val helloPacket = ProtocolConstants.buildClientHello(
                    width = 2960,
                    height = 1848,
                    refreshRate = 120,
                    dpi = 280
                )
                sendControlPacket(helloPacket)

                // Start Streaming receiver loops
                launch { readVideoStream(vSocket) }
                launch { readControlStream(cSocket) }

            } catch (e: Exception) {
                Log.e(TAG, "Connection failed to $host", e)
                cleanupSockets()
                _isConnected.set(false)
                withContext(Dispatchers.Main) {
                    val msg = e.localizedMessage ?: "Connection timed out"
                    onError(msg)
                }
            }
        }
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
            Log.d(TAG, "Control stream terminated: ${e.message}")
            handleRemoteDisconnect()
        }
    }

    private fun readVideoStream(socket: Socket) {
        try {
            val dis = DataInputStream(socket.getInputStream())
            val headerBuffer = ByteArray(20)

            while (_isConnected.get() && !socket.isClosed) {
                dis.readFully(headerBuffer)
                val bb = ByteBuffer.wrap(headerBuffer).order(ByteOrder.BIG_ENDIAN)
                val magic = bb.short
                val frameType = bb.get()
                val codec = bb.get()
                val seqNum = bb.int
                val ptsNano = bb.long
                val payloadLength = bb.int

                val naluData = ByteArray(payloadLength)
                dis.readFully(naluData)

                val isKeyframe = (frameType == ProtocolConstants.FRAME_TYPE_KEYFRAME)
                val ptsUs = ptsNano / 1000L

                onVideoFrame(naluData, ptsUs, isKeyframe)
            }
        } catch (e: Exception) {
            Log.d(TAG, "Video stream terminated: ${e.message}")
            handleRemoteDisconnect()
        }
    }

    private fun handleRemoteDisconnect() {
        if (_isConnected.compareAndSet(true, false)) {
            Log.i(TAG, "Remote server disconnected or connection closed.")
            cleanupSockets()
            managerScope.launch(Dispatchers.Main) {
                onDisconnected()
            }
        }
    }

    /**
     * Clean manual disconnect requested by user.
     */
    fun disconnect() {
        Log.i(TAG, "User requested disconnect.")
        _isConnected.set(false)
        connectionJob?.cancel()
        cleanupSockets()
        managerScope.launch(Dispatchers.Main) {
            onDisconnected()
        }
    }

    private fun cleanupSockets() {
        try {
            controlSocket?.close()
        } catch (_: Exception) {}
        try {
            videoSocket?.close()
        } catch (_: Exception) {}
        controlSocket = null
        videoSocket = null
        controlOutputStream = null
    }

    fun shutdown() {
        disconnect()
        stopMdnsDiscovery()
        managerScope.cancel()
    }
}
