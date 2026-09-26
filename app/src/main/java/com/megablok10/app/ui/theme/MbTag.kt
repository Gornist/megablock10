package com.megablok10.app.ui.theme

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em

/** Смысловой тон метки/статуса — раздел 5 гайдлайна: жёлтый «новое», зелёный/красный «итог», оранжевый «нужно действие». */
enum class MbTagTone { Money, Ok, Bad, Warn }

/**
 * Метка (раздел 5): форма tab, срез 4 dp. `filled` — сплошная жёлтая заливка для «нового» и счётчиков (единственный
 * вариант заливки в гайдлайне); без заливки — контурная, цвет по [tone].
 */
@Composable
fun MbTag(text: String, modifier: Modifier = Modifier, filled: Boolean = false, tone: MbTagTone = MbTagTone.Money, bg: Color = LocalMbColors.current.bg) {
    val c = LocalMbColors.current
    val (ink, edge) = when (tone) {
        MbTagTone.Money -> c.money to c.money
        MbTagTone.Ok -> c.ok to c.ok
        MbTagTone.Bad -> Color(0xFFFF7A70) to Color(0xFF8A3A36)
        MbTagTone.Warn -> c.warn to c.warn
    }
    val fill = if (filled) c.money else bg
    val textColor = if (filled) c.onMoney else ink
    Box(
        modifier
            .mbFrame(fill = fill, edge = edge, form = MbChamferForm.Tab, cut = 4.dp)
            .padding(horizontal = 6.dp, vertical = 4.dp)
    ) {
        Text(text.uppercase(), style = MbTypography.tagLabel, color = textColor)
    }
}

/** Тон статуса (раздел 5): ok/dim — без иконки, warn/bad — ещё и иконкой (часы/⚠), статус никогда не держится на одном цвете. */
enum class MbStatusTone { Ok, Warn, Bad, Dim }

@Composable
fun MbStatusText(text: String, tone: MbStatusTone, modifier: Modifier = Modifier) {
    val c = LocalMbColors.current
    val color = when (tone) {
        MbStatusTone.Ok -> c.ok
        MbStatusTone.Warn -> c.warn
        MbStatusTone.Bad -> c.bad
        MbStatusTone.Dim -> c.ink3
    }
    Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        when (tone) {
            MbStatusTone.Warn -> Icon(painterResource(MbIcons.Clock), contentDescription = null, tint = color, modifier = Modifier.size(11.dp))
            MbStatusTone.Bad -> Icon(painterResource(MbIcons.Alert), contentDescription = null, tint = color, modifier = Modifier.size(11.dp))
            else -> {}
        }
        Text(text.uppercase(), style = MbTypography.metaStatus.copy(letterSpacing = 0.06f.em), color = color)
    }
}
