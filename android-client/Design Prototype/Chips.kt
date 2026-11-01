package com.displaymac.client.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.displaymac.client.ui.theme.AuroraBlue
import com.displaymac.client.ui.theme.AuroraBlueContainer
import com.displaymac.client.ui.theme.AuroraBlueDark
import com.displaymac.client.ui.theme.AuroraChip
import com.displaymac.client.ui.theme.AuroraInkTertiary
import com.displaymac.client.ui.theme.AuroraOutline
import com.displaymac.client.ui.theme.AuroraSuccess
import com.displaymac.client.ui.theme.AuroraSurface

/** "Recommended", "Wireless" tag at the top of a card. */
@Composable
fun TonalBadge(
    text: String,
    modifier: Modifier = Modifier,
    container: Color = AuroraBlueContainer,
    content: Color = AuroraBlueDark,
) {
    Surface(modifier, shape = RoundedCornerShape(10.dp), color = container) {
        Text(
            text = text,
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 3.dp),
            color = content,
            style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Medium),
        )
    }
}

/** Row of small grey spec chips (5 Gbps, 120 FPS ...). */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun SpecChips(items: List<String>, modifier: Modifier = Modifier) {
    FlowRow(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        items.forEach { label ->
            Surface(shape = RoundedCornerShape(10.dp), color = AuroraChip) {
                Text(
                    text = label,
                    modifier = Modifier.padding(horizontal = 9.dp, vertical = 2.dp),
                    color = AuroraInkTertiary,
                    style = MaterialTheme.typography.labelSmall,
                )
            }
        }
    }
}

@Composable
fun InlineSpinner() {
    CircularProgressIndicator(
        modifier = Modifier.size(16.dp),
        strokeWidth = 2.dp,
        color = AuroraBlue,
    )
}

/** Status line inside a card: spinner or icon + text. */
@Composable
fun StatusPill(
    text: String,
    modifier: Modifier = Modifier,
    leading: @Composable () -> Unit,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 34.dp)
            .background(AuroraSurface, RoundedCornerShape(12.dp))
            .padding(horizontal = 10.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        leading()
        Text(
            text = text,
            color = AuroraInkTertiary,
            style = MaterialTheme.typography.labelMedium,
        )
    }
}

@Composable
fun SuccessIcon(icon: ImageVector) {
    Icon(icon, contentDescription = null, tint = AuroraSuccess, modifier = Modifier.size(16.dp))
}

enum class PillStyle { Primary, Tonal, Outlined, Success }

/** Full-width pill button, 42 dp high, used at the bottom of each card. */
@Composable
fun PillButton(
    text: String,
    onClick: () -> Unit,
    style: PillStyle,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    icon: ImageVector? = null,
) {
    val m = modifier.fillMaxWidth().height(42.dp)
    val body: @Composable RowScope.() -> Unit = {
        if (icon != null) {
            Icon(icon, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
        }
        Text(text, style = MaterialTheme.typography.labelLarge)
    }
    when (style) {
        PillStyle.Primary -> Button(
            onClick = onClick, modifier = m, enabled = enabled, shape = CircleShape, content = body,
        )
        PillStyle.Tonal -> FilledTonalButton(
            onClick = onClick, modifier = m, enabled = enabled, shape = CircleShape,
            colors = ButtonDefaults.filledTonalButtonColors(
                containerColor = AuroraBlueContainer,
                contentColor = AuroraBlueDark,
            ),
            content = body,
        )
        PillStyle.Outlined -> OutlinedButton(
            onClick = onClick, modifier = m, enabled = enabled, shape = CircleShape,
            border = BorderStroke(1.dp, AuroraOutline),
            content = body,
        )
        PillStyle.Success -> Button(
            onClick = onClick, modifier = m, enabled = enabled, shape = CircleShape,
            colors = ButtonDefaults.buttonColors(containerColor = AuroraSuccess),
            content = body,
        )
    }
}
