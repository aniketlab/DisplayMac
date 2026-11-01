package com.displaymac.client.ui.connect

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

enum class LinkStatus { Searching, Found, Paused, Connecting, Connected }

data class ConnectUiState(
    val macName: String? = null,
    val usb: LinkStatus = LinkStatus.Searching,
    val wifiHost: String? = null,
    val wifiMacName: String? = null,
    val wifiConnecting: Boolean = false,
    val manualEntry: Boolean = false,
    val manualHost: String = "",
    val connectedVia: Transport? = null,
    val refreshHz: Int = 120,
    val error: String? = null,
)

class ConnectViewModel(
    // Swap FakeLinkController for your real implementation.
    private val controller: LinkController = FakeLinkController(),
) : ViewModel() {

    private val _state = MutableStateFlow(ConnectUiState())
    val state: StateFlow<ConnectUiState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            controller.events.collect { event -> _state.update { it.reduce(event) } }
        }
        controller.startUsbProbe()
        controller.startWifiDiscovery()
    }

    private fun ConnectUiState.reduce(e: LinkEvent): ConnectUiState = when (e) {
        is LinkEvent.UsbMacFound -> copy(
            macName = e.macName,
            usb = if (usb == LinkStatus.Searching) LinkStatus.Found else usb,
        )
        LinkEvent.UsbLost -> copy(
            usb = if (connectedVia == null && usb != LinkStatus.Paused) LinkStatus.Searching else usb,
        )
        is LinkEvent.WifiMacFound -> copy(
            wifiMacName = e.macName,
            wifiHost = e.host,
            macName = macName ?: e.macName,
        )
        LinkEvent.WifiLost -> copy(wifiMacName = null, wifiHost = null)
        is LinkEvent.Connected -> copy(
            connectedVia = e.transport,
            usb = if (e.transport == Transport.Usb) LinkStatus.Connected else usb,
            wifiConnecting = false,
            refreshHz = e.refreshHz,
            error = null,
        )
        LinkEvent.Disconnected -> copy(
            connectedVia = null,
            usb = LinkStatus.Searching,
            wifiConnecting = false,
        )
        is LinkEvent.Failed -> copy(
            error = e.message,
            usb = if (usb == LinkStatus.Connecting) LinkStatus.Found else usb,
            wifiConnecting = false,
        )
    }

    fun onUsbButton() {
        when (_state.value.usb) {
            LinkStatus.Searching -> {
                controller.stopUsbProbe()
                _state.update { it.copy(usb = LinkStatus.Paused) }
            }
            LinkStatus.Paused -> {
                controller.startUsbProbe()
                _state.update { it.copy(usb = LinkStatus.Searching) }
            }
            LinkStatus.Found -> {
                _state.update { it.copy(usb = LinkStatus.Connecting, error = null) }
                controller.connectUsb()
            }
            LinkStatus.Connecting -> Unit
            LinkStatus.Connected -> controller.disconnect()
        }
    }

    fun onWifiButton() {
        val s = _state.value
        when {
            s.connectedVia == Transport.Wifi -> controller.disconnect()
            s.wifiConnecting -> Unit
            else -> {
                val host = if (s.manualEntry) s.manualHost.trim() else s.wifiHost.orEmpty()
                if (host.isBlank()) {
                    _state.update { it.copy(error = "Enter your Mac's IP address") }
                    return
                }
                _state.update { it.copy(wifiConnecting = true, error = null) }
                controller.connectWifi(host)
            }
        }
    }

    fun toggleManualEntry() = _state.update { it.copy(manualEntry = !it.manualEntry, error = null) }

    fun onManualHostChange(value: String) = _state.update { it.copy(manualHost = value, error = null) }

    override fun onCleared() {
        controller.close()
    }
}
