package com.displaymac.client.ui.connect

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.DesktopMac
import androidx.compose.material.icons.outlined.Devices
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.Pause
import androidx.compose.material.icons.outlined.Speed
import androidx.compose.material.icons.outlined.TabletAndroid
import androidx.compose.material.icons.outlined.Usb
import androidx.compose.material.icons.outlined.Wifi
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.displaymac.client.ui.components.AuroraBackdrop
import com.displaymac.client.ui.components.InlineSpinner
import com.displaymac.client.ui.components.LogoMark
import com.displaymac.client.ui.components.PillButton
import com.displaymac.client.ui.components.PillStyle
import com.displaymac.client.ui.components.SpecChips
import com.displaymac.client.ui.components.StatusPill
import com.displaymac.client.ui.components.SuccessIcon
import com.displaymac.client.ui.components.TonalBadge
import com.displaymac.client.ui.theme.AuroraBlue
import com.displaymac.client.ui.theme.AuroraBlueContainer
import com.displaymac.client.ui.theme.AuroraBorder
import com.displaymac.client.ui.theme.AuroraCard
import com.displaymac.client.ui.theme.AuroraError
import com.displaymac.client.ui.theme.AuroraInk
import com.displaymac.client.ui.theme.AuroraInkSecondary
import com.displaymac.client.ui.theme.AuroraInkTertiary
import com.displaymac.client.ui.theme.AuroraSkyContainer
import com.displaymac.client.ui.theme.AuroraSkyDark
import com.displaymac.client.ui.theme.AuroraSuccess
import com.displaymac.client.ui.theme.AuroraSurface
import com.displaymac.client.ui.theme.DisplayMacTheme

private val ContentMaxWidth = 640.dp
private val CardShape = RoundedCornerShape(20.dp)

/** Entry point: wires the ViewModel to the UI. */
@Composable
fun ConnectScreen(
    device: DeviceInfo,
    viewModel: ConnectViewModel = viewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    ConnectContent(
        state = state,
        device = device,
        onUsb = viewModel::onUsbButton,
        onWifi = viewModel::onWifiButton,
        onToggleManual = viewModel::toggleManualEntry,
        onManualHost = viewModel::onManualHostChange,
    )
}

/** Stateless UI, easy to preview. */
@Composable
fun ConnectContent(
    state: ConnectUiState,
    device: DeviceInfo,
    onUsb: () -> Unit,
    onWifi: () -> Unit,
    onToggleManual: () -> Unit,
    onManualHost: (String) -> Unit,
) {
    AuroraBackdrop {
        Column(Modifier.fillMaxSize().systemBarsPadding()) {
            TopBar(device)

            BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
                val wide = maxWidth >= 600.dp
                val viewportHeight = maxHeight

                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .verticalScroll(rememberScrollState())
                        .heightIn(min = viewportHeight)
                        .padding(horizontal = 20.dp, vertical = 12.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    Hero(state, device)
                    Spacer(Modifier.height(16.dp))

                    val width = Modifier.widthIn(max = ContentMaxWidth).fillMaxWidth()

                    if (wide) {
                        Row(
                            modifier = width.height(IntrinsicSize.Max),
                            horizontalArrangement = Arrangement.spacedBy(14.dp),
                        ) {
                            UsbCard(state, onUsb, Modifier.weight(1f).fillMaxHeight())
                            WifiCard(state, onWifi, onToggleManual, onManualHost, Modifier.weight(1f).fillMaxHeight())
                        }
                    } else {
                        Column(width, verticalArrangement = Arrangement.spacedBy(14.dp)) {
                            UsbCard(state, onUsb, Modifier.fillMaxWidth())
                            WifiCard(state, onWifi, onToggleManual, onManualHost, Modifier.fillMaxWidth())
                        }
                    }

                    Spacer(Modifier.height(14.dp))
                    FeatureStrip(wide = wide, modifier = width)
                }
            }
        }
    }
}

// ---------------------------------------------------------------- top bar / hero

