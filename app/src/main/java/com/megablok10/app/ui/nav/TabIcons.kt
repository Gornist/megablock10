package com.megablok10.app.ui.nav

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * Иконки таб-бара — порт тех же path-данных, что в HTML-макете (viewBox
 * 0..24), просто отмасштабированных под фактический размер Canvas.
 */

@Composable
private fun IconCanvas(size: Dp, draw: androidx.compose.ui.graphics.drawscope.DrawScope.(scale: Float) -> Unit) {
    Canvas(Modifier.size(size)) {
        val scale = this.size.width / 24f
        draw(scale)
    }
}

private fun androidx.compose.ui.graphics.drawscope.DrawScope.strokePath(points: List<Offset>, tint: Color, scale: Float, close: Boolean = false) {
    val path = Path().apply {
        points.forEachIndexed { i, p ->
            val scaled = Offset(p.x * scale, p.y * scale)
            if (i == 0) moveTo(scaled.x, scaled.y) else lineTo(scaled.x, scaled.y)
        }
        if (close) close()
    }
    drawPath(path, tint, style = Stroke(width = 1.5f * scale, cap = StrokeCap.Round))
}

@Composable
fun ChatTabIcon(tint: Color, size: Dp = 17.dp) {
    IconCanvas(size) { scale ->
        strokePath(
            listOf(
                Offset(4f, 5f), Offset(20f, 5f), Offset(20f, 16f),
                Offset(8f, 16f), Offset(4f, 20f), Offset(4f, 5f)
            ),
            tint, scale, close = true
        )
    }
}

@Composable
fun HackTabIcon(tint: Color, size: Dp = 17.dp) {
    IconCanvas(size) { scale ->
        strokePath(listOf(Offset(4f, 4f), Offset(20f, 4f), Offset(20f, 20f), Offset(4f, 20f)), tint, scale, close = true)
        strokePath(listOf(Offset(8f, 9f), Offset(11f, 12f), Offset(8f, 15f)), tint, scale)
        strokePath(listOf(Offset(13f, 15f), Offset(16f, 15f)), tint, scale)
    }
}

/** Классическая трубка, тот же path-паттерн, что у остальных иконок бара (viewBox 0..24). */
@Composable
fun CallsTabIcon(tint: Color, size: Dp = 17.dp) {
    IconCanvas(size) { scale ->
        strokePath(
            listOf(
                Offset(6f, 4f), Offset(10f, 4f), Offset(11.5f, 8f), Offset(9f, 10f),
                Offset(12f, 15f), Offset(15f, 17f), Offset(17f, 13.5f), Offset(21f, 15f),
                Offset(21f, 19f), Offset(18f, 21f), Offset(11f, 17f), Offset(4f, 9f), Offset(6f, 4f)
            ),
            tint, scale, close = true
        )
    }
}

/** Карта/кошелёк с полосой — та же line-art логика, что у остальных иконок бара, ни одна не смешивает векторный рисунок с текстовым глифом. */
@Composable
fun WalletTabIcon(tint: Color, size: Dp = 17.dp) {
    IconCanvas(size) { scale ->
        strokePath(listOf(Offset(4f, 7f), Offset(20f, 7f), Offset(20f, 18f), Offset(4f, 18f)), tint, scale, close = true)
        strokePath(listOf(Offset(4f, 11f), Offset(20f, 11f)), tint, scale)
        strokePath(listOf(Offset(15f, 14.5f), Offset(17.5f, 14.5f)), tint, scale)
    }
}
