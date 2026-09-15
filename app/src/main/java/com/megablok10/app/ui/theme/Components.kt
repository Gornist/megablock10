package com.megablok10.app.ui.theme

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxSize
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
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.width
import androidx.compose.ui.Alignment
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Двухслойная рамка со срезом: border не комбинируется с clip-path на одном
 * элементе, поэтому "рамка" рисуется отдельным фоном под отступом borderWidth
 * от заливки. Это ОДИН Box с цепочкой модификаторов (фон рамки → отступ →
 * фон заливки → отступ → контент), а не два вложенных Box — важно: вложенный
 * Box с fillMaxSize()/fillMaxWidth() внутри Box без своего размера даёт
 * циклическую зависимость размеров (родитель хочет обернуть ребёнка, ребёнок
 * хочет заполнить родителя) и панель раздувается на весь доступный экран.
 * Модификаторы в цепочке такой проблемы не создают: Box просто оборачивает
 * content, а фоны/паддинги — это концентрические отступы вокруг него.
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
            .background(fillColor, innerShape)
            .padding(contentPadding),
        content = content
    )
}

@Composable
fun HexBullet(color: Color = MB10Colors.accentPrimary, size: Dp = 8.dp) {
    Box(Modifier.size(size).background(color, hexShape()))
}

/**
 * Контурный шестиугольник с буквой/пиктограммой внутри — в отличие от
 * HexBullet (залитая точка-статус), это отдельная сущность с содержимым:
 * инициал позывного там, где аватарок в базе нет. Только обводка (border,
 * не background) — залитый вариант остаётся исключительно за HexBullet.
 */
@Composable
fun HexOutlineIcon(letter: String, color: Color = MB10Colors.ink0, size: Dp = 32.dp, borderWidth: Dp = 1.5.dp) {
    Box(
        modifier = Modifier.size(size).border(borderWidth, color, hexShape()),
        contentAlignment = Alignment.Center
    ) {
        Text(letter, color = color, fontFamily = Jura, fontWeight = androidx.compose.ui.text.font.FontWeight.Bold, fontSize = (size.value * 0.4f).sp)
    }
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

/** Кастомный тумблер по макету — трек 34x18, ручка 12x12, on = жёлтый. */
@Composable
fun MB10Toggle(checked: Boolean, onCheckedChange: (Boolean) -> Unit, modifier: Modifier = Modifier) {
    val knobOffset by animateDpAsState(if (checked) 18.dp else 2.dp, tween(150), label = "toggleKnob")
    Box(
        modifier = modifier
            .size(width = 34.dp, height = 18.dp)
            .background(MB10Colors.bg2)
            .border(1.dp, if (checked) MB10Colors.accentPrimary else MB10Colors.inkFaint)
            .clickable { onCheckedChange(!checked) }
    ) {
        Box(
            modifier = Modifier
                .padding(start = knobOffset, top = 2.dp)
                .size(12.dp)
                .background(if (checked) MB10Colors.accentPrimary else MB10Colors.inkMuted)
        )
    }
}

@Composable
fun FlagTab(text: String, accent: Color = MB10Colors.accentHack, modifier: Modifier = Modifier) {
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
fun SectionLabel(text: String, color: Color = MB10Colors.inkMuted, modifier: Modifier = Modifier) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = modifier.padding(bottom = 8.dp)) {
        HexBullet(color, size = 8.dp)
        Spacer(Modifier.width(6.dp))
        Text(text, color = color, fontFamily = JetBrainsMono, fontSize = 10.5.sp)
    }
}

/** Чамфер-бейдж с рамкой — код демона, статус шарда, версия базы. Один визуальный паттерн вместо трёх копий по экранам. */
@Composable
fun Chip(text: String, color: Color = MB10Colors.inkMuted, cut: Dp = 4.dp, modifier: Modifier = Modifier) {
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
    accentColor: Color = MB10Colors.ink0,
    borderColor: Color = accentColor,
    enabled: Boolean = true,
    onClick: () -> Unit
) {
    val effectiveTextColor = if (enabled) accentColor else MB10Colors.inkFaint
    val effectiveBorderColor = if (enabled) borderColor else MB10Colors.inkFaint
    Box(
        modifier = modifier
            .border(1.dp, effectiveBorderColor, chamferShape(5.dp))
            .clickable(enabled = enabled, onClick = onClick)
            .padding(vertical = 10.dp)
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
 * Дисклеймер "это макет, не реальные данные" — одна строка мелким моно
 * текстом. Нужен там, где статичные цифры/статусы визуально неотличимы от
 * настоящих игровых данных (карантин-таймер, репутация, баланс) и живой
 * тестировщик может принять заглушку за баг или за факт игры.
 */
@Composable
fun DemoNotice(text: String, modifier: Modifier = Modifier) {
    Text(
        "// $text",
        color = MB10Colors.inkFaint,
        fontFamily = JetBrainsMono,
        fontSize = 9.5.sp,
        modifier = modifier
    )
}

/**
 * Строка выбираемого списка. Невыбранная — только тонкая рамка (обычный
 * ChamferedPanel-паттерн). Выбранная — сплошная заливка акцентом на всю
 * строку, а не просто более толстая рамка или второй индикатор (галочка и
 * т.п.) — единственный сигнал состояния сам по себе. Текст/иконки внутри
 * content должны сами переключаться на onAccent при selected == true —
 * компонент передаёт это решение наружу, а не красит контент сам.
 */
@Composable
fun SelectableRow(
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    accentColor: Color = MB10Colors.accentPrimary,
    borderColor: Color = MB10Colors.accentBorder,
    cut: Dp = 6.dp,
    content: @Composable RowScope.() -> Unit
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .then(
                if (selected) Modifier.background(accentColor, chamferShape(cut))
                else Modifier.border(1.dp, borderColor, chamferShape(cut))
            )
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        content = content
    )
}