@Composable
private fun TopBar(device: DeviceInfo) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            LogoMark()
            Text("DisplayMac", style = MaterialTheme.typography.titleMedium, color = AuroraInk)
        }
        Surface(
            modifier = Modifier.padding(start = 12.dp),
            shape = CircleShape,
            color = AuroraCard,
            border = BorderStroke(0.5.dp, AuroraBorder),
        ) {
            Row(
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 5.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Icon(
                    Icons.Outlined.TabletAndroid,
                    contentDescription = null,
                    modifier = Modifier.size(16.dp),
                    tint = AuroraInkTertiary,
                )
                Text(
                    text = device.pillLabel,
                    color = AuroraInkTertiary,
                    style = MaterialTheme.typography.labelMedium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

@Composable
private fun Hero(state: ConnectUiState, device: DeviceInfo) {
    val mac = state.macName ?: "your Mac"
    val (subtitle, ok) = when {
        state.connectedVia == Transport.Usb -> "Connected over USB-C · ${state.refreshHz} Hz" to true
        state.connectedVia == Transport.Wifi -> "Connected over Wi-Fi · ${state.refreshHz} Hz" to true
        state.wifiConnecting -> "Connecting over Wi-Fi…" to false
        else -> "Pick how to connect your ${device.name}" to false
    }

    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Surface(
            modifier = Modifier.size(48.dp),
            shape = RoundedCornerShape(16.dp),
            color = AuroraCard,
            border = BorderStroke(0.5.dp, AuroraBorder),
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(
                    Icons.Outlined.DesktopMac,
                    contentDescription = null,
                    modifier = Modifier.size(26.dp),
                    tint = AuroraInk,
                )
            }
        }
        Spacer(Modifier.height(10.dp))
        Text(
            text = "Connect to $mac",
            style = MaterialTheme.typography.headlineSmall,
            color = AuroraInk,
            textAlign = TextAlign.Center,
        )
        Text(
            text = subtitle,
            style = MaterialTheme.typography.bodyMedium,
            color = if (ok) AuroraSuccess else AuroraInkSecondary,
            textAlign = TextAlign.Center,
        )
        state.error?.let {
            Text(
                text = it,
                modifier = Modifier.padding(top = 4.dp),
                style = MaterialTheme.typography.labelMedium,
                color = AuroraError,
                textAlign = TextAlign.Center,
            )
        }
    }
}

// ---------------------------------------------------------------- cards

@Composable
private fun LinkCard(
    modifier: Modifier,
    badge: @Composable () -> Unit,
    icon: ImageVector,
    title: String,
    chips: List<String>,
    body: @Composable ColumnScope.() -> Unit,
    action: @Composable () -> Unit,
) {
    Surface(
        modifier = modifier.heightIn(min = 196.dp),
        shape = CardShape,
        color = AuroraCard,
        border = BorderStroke(0.5.dp, AuroraBorder),
    ) {
        Column(
            modifier = Modifier.fillMaxHeight().padding(16.dp),
            verticalArrangement = Arrangement.SpaceBetween,
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                badge()
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Icon(icon, contentDescription = null, tint = AuroraBlue)
                    Text(title, style = MaterialTheme.typography.titleMedium, color = AuroraInk)
                }
                SpecChips(chips)
                body()
            }
            Spacer(Modifier.height(12.dp))
            action()
        }
    }
}

@Composable
private fun UsbCard(state: ConnectUiState, onClick: () -> Unit, modifier: Modifier) {
    val usb = state.usb
    LinkCard(
        modifier = modifier,
        badge = { TonalBadge("Recommended") },
        icon = Icons.Outlined.Usb,
        title = "USB-C cable",
        chips = listOf("5 Gbps", "< 1 ms", "85 Mbps", "120 FPS"),
        body = {
            when (usb) {
                LinkStatus.Searching ->
                    StatusPill("Looking for your Mac over USB-C…") { InlineSpinner() }
                LinkStatus.Found ->
                    StatusPill("${state.macName ?: "Mac"} found") { SuccessIcon(Icons.Outlined.CheckCircle) }
                LinkStatus.Paused ->
                    StatusPill("Search paused") {
                        Icon(
                            Icons.Outlined.Pause,
                            contentDescription = null,
                            modifier = Modifier.size(16.dp),
                            tint = AuroraInkTertiary,
                        )
                    }
                LinkStatus.Connecting ->
                    StatusPill("Connecting…") { InlineSpinner() }
                LinkStatus.Connected ->
                    StatusPill("Streaming at ${state.refreshHz} Hz") { SuccessIcon(Icons.Outlined.CheckCircle) }
            }
        },
        action = {
            val (label, style) = when (usb) {
                LinkStatus.Searching -> "Stop searching" to PillStyle.Outlined
                LinkStatus.Found -> "Connect with USB-C" to PillStyle.Primary
                LinkStatus.Paused -> "Search again" to PillStyle.Primary
                LinkStatus.Connecting -> "Connecting…" to PillStyle.Primary
                LinkStatus.Connected -> "Disconnect" to PillStyle.Success
            }
            PillButton(
                text = label,
                onClick = onClick,
                style = style,
                enabled = state.connectedVia != Transport.Wifi && usb != LinkStatus.Connecting,
            )
        },
    )
}

