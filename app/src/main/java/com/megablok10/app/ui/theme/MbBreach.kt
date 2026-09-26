package com.megablok10.app.ui.theme

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.invisibleToUser
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp

/** Полоса «СЕТЬ ═ ДЕКА»: подпись + цветная лента, декоративная надпись у её края (например «ПРОТОКОЛ 2.07») скрыта от TalkBack. */
@OptIn(ExperimentalComposeUiApi::class)
@Composable
fun MbStrip(label: String, barText: String, modifier: Modifier = Modifier) {
    val c = LocalMbColors.current
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, style = MbTypography.tagLabel.copy(letterSpacing = 0.14f.em), color = c.acc)
        Box(Modifier.weight(1f).height(10.dp).background(c.acc.copy(alpha = 0.85f)), contentAlignment = Alignment.CenterEnd) {
            Text(
                barText,
                style = MbTypography.meta.copy(fontSize = 7.sp, fontWeight = FontWeight.Medium, letterSpacing = 0.1f.em),
                color = c.accInk,
                modifier = Modifier.padding(end = 5.dp).semantics { invisibleToUser() }
            )
        }
    }
}

/** Таймер взлома: подпись + цифровой индикатор в рамке tab; [extra] — обычно кнопка «Выйти из взлома». */
@Composable
fun MbTimer(label: String, time: String, modifier: Modifier = Modifier, timeColor: Color? = null, extra: (@Composable () -> Unit)? = null) {
    val c = LocalMbColors.current
    val tone = timeColor ?: c.acc
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label.uppercase(), style = MbTypography.settingLabel.copy(letterSpacing = 0.06f.em), color = c.ink, modifier = Modifier.weight(1f))
        Box(
            Modifier.mbFrame(fill = c.bg, edge = tone, form = MbChamferForm.Tab, cut = 5.dp).padding(horizontal = 8.dp, vertical = 5.dp)
        ) {
            Text(time, style = MbTypography.breachCell, color = tone)
        }
        extra?.invoke()
    }
}

/** Полоса прогресса взлома: тонкая линия `chromeDim` с заливкой `acc` на [percent] процентов. */
@Composable
fun MbProgress(percent: Int, modifier: Modifier = Modifier) {
    val c = LocalMbColors.current
    Box(modifier.fillMaxWidth().height(3.dp).background(c.chromeDim)) {
        Box(Modifier.fillMaxHeight().fillMaxWidth(percent.coerceIn(0, 100) / 100f).background(c.acc))
    }
}

/** Панель с залитой полосой-заголовком — буфер, матрица кодов, последовательности на экране взлома. */
@Composable
fun MbPanel(title: String, modifier: Modifier = Modifier, meta: String? = null, content: @Composable ColumnScope.() -> Unit) {
    val c = LocalMbColors.current
    Column(modifier.mbFrame(fill = c.surface, edge = c.plateEdge, form = MbChamferForm.Dlg, cut = 10.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth().background(c.acc).padding(horizontal = 8.dp, vertical = 5.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Icon(painterResource(MbIcons.Chip), contentDescription = null, tint = c.accInk, modifier = Modifier.size(13.dp))
            Text(title.uppercase(), style = MbTypography.tab.copy(fontSize = 12.sp, letterSpacing = 0.06f.em), color = c.accInk, modifier = Modifier.weight(1f))
            if (meta != null) Text(meta, style = MbTypography.metaStatus.copy(letterSpacing = 0.06f.em), color = c.accInk.copy(alpha = 0.75f))
        }
        Column(Modifier.padding(horizontal = 8.dp, vertical = 7.dp), content = content)
    }
}

/**
 * Буфер попыток: заполненные ячейки показывают набранный код, пустые — «··». В прототипе ячейки прямоугольные
 * (`box-shadow: inset 0 0 0 1px`), но проект запрещает голые прямоугольные рамки везде (гайдлайн, раздел 10;
 * `NoRectangularBordersTest`) — здесь минимальный срез 3 dp, почти незаметный на ячейке такого размера.
 */
@Composable
fun MbBuffer(codes: List<String>, size: Int, modifier: Modifier = Modifier) {
    val c = LocalMbColors.current
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(3.dp)) {
        repeat(size) { i ->
            val filled = i < codes.size
            Box(
                modifier = Modifier
                    .weight(1f)
                    .height(24.dp)
                    .border(1.dp, if (filled) c.acc else c.chromeDim, mbChamferShape(MbChamferForm.Tab, 3.dp)),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    if (filled) codes[i] else "··",
                    style = MbTypography.tagLabel,
                    color = if (filled) c.acc else c.ink3
                )
            }
        }
    }
}

enum class MbMatrixCellKind { Normal, Band, Aim, Used, Trap }
class MbMatrixCell(val code: String, val kind: MbMatrixCellKind = MbMatrixCellKind.Normal)

/** Матрица кодов 5×5: полоса выбора демона (band), прицел (aim), использованные и ловушки — своими цветами. */
@Composable
fun MbCodeMatrix(cells: List<List<MbMatrixCell>>, modifier: Modifier = Modifier) {
    val c = LocalMbColors.current
    Column(modifier.fillMaxWidth()) {
        cells.forEach { row ->
            Row(Modifier.fillMaxWidth()) {
                row.forEach { cell ->
                    val bg = when (cell.kind) {
                        MbMatrixCellKind.Band -> c.acc.copy(alpha = 0.1f)
                        MbMatrixCellKind.Aim -> c.acc
                        else -> Color.Transparent
                    }
                    val ink = when (cell.kind) {
                        MbMatrixCellKind.Aim -> c.accInk
                        MbMatrixCellKind.Used -> c.used
                        MbMatrixCellKind.Trap -> c.bad
                        MbMatrixCellKind.Band -> c.acc
                        MbMatrixCellKind.Normal -> c.ink
                    }
                    Box(
                        modifier = Modifier.weight(1f).height(MbDimens.breachCell).background(bg),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(if (cell.kind == MbMatrixCellKind.Trap) "▒▒" else cell.code, style = MbTypography.breachCell, color = ink)
                    }
                }
            }
        }
    }
}

/**
 * Журнал взлома — строки в столбик моношрифтом акцентного цвета. Высота — по содержимому (не fillMaxSize): в
 * BootLog это единственный контент панели, в ResultOverlay он делит место с итоговой плашкой и списком демонов —
 * fillMaxSize() отбирал бы у них всю высоту (баг, найден на скриншот-тесте M4.5).
 */
@Composable
fun MbLog(lines: List<String>, modifier: Modifier = Modifier) {
    Text(
        lines.joinToString("\n"),
        style = MbTypography.meta.copy(lineHeight = 16.5.sp),
        color = LocalMbColors.current.acc,
        modifier = modifier.fillMaxWidth().padding(2.dp)
    )
}

/** Итоговая плашка успешного взлома — заливка `acc` на всю ширину. */
@Composable
fun MbDone(text: String, modifier: Modifier = Modifier) {
    val c = LocalMbColors.current
    Box(modifier.fillMaxWidth().background(c.acc).padding(12.dp), contentAlignment = Alignment.Center) {
        Text(text.uppercase(), style = MbTypography.button.copy(letterSpacing = 0.08f.em), color = c.accInk)
    }
}
