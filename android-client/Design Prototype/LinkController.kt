package com.displaymac.client.ui.connect

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.launch

enum class Transport { Usb, Wifi }

/** Things the connection layer tells the UI. */
sealed interface LinkEvent {
    data class UsbMacFound(val macName: String) : LinkEvent
    data object UsbLost : LinkEvent
    data class WifiMacFound(val macName: String, val host: String) : LinkEvent
    data object WifiLost : LinkEvent
    data class Connected(val transport: Transport, val refreshHz: Int) : LinkEvent
    data object Disconnected : LinkEvent
    data class Failed(val message: String) : LinkEvent
}

/**
 * The only thing the UI needs from your networking code.
 * Implement this on top of your existing `network/` package
 * (ADB tunnel probe, Bonjour discovery, socket connect) and pass it
 * to ConnectViewModel.
 */
interface LinkController {
    val events: Flow<LinkEvent>
    fun startUsbProbe()
    fun stopUsbProbe()
    fun startWifiDiscovery()
    fun connectUsb()
    fun connectWifi(host: String)
    fun disconnect()
    fun close()
}

/** Demo controller: finds a Mac after a few seconds so the UI can be tried without a Mac. */
class FakeLinkController : LinkController {
    private val bus = MutableSharedFlow<LinkEvent>(extraBufferCapacity = 16)
    override val events: Flow<LinkEvent> = bus.asSharedFlow()

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var usbJob: Job? = null

    override fun startUsbProbe() {
        usbJob?.cancel()
        usbJob = scope.launch {
            delay(3_200)
            bus.emit(LinkEvent.UsbMacFound("Mac mini M4"))
        }
    }

    override fun stopUsbProbe() {
        usbJob?.cancel()
    }

    override fun startWifiDiscovery() {
        scope.launch {
            delay(1_500)
            bus.emit(LinkEvent.WifiMacFound("Mac mini M4", "192.168.1.17"))
        }
    }

    override fun connectUsb() {
        scope.launch {
            delay(800)
            bus.emit(LinkEvent.Connected(Transport.Usb, refreshHz = 120))
        }
    }

    override fun connectWifi(host: String) {
        scope.launch {
            delay(1_200)
            bus.emit(LinkEvent.Connected(Transport.Wifi, refreshHz = 120))
        }
    }

    override fun disconnect() {
        scope.launch { bus.emit(LinkEvent.Disconnected) }
        startUsbProbe()
    }

    override fun close() {
        scope.cancel()
    }
}
