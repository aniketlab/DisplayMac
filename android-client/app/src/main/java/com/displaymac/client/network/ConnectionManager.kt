package com.displaymac.client.network

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.util.Log
import com.displaymac.client.protocol.ProtocolConstants
import kotlinx.coroutines.*
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.nio.ByteBuffer
import java.nio.ByteOrder

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
    
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var isRunning = false
    private var nsdManager: NsdManager? = null

    fun startAutoDiscoveryAndConnect() {
        if (isRunning) return
        isRunning = true

        scope.launch {
            // Step 1: Check USB connection (USB Tethering default gateway or ADB reverse 127.0.0.1)
            val usbCandidate = checkUsbCandidates()
            if (usbCandidate != null) {
                Log.i(TAG, "⚡ USB Link candidate discovered: $usbCandidate")
                connectToHost(usbCandidate, "Direct USB-C (5 Gbps)")
                return@launch
            }

            // Step 2: Fallback to Wi-Fi mDNS / Bonjour
            Log.i(TAG, "Discovering Mac mini via Bonjour mDNS...")
            discoverViaMdns()
        }
    }

    private fun checkUsbCandidates(): String? {
        val candidates = listOf("192.168.42.129", "192.168.42.1", "127.0.0.1")
        for (ip in candidates) {
            try {
                Socket().use { socket ->
                    socket.connect(InetSocketAddress(ip, ProtocolConstants.CONTROL_PORT), 250)
                    return ip
                }
            } catch (_: Exception) {
                // Not reachable
            }
        }
        return null
    }

    private fun discoverViaMdns() {
        nsdManager = context.getSystemService(Context.NSD_SERVICE) as NsdManager
        val discoveryListener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(regType: String) {
                Log.d(TAG, "mDNS Discovery started")
            }

            override fun onServiceFound(service: NsdServiceInfo) {
                if (service.serviceType.contains("displaymac")) {
                    nsdManager?.resolveService(service, object : NsdManager.ResolveListener {
                        override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                            Log.e(TAG, "Resolve failed: $errorCode")
                        }

                        override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                            val host = serviceInfo.host.hostAddress ?: return
                            Log.i(TAG, "Discovered DisplayMac Host via Wi-Fi: $host")
                            scope.launch {
                                connectToHost(host, "Wi-Fi 6E/7")
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
            nsdManager?.discoverServices(ProtocolConstants.BONJOUR_SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, discoveryListener)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start mDNS discovery", e)
        }
    }

    fun connectToHost(host: String, connectionMode: String) {
        scope.launch {
            try {
                Log.i(TAG, "Connecting to Control Channel $host:${ProtocolConstants.CONTROL_PORT}...")
                val cSocket = Socket()
                cSocket.tcpNoDelay = true
                cSocket.connect(InetSocketAddress(host, ProtocolConstants.CONTROL_PORT), 3000)
                controlSocket = cSocket
                controlOutputStream = DataOutputStream(cSocket.getOutputStream())

                Log.i(TAG, "Connecting to Video Channel $host:${ProtocolConstants.VIDEO_PORT}...")
                val vSocket = Socket()
                vSocket.tcpNoDelay = true
                vSocket.receiveBufferSize = 4 * 1024 * 1024 // 4MB buffer for 120Hz peak stream
                vSocket.connect(InetSocketAddress(host, ProtocolConstants.VIDEO_PORT), 3000)
                videoSocket = vSocket

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

                // Start Video Receiver Loop
                launch { readVideoStream(vSocket) }
                // Start Control Receiver Loop
                launch { readControlStream(cSocket) }

            } catch (e: Exception) {
                Log.e(TAG, "Connection failed to $host", e)
                withContext(Dispatchers.Main) {
                    onDisconnected()
                }
            }
        }
    }

    fun sendControlPacket(packet: ByteArray) {
        scope.launch {
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
            while (isRunning && !socket.isClosed) {
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
            Log.d(TAG, "Control stream closed: ${e.message}")
        }
    }

    private fun readVideoStream(socket: Socket) {
        try {
            val dis = DataInputStream(socket.getInputStream())
            val headerBuffer = ByteArray(20)

            while (isRunning && !socket.isClosed) {
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
            Log.d(TAG, "Video stream disconnected: ${e.message}")
            scope.launch(Dispatchers.Main) {
                onDisconnected()
            }
        }
    }

    fun stop() {
        isRunning = false
        try {
            controlSocket?.close()
            videoSocket?.close()
        } catch (_: Exception) {}
        scope.cancel()
    }
}