@Composable
private fun WifiCard(
    state: ConnectUiState,
    onClick: () -> Unit,
    onToggleManual: () -> Unit,
    onManualHost: (String) -> Unit,
    modifier: Modifier,
) {
    val connected = state.connectedVia == Transport.Wifi
    val hasTarget = if (state.manualEntry) state.manualHost.isNotBlank() else state.wifiHost != null

    LinkCard(
        modifier = modifier,
        badge = { TonalBadge("Wireless", container = AuroraSkyContainer, content = AuroraSkyDark) },
        icon = Icons.Outlined.Wifi,
        title = "Wi-Fi",
        chips = listOf("Wi-Fi 6E / 7", "Adaptive bitrate", "120 FPS"),
        body = {
            if (state.wifiHost != null) {
                DiscoveredMacRow(name = state.wifiMacName ?: "Mac", host = state.wifiHost)
            } else if (!state.manualEntry) {
                StatusPill("Looking for Macs nearby…") { InlineSpinner() }
            }
            if (state.manualEntry) {
                OutlinedTextField(
                    value = state.manualHost,
                    onValueChange = onManualHost,
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    shape = RoundedCornerShape(12.dp),
                    textStyle = MaterialTheme.typography.bodyMedium,
                    placeholder = { Text("Mac IP, e.g. 192.168.1.17") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                )
            }
            TextButton(
                onClick = onToggleManual,
                modifier = Modifier.height(32.dp),
                contentPadding = PaddingValues(0.dp),
            ) {
                Text(
                    text = if (state.manualEntry) "Use the found Mac" else "Enter IP manually",
                    style = MaterialTheme.typography.labelMedium,
                )
            }
        },
        action = {
            PillButton(
                text = when {
                    connected -> "Disconnect"
                    state.wifiConnecting -> "Connecting…"
                    else -> "Connect over Wi-Fi"
                },
                onClick = onClick,
                style = if (connected) PillStyle.Success else PillStyle.Tonal,
                enabled = connected || (state.connectedVia == null && !state.wifiConnecting && hasTarget),
                icon = if (connected) null else Icons.Outlined.Wifi,
            )
        },
    )
}

@Composable
private fun DiscoveredMacRow(name: String, host: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(AuroraSurface, RoundedCornerShape(12.dp))
            .padding(horizontal = 10.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(
            Icons.Outlined.DesktopMac,
            contentDescription = null,
            modifier = Modifier.size(18.dp),
            tint = AuroraInk,
        )
        Column(Modifier.weight(1f)) {
            Text(
                text = name,
                style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Medium),
                color = AuroraInk,
            )
            Text(
                text = "$host · found via Bonjour",
                style = MaterialTheme.typography.labelSmall,
                color = AuroraInkSecondary,
            )
        }
        Icon(
            Icons.Outlined.CheckCircle,
            contentDescription = null,
            modifier = Modifier.size(18.dp),
            tint = AuroraBlue,
        )
    }
}

// ---------------------------------------------------------------- feature strip

private data class Feature(val icon: ImageVector, val title: String, val subtitle: String)

private val features = listOf(
    Feature(Icons.Outlined.Edit, "S Pen ready", "Pressure, tilt and hover"),
    Feature(Icons.Outlined.Speed, "Native 120 Hz", "Full resolution, no bars"),
    Feature(Icons.Outlined.Bolt, "HEVC decoding", "Hardware, low latency"),
    Feature(Icons.Outlined.Devices, "Main or extra", "Use as your Mac's display"),
)

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun FeatureStrip(wide: Boolean, modifier: Modifier) {
    Surface(
        modifier = modifier,
        shape = CardShape,
        color = AuroraCard,
        border = BorderStroke(0.5.dp, AuroraBorder),
    ) {
        FlowRow(
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 10.dp),
            maxItemsInEachRow = if (wide) 4 else 2,
        ) {
            features.forEach { f ->
                Row(
                    modifier = Modifier.weight(1f).padding(horizontal = 8.dp, vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Box(
                        modifier = Modifier.size(30.dp).background(AuroraBlueContainer, CircleShape),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(f.icon, contentDescription = null, modifier = Modifier.size(16.dp), tint = AuroraBlue)
                    }
                    Column {
                        Text(
                            text = f.title,
                            style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Medium),
                            color = AuroraInk,
                        )
                        Text(
                            text = f.subtitle,
                            style = MaterialTheme.typography.labelSmall,
                            color = AuroraInkSecondary,
                            maxLines = 2,
                        )
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------- previews

private val previewDevice = DeviceInfo("Galaxy Tab S10 Ultra", "2960 × 1848 · 120 Hz")
private val previewState = ConnectUiState(
    macName = "Mac mini M4",
    usb = LinkStatus.Found,
    wifiHost = "192.168.1.17",
    wifiMacName = "Mac mini M4",
)

@Preview(name = "Tablet", widthDp = 1100, heightDp = 700)
@Composable
private fun ConnectTabletPreview() {
    DisplayMacTheme {
        ConnectContent(previewState, previewDevice, {}, {}, {}, {})
    }
}

@Preview(name = "Phone", widthDp = 400, heightDp = 860)
@Composable
private fun ConnectPhonePreview() {
    DisplayMacTheme {
        ConnectContent(previewState.copy(usb = LinkStatus.Searching), previewDevice, {}, {}, {}, {})
    }
}
