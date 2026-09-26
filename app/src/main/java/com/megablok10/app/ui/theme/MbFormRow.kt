package com.megablok10.app.ui.theme

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Строка настройки: подпись слева, элемент справа в колонке 128 dp, высота 48 dp. */
@Composable
fun MbFormRow(label: String, modifier: Modifier = Modifier, control: @Composable () -> Unit) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = MbDimens.rowHeight)
            .padding(vertical = 2.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(label, style = MbTypography.settingLabel, color = LocalMbColors.current.label, modifier = Modifier.weight(1f))
        Box(Modifier.widthIn(min = 96.dp, max = 128.dp), contentAlignment = Alignment.CenterEnd) { control() }
    }
}

/** Переключатель «ВЫКЛ | ВКЛ»: активная половина ВЫКЛ — `plateSel` (красная), активная ВКЛ — `selFill` (бирюзовая). */
@Composable
fun MbToggle(on: Boolean, onToggle: (Boolean) -> Unit, modifier: Modifier = Modifier) {
    val c = LocalMbColors.current
    Row(
        modifier = modifier
            .width(96.dp)
            .height(32.dp)
            .mbFrame(fill = Color(0xFF101A1B), edge = Color(0xFF2C4A4A), form = MbChamferForm.Tab, cut = 7.dp)
            .clickable { onToggle(!on) }
    ) {
        val idle = Color(0xFF86A09D)
        Box(
            Modifier.weight(1f).fillMaxHeight().background(if (!on) c.plateSel else Color.Transparent),
            contentAlignment = Alignment.Center
        ) {
            Text("ВЫКЛ", style = MbTypography.tagLabel, color = if (!on) Color.White else idle)
        }
        Box(
            Modifier.weight(1f).fillMaxHeight().background(if (on) c.selFill else Color.Transparent),
            contentAlignment = Alignment.Center
        ) {
            Text("ВКЛ", style = MbTypography.tagLabel, color = if (on) Color(0xFFEAFFFD) else idle)
        }
    }
}

/** Ползунок: красный бегунок на тёмной полосе, значение по центру моношрифтом. [percent] — позиция бегунка 0..100. */
@Composable
fun MbSlider(percent: Int, value: String, modifier: Modifier = Modifier) {
    val c = LocalMbColors.current
    BoxWithConstraints(
        modifier
            .fillMaxWidth()
            .height(32.dp)
            .mbFrame(fill = c.plate, edge = c.plateEdge, form = MbChamferForm.Tab, cut = 7.dp)
    ) {
        val thumbX = (maxWidth * (percent.coerceIn(0, 100) / 100f) - 7.dp).coerceIn(0.dp, (maxWidth - 14.dp).coerceAtLeast(0.dp))
        Box(
            Modifier
                .offset(x = thumbX)
                .fillMaxHeight()
                .padding(vertical = 1.dp)
                .width(14.dp)
                .background(c.plateSel)
        )
        Text(value, style = MbTypography.tagLabel, color = c.acc, modifier = Modifier.align(Alignment.Center))
    }
}

/** Значение только для чтения — моношрифт, акцентный цвет, выравнивание вправо. */
@Composable
fun MbValue(text: String, modifier: Modifier = Modifier, tone: Color = LocalMbColors.current.acc) {
    Text(
        text,
        style = TextStyle(fontFamily = IBMPlexMono, fontWeight = FontWeight.Medium, fontSize = 12.sp),
        color = tone,
        textAlign = TextAlign.End,
        modifier = modifier
    )
}
