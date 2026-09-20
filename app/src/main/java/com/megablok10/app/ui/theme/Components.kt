package com.megablok10.app.ui.theme

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.width
import androidx.compose.ui.Alignment
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun HexBullet(color: Color = MB10Colors.accentAction, size: Dp = 8.dp) {
    Box(Modifier.size(size).background(color, hexShape()))
}

@Composable
fun DottedDivider(color: Color = MB10Colors.borderMuted, modifier: Modifier = Modifier) {
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

/** Кастомный тумблер по макету — трек 34x18, ручка 12x12, on = акцент действия. */
@Composable
fun AppToggle(checked: Boolean, onCheckedChange: (Boolean) -> Unit, modifier: Modifier = Modifier) {
    val knobOffset by animateDpAsState(if (checked) 18.dp else 2.dp, tween(150), label = "toggleKnob")
    Box(
        modifier = modifier
            .size(width = 34.dp, height = 18.dp)
            .background(MB10Colors.surfaceSunken, chamferShape(4.dp))
            .chamferBorder(if (checked) MB10Colors.accentAction else MB10Colors.borderMuted, cut = 4.dp)
            .clickable { onCheckedChange(!checked) }
    ) {
        Box(
            modifier = Modifier
                .padding(start = knobOffset, top = 2.dp)
                .size(12.dp)
                .background(if (checked) MB10Colors.accentAction else MB10Colors.inkSecondary, chamferShape(3.dp))
        )
    }
}

@Composable
fun FlagTab(text: String, accent: Color = MB10Colors.accentNetrun, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .background(accent, flagTabShape())
            .padding(start = 9.dp, end = 14.dp, top = 5.dp, bottom = 5.dp)
    ) {
        Text(text, color = Color.Black, fontFamily = JetBrainsMono, fontSize = 10.sp)
    }
}

/** Мелкий заголовок секции: hex-буллит + моно-текст капсом. Повторяется на каждом экране со списками. */
@Composable
fun SectionLabel(text: String, color: Color = MB10Colors.inkSecondary, modifier: Modifier = Modifier) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = modifier.padding(bottom = 8.dp)) {
        HexBullet(color, size = 8.dp)
        Spacer(Modifier.width(6.dp))
        Text(text, color = color, fontFamily = JetBrainsMono, fontSize = 10.5.sp)
    }
}

/** Чамфер-бейдж с рамкой — код демона, статус шарда, версия базы. Один визуальный паттерн вместо трёх копий по экранам. */
@Composable
fun Chip(text: String, color: Color = MB10Colors.inkSecondary, cut: Dp = 4.dp, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .background(color.copy(alpha = 0.08f), chamferShape(cut))
            .border(1.dp, color, chamferShape(cut))
            .padding(horizontal = 7.dp, vertical = 2.dp)
    ) {
        Text(text, color = color, fontFamily = JetBrainsMono, fontSize = 9.5.sp)
    }
}

/**
 * Кнопка-рамка с моно-текстом по центру — единственный вариант "аутлайн"
 * кнопки в стайлгайде. accentColor красит и рамку, и текст (red для
 * опасных действий, ink0 по умолчанию).
 */
@Composable
fun OutlineButton(
    text: String,
    modifier: Modifier = Modifier,
    accentColor: Color = MB10Colors.inkPrimary,
    borderColor: Color = accentColor,
    enabled: Boolean = true,
    verticalPadding: Dp = 10.dp,
    onClick: () -> Unit
) {
    val effectiveTextColor = if (enabled) accentColor else MB10Colors.borderMuted
    val effectiveBorderColor = if (enabled) borderColor else MB10Colors.borderMuted
    Box(
        modifier = modifier
            .border(1.dp, effectiveBorderColor, chamferShape(5.dp))
            .clickable(enabled = enabled, onClick = onClick)
            .padding(vertical = verticalPadding)
    ) {
        Text(
            text,
            color = effectiveTextColor,
            fontFamily = JetBrainsMono,
            fontSize = 11.sp,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth()
        )
    }
}


/**
 * Плавающая кнопка сканирования — главное действие Кибердеки. Лаймовая (действие взлома), скошенная; лежит в правом нижнем углу,
 * куда дотягивается большой палец, и не съедает высоту списка.
 */
@Composable
fun ScanFab(onClick: () -> Unit, modifier: Modifier = Modifier, label: String = "Сканировать") {
    Row(
        modifier = modifier
            .background(MB10Colors.accentNetrun, chamferShape(8.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Видоискатель: четыре уголка и точка.
        Canvas(Modifier.size(18.dp)) {
            val stroke = 2.dp.toPx()
            val arm = 5.dp.toPx()
            val w = size.width
            val h = size.height
            val c = MB10Colors.onAccent
            drawLine(c, Offset(0f, 0f), Offset(arm, 0f), stroke); drawLine(c, Offset(0f, 0f), Offset(0f, arm), stroke)
            drawLine(c, Offset(w, 0f), Offset(w - arm, 0f), stroke); drawLine(c, Offset(w, 0f), Offset(w, arm), stroke)
            drawLine(c, Offset(0f, h), Offset(arm, h), stroke); drawLine(c, Offset(0f, h), Offset(0f, h - arm), stroke)
            drawLine(c, Offset(w, h), Offset(w - arm, h), stroke); drawLine(c, Offset(w, h), Offset(w, h - arm), stroke)
            drawCircle(c, radius = 2.dp.toPx(), center = Offset(w / 2, h / 2))
        }
        Spacer(Modifier.width(8.dp))
        Text(label, color = MB10Colors.onAccent, fontFamily = JetBrainsMono, fontWeight = FontWeight.Medium, fontSize = 13.sp)
    }
}
