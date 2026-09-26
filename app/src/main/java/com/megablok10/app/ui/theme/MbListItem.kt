package com.megablok10.app.ui.theme

import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

/** Обычная / прочитанная (приглушённая) / не в сети — «нажата» не входит сюда: это временный эффект настоящего касания, не состояние. */
enum class MbListItemState { Normal, Muted, Off }

private val TitleDefault = Color(0xFFDFF3EF)
private val TitleMuted = Color(0xFF9FB8B4)
private val SubMuted = Color(0xFF6F8784)
private val SelInk = Color(0xFFBFE7E2)

/**
 * Одна строка на все списки (раздел 5): чаты, контакты, звонки, операции, демоны, шарды, узлы, итоги взлома.
 *
 * «Нажата» — не параметр состояния, а реакция на настоящее касание (пока палец на строке), поэтому проявляется сама,
 * когда передан [onClick]; [forcePressedPreview] существует только для каталога/скриншот-теста, где показать реальное
 * касание нельзя. plate+mark вместе красне́ют при нажатии (журнал шардов), обычная строка — подсвечивается заливкой
 * `sel_fill`; голая плашка без «язычка» (демоны) отдельного вида нажатия не имеет — так в гайдлайне.
 */
@Composable
fun MbListItem(
    title: String,
    modifier: Modifier = Modifier,
    lead: (@Composable () -> Unit)? = null,
    sub: String? = null,
    titleWrap: Boolean = false,
    subWrap: Boolean = false,
    trail: List<@Composable () -> Unit> = emptyList(),
    trailRow: Boolean = false,
    state: MbListItemState = MbListItemState.Normal,
    plate: Boolean = false,
    mark: Boolean = false,
    end: Boolean = false,
    onClick: (() -> Unit)? = null,
    forcePressedPreview: Boolean = false
) {
    val c = LocalMbColors.current
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val isPressed = forcePressedPreview || pressed
    val pressedPlain = isPressed && !plate
    val pressedPlate = isPressed && plate && mark

    val content: @Composable () -> Unit = {
        val rowBg = when {
            pressedPlain -> Modifier.mbFrame(fill = c.selFill, edge = c.acc, form = MbChamferForm.Tab, cut = 12.dp).padding(vertical = 6.dp, horizontal = 8.dp)
            plate -> Modifier
                .mbFrame(
                    fill = if (pressedPlate) c.plateSel else c.plate,
                    edge = if (pressedPlate) c.plateSelEdge else c.plateEdge,
                    form = MbChamferForm.Tab,
                    cut = 8.dp
                )
                .padding(vertical = 8.dp, horizontal = 10.dp)
            else -> Modifier
                .drawBehind { drawLine(c.chromeSoft, Offset(0f, size.height), Offset(size.width, size.height), strokeWidth = 1.dp.toPx()) }
                .padding(vertical = 8.dp, horizontal = 8.dp)
        }
        val titleColor = when {
            state == MbListItemState.Off -> c.offTitle
            state == MbListItemState.Muted -> TitleMuted
            pressedPlain || pressedPlate -> Color.White
            else -> TitleDefault
        }
        val subColor = when {
            state == MbListItemState.Off -> c.offSub
            state == MbListItemState.Muted -> SubMuted
            pressedPlain -> SelInk
            else -> c.ink2
        }
        val leadColor = if (state == MbListItemState.Off) c.offSub else if (pressedPlain) SelInk else c.ink2

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = MbDimens.rowHeight)
                .then(if (onClick != null) Modifier.clickable(interactionSource = interaction, indication = null, onClick = onClick) else Modifier)
                .then(rowBg),
            verticalAlignment = Alignment.CenterVertically
        ) {
            if (lead != null) {
                Box(Modifier.size(18.dp), contentAlignment = Alignment.Center) {
                    CompositionLocalProvider(LocalContentColor provides leadColor) { lead() }
                }
                Spacer(Modifier.width(10.dp))
            }
            Column(Modifier.weight(1f), horizontalAlignment = if (end) Alignment.End else Alignment.Start) {
                Text(
                    title.uppercase(),
                    style = MbTypography.listItemTitle,
                    color = titleColor,
                    maxLines = if (titleWrap) 2 else 1,
                    overflow = TextOverflow.Ellipsis,
                    textAlign = if (end) TextAlign.End else TextAlign.Start
                )
                if (sub != null) {
                    Spacer(Modifier.height(4.dp))
                    Text(
                        sub,
                        style = MbTypography.rowSub,
                        color = subColor,
                        maxLines = if (subWrap) Int.MAX_VALUE else 1,
                        overflow = TextOverflow.Ellipsis,
                        textAlign = if (end) TextAlign.End else TextAlign.Start
                    )
                }
            }
            if (trail.isNotEmpty()) {
                Spacer(Modifier.width(10.dp))
                if (trailRow) {
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                        trail.forEach { it() }
                    }
                } else {
                    Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(5.dp)) {
                        trail.forEach { it() }
                    }
                }
            }
        }
    }

    if (mark) {
        val markerFill = if (pressedPlate) c.plateSel else c.mark
        val markerEdge = if (pressedPlate) c.plateSelEdge else c.markEdge
        Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            Box(
                Modifier
                    .size(width = 14.dp, height = MbDimens.rowHeight)
                    .mbFrame(fill = markerFill, edge = markerEdge, form = MbChamferForm.Tab, cut = 5.dp)
            )
            Box(Modifier.weight(1f)) { content() }
        }
    } else {
        Box(modifier.fillMaxWidth()) { content() }
    }
}
