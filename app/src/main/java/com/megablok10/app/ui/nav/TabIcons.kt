package com.megablok10.app.ui.nav

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.megablok10.app.ui.theme.JetBrainsMono

/**
 * Иконки таб-бара — порт тех же path-данных, что в HTML-макете (viewBox
 * 0..24), просто отмасштабированных под фактический размер Canvas.
 */

@Composable
private fun IconCanvas(tint: Color, size: Dp, draw: androidx.compose.ui.graphics.drawscope.DrawScope.(scale: Float) -> Unit) {
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
    IconCanvas(tint, size) { scale ->
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
    IconCanvas(tint, size) { scale ->
        strokePath(listOf(Offset(4f, 4f), Offset(20f, 4f), Offset(20f, 20f), Offset(4f, 20f)), tint, scale, close = true)
        strokePath(listOf(Offset(8f, 9f), Offset(11f, 12f), Offset(8f, 15f)), tint, scale)
        strokePath(listOf(Offset(13f, 15f), Offset(16f, 15f)), tint, scale)
    }
}

/** Классическая трубка, тот же path-паттерн, что у остальных иконок бара (viewBox 0..24). */
@Composable
fun CallsTabIcon(tint: Color, size: Dp = 17.dp) {
    IconCanvas(tint, size) { scale ->
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

@Composable
fun WalletTabIcon(tint: Color, size: Dp = 17.dp) {
    Box(Modifier.size(size), contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(size)) {
            val scale = this.size.width / 24f
            drawCircle(tint, radius = 9f * scale, center = Offset(12f * scale, 12f * scale), style = Stroke(width = 1.5f * scale))
        }
        Text("€$", color = tint, fontFamily = JetBrainsMono, fontSize = 8.sp)
    }
}

@Composable
fun ShardsTabIcon(tint: Color, size: Dp = 17.dp) {
    IconCanvas(tint, size) { scale ->
        strokePath(listOf(Offset(4f, 4f), Offset(11f, 4f), Offset(11f, 11f), Offset(4f, 11f)), tint, scale, close = true)
        strokePath(listOf(Offset(13f, 4f), Offset(20f, 4f), Offset(20f, 11f), Offset(13f, 11f)), tint, scale, close = true)
        strokePath(listOf(Offset(4f, 13f), Offset(11f, 13f), Offset(11f, 20f), Offset(4f, 20f)), tint, scale, close = true)
        strokePath(listOf(Offset(14f, 14f), Offset(20f, 14f)), tint, scale)
        strokePath(listOf(Offset(17f, 14f), Offset(17f, 20f)), tint, scale)
        strokePath(listOf(Offset(14f, 17f), Offset(17f, 17f)), tint, scale)
    }
}

@Composable
fun ProfileTabIcon(tint: Color, size: Dp = 17.dp) {
    Canvas(Modifier.size(size)) {
        val scale = this.size.width / 24f
        drawCircle(tint, radius = 3.2f * scale, center = Offset(12f * scale, 8f * scale), style = Stroke(width = 1.5f * scale))
        strokePath(listOf(Offset(5f, 20f), Offset(8.5f, 12.5f), Offset(12f, 14f), Offset(15.5f, 12.5f), Offset(19f, 20f)), tint, scale)
    }
}

@Composable
fun SettingsTabIcon(tint: Color, size: Dp = 17.dp) {
    Canvas(Modifier.size(size)) {
        val scale = this.size.width / 24f
        drawCircle(tint, radius = 2.6f * scale, center = Offset(12f * scale, 12f * scale), style = Stroke(width = 1.5f * scale))
        val spokes = listOf(
            Offset(12f, 4f) to Offset(12f, 6f),
            Offset(12f, 18f) to Offset(12f, 20f),
            Offset(4f, 12f) to Offset(6f, 12f),
            Offset(18f, 12f) to Offset(20f, 12f),
            Offset(6.3f, 6.3f) to Offset(7.7f, 7.7f),
            Offset(16.3f, 16.3f) to Offset(17.7f, 17.7f),
            Offset(17.7f, 6.3f) to Offset(16.3f, 7.7f),
            Offset(7.7f, 16.3f) to Offset(6.3f, 17.7f)
        )
        spokes.forEach { (a, b) ->
            drawLine(tint, Offset(a.x * scale, a.y * scale), Offset(b.x * scale, b.y * scale), strokeWidth = 1.5f * scale, cap = StrokeCap.Round)
        }
    }
}
