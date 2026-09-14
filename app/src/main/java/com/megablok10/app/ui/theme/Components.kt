package com.megablok10.app.ui.theme

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Двухслойная рамка со срезом: border не комбинируется с clip-path на одном
 * элементе, поэтому "рамка" — это внешний Box цвета borderColor, внутрь
 * которого с отступом borderWidth вложен внутренний Box цвета fillColor.
 * innerCut уменьшен на borderWidth, чтобы диагональ среза оставалась
 * параллельна внешней независимо от толщины рамки.
 */
@Composable
fun ChamferedPanel(
    modifier: Modifier = Modifier,
    borderColor: Color = MB10Colors.inkFaint,
    fillColor: Color = MB10Colors.bg1,
    cut: Dp = 10.dp,
    borderWidth: Dp = 1.dp,
    doubleCorner: Boolean = false,
    contentPadding: Dp = 12.dp,
    content: @Composable BoxScope.() -> Unit
) {
    val innerCut = cut - borderWidth
    val outerShape = if (doubleCorner) doubleChamferShape(cut) else chamferShape(cut)
    val innerShape = if (doubleCorner) doubleChamferShape(innerCut) else chamferShape(innerCut)
    Box(
        modifier = modifier
            .background(borderColor, outerShape)
            .padding(borderWidth)
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(fillColor, innerShape)
                .padding(contentPadding),
            content = content
        )
    }
}

@Composable
fun HexBullet(color: Color = MB10Colors.yellow, size: Dp = 8.dp) {
    Box(Modifier.size(size).background(color, hexShape()))
}

@Composable
fun DottedDivider(color: Color = MB10Colors.inkFaint, modifier: Modifier = Modifier) {
    Canvas(modifier.fillMaxWidth().height(1.dp)) {
        drawLine(
            color = color,
            start = Offset(0f, 0f),
            end = Offset(size.width, 0f),
            strokeWidth = 1.dp.toPx(),
            pathEffect = PathEffect.dashPathEffect(floatArrayOf(4f, 4f))
        )
    }
}

@Composable
fun FlagTab(text: String, accent: Color = MB10Colors.lime, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .background(accent, flagTabShape())
            .padding(start = 9.dp, end = 14.dp, top = 5.dp, bottom = 5.dp)
    ) {
        Text(text, color = Color.Black, fontFamily = JetBrainsMono, fontSize = 10.sp)
    }
}
