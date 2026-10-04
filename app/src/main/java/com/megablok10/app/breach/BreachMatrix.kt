package com.megablok10.app.breach

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.AnimationVector1D
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.megablok10.app.ui.theme.LocalMbColors
import com.megablok10.app.ui.theme.MbChamferForm
import com.megablok10.app.ui.theme.MbDimens
import com.megablok10.app.ui.theme.MbTypography
import com.megablok10.app.ui.theme.mbFrame
import kotlin.math.roundToInt

/**
 * Содержимое панели «Матрица кодов»: сетка ячеек, размер которых считается из доступной ширины. [shake] — сдвиг сетки по горизонтали
 * при ловушке (читается только в фазе размещения), [onCell] получает тапнутую клетку.
 */
@Composable
internal fun BreachMatrix(run: BreachRun, shake: Animatable<Float, AnimationVector1D>, onCell: (Pair<Int, Int>) -> Unit) {
    val attempt = run.attempt
    val selectable = run.selectable
    BoxWithConstraints(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        val n = attempt.grid.size
        val gap = 4.dp
        val cell = ((maxWidth - gap * (n - 1)) / n).coerceIn(28.dp, MbDimens.breachCell)
        Column(Modifier.offset { IntOffset(shake.value.roundToInt(), 0) }, verticalArrangement = Arrangement.spacedBy(gap)) {
            for (r in 0 until n) {
                Row(horizontalArrangement = Arrangement.spacedBy(gap)) {
                    for (col in 0 until n) {
                        val at = r to col
                        val order = attempt.selected.indexOf(at)
                        HackCell(
                            size = cell,
                            code = attempt.grid.codeAt(at),
                            isSelected = order >= 0,
                            orderLabel = if (order >= 0) (order + 1).toString() else null,
                            isSelectable = at in selectable,
                            onClick = { onCell(at) }
                        )
                    }
                }
            }
        }
    }
}

/** Ячейка матрицы: квадрат заданного размера. Шрифт растёт вместе с ячейкой, но не мельче 12 sp. */
@Composable
internal fun HackCell(size: Dp, code: String, isSelected: Boolean, orderLabel: String?, isSelectable: Boolean, onClick: () -> Unit) {
    val c = LocalMbColors.current
    val isDead = code == BreachSymbols.DEAD_MARKER
    val (bg, border, ink) = when {
        isDead && !isSelected -> Triple(c.bad.copy(alpha = 0.08f), c.bad, c.bad)
        isSelected -> Triple(c.bg, c.chromeDim, c.used)
        isSelectable -> Triple(c.acc.copy(alpha = 0.07f), c.acc, c.acc)
        else -> Triple(c.plate, c.plateEdge, c.ink)
    }
    Box(
        modifier = Modifier
            .size(size)
            .mbFrame(fill = bg, edge = border, form = MbChamferForm.Tab, cut = 4.dp)
            .clickable(enabled = isSelectable, onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        Text(code, style = MbTypography.breachCell.copy(fontSize = (size.value * 0.32f).coerceIn(12f, 18f).sp), color = ink)
        if (orderLabel != null) {
            Text(
                orderLabel, color = c.acc, fontSize = 11.sp, fontWeight = FontWeight.Bold,
                modifier = Modifier.align(Alignment.TopEnd).padding(horizontal = 3.dp, vertical = 1.dp)
            )
        }
    }
}
