package com.megablok10.app.ui.theme

import androidx.annotation.DrawableRes
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em

/** Виды кнопки — раздел 5 гайдлайна. Одна primary на экран, остальные — по смыслу конкретного действия. */
enum class MbButtonKind { Primary, Ghost, Success, Danger, Alert, Quiet }

private class MbButtonPalette(val fill: Color, val edge: Color, val ink: Color, val letterSpacingEm: Float)

@Composable
private fun mbButtonPalette(kind: MbButtonKind): MbButtonPalette {
    val c = LocalMbColors.current
    return when (kind) {
        MbButtonKind.Primary -> MbButtonPalette(c.acc, c.acc, c.accInk, 0.1f)
        MbButtonKind.Ghost -> MbButtonPalette(Color(0xFF1B1215), Color(0xFFDCCBC8), Color(0xFFF1ECEA), 0.1f)
        MbButtonKind.Success -> MbButtonPalette(Color(0xFF0F3A2A), c.ok, Color(0xFFDFFFEE), 0.1f)
        MbButtonKind.Danger -> MbButtonPalette(Color(0xFF3A1214), c.bad, Color(0xFFFFE3DF), 0.1f)
        MbButtonKind.Alert -> MbButtonPalette(Color(0xFFB3312A), c.bad, Color.White, 0.08f)
        MbButtonKind.Quiet -> MbButtonPalette(c.dlgFill, c.dlgBar, c.acc, 0.04f)
    }
}

/** `filter:brightness(1.35)` прототипа — умножение канала, а не смешивание с белым (то было бы `lighten`, не `brightness`). */
private fun brightness135(color: Color): Color = Color(
    red = (color.red * 1.35f).coerceIn(0f, 1f),
    green = (color.green * 1.35f).coerceIn(0f, 1f),
    blue = (color.blue * 1.35f).coerceIn(0f, 1f),
    alpha = color.alpha
)

/**
 * Кнопка стандартной формы (срез std, 8 dp), высота 48 dp. [inline] — по ширине текста вместо всей строки
 * (действия в шапке экрана, кнопки под окном). [keyIcon] — «клавиша» слева, как в подтверждении звонка/окне.
 */
@Composable
fun MbButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    kind: MbButtonKind = MbButtonKind.Primary,
    @DrawableRes keyIcon: Int? = null,
    enabled: Boolean = true,
    inline: Boolean = false
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val focused by interaction.collectIsFocusedAsState()
    val palette = mbButtonPalette(kind)
    val fill = when {
        !enabled -> Color(0xFF1A1416)
        pressed -> brightness135(palette.fill)
        else -> palette.fill
    }
    val edge = when {
        !enabled -> Color(0xFF3A2A2C)
        focused -> Color.White
        pressed -> brightness135(palette.edge)
        else -> palette.edge
    }
    val ink = if (enabled) palette.ink else Color(0xFF7D6A6D)
    Row(
        modifier = modifier
            .then(if (inline) Modifier.wrapContentWidth() else Modifier.fillMaxWidth())
            .heightIn(min = MbDimens.buttonHeight)
            .mbFrame(fill = fill, edge = edge, form = MbChamferForm.Std, width = if (focused) 2.dp else 1.dp)
            .clickable(interactionSource = interaction, indication = null, enabled = enabled, onClick = onClick)
            .padding(horizontal = if (inline) 16.dp else 12.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (keyIcon != null) {
            MbKeyCap(keyIcon, tint = ink, fill = fill)
            Spacer(Modifier.width(8.dp))
        }
        Text(text, color = ink, style = MbTypography.button.copy(letterSpacing = palette.letterSpacingEm.em), textAlign = TextAlign.Center)
    }
}

/** «Клавиша» из игры — иконка в рамке форма tab, 22×22, рамка 1,5 dp цветом [tint] (по умолчанию — как рамка кнопки). */
@Composable
fun MbKeyCap(
    @DrawableRes icon: Int,
    modifier: Modifier = Modifier,
    tint: Color = LocalMbColors.current.ink,
    fill: Color = LocalMbColors.current.bg
) {
    Box(
        modifier = modifier
            .defaultMinSize(minWidth = 22.dp, minHeight = 22.dp)
            .mbFrame(fill = fill, edge = tint, form = MbChamferForm.Tab, cut = 4.dp, width = 1.5.dp)
            .padding(horizontal = 4.dp),
        contentAlignment = Alignment.Center
    ) {
        Icon(painterResource(icon), contentDescription = null, tint = tint, modifier = Modifier.size(13.dp))
    }
}

/**
 * Кнопка-иконка: рисунок 40 dp (форма tab, срез 6 dp), область нажатия 48 dp — [Modifier.minimumInteractiveComponentSize]
 * снаружи, до фиксированного размера рисунка. `contentDescription` обязателен: по нему кнопку находит и TalkBack, и e2e-стенд.
 */
@Composable
fun MbIconButton(
    @DrawableRes icon: Int,
    contentDescription: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    fill: Color = LocalMbColors.current.plate,
    edge: Color = LocalMbColors.current.plateEdge,
    tint: Color = LocalMbColors.current.ink,
    enabled: Boolean = true
) {
    Box(
        modifier = modifier
            .minimumInteractiveComponentSize()
            .size(MbDimens.iconButtonArt)
            .mbFrame(fill = fill, edge = edge, form = MbChamferForm.Tab, cut = 6.dp)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                enabled = enabled,
                onClick = onClick
            ),
        contentAlignment = Alignment.Center
    ) {
        Icon(painterResource(icon), contentDescription = contentDescription, tint = if (enabled) tint else edge, modifier = Modifier.size(18.dp))
    }
}

class MbActionBarItem(@DrawableRes val icon: Int, val label: String, val onClick: () -> Unit)

/** Подвал действий экрана: линия `chrome` сверху, пункты «клавиша + ПОДПИСЬ» справа, каждый высотой 48 dp. */
@Composable
fun MbActionBar(items: List<MbActionBarItem>, modifier: Modifier = Modifier) {
    val chrome = LocalMbColors.current.chrome
    val ink = LocalMbColors.current.ink
    Row(
        modifier = modifier
            .fillMaxWidth()
            .drawBehind { drawLine(chrome, Offset(0f, 0f), Offset(size.width, 0f), strokeWidth = 1.dp.toPx()) }
            .padding(top = 1.dp),
        horizontalArrangement = Arrangement.End
    ) {
        items.forEachIndexed { i, item ->
            Row(
                modifier = Modifier
                    .heightIn(min = MbDimens.rowHeight)
                    .clickable(onClick = item.onClick)
                    .padding(start = if (i == 0) 0.dp else 14.dp, end = 2.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                MbKeyCap(item.icon, tint = ink)
                Spacer(Modifier.width(6.dp))
                Text(item.label.uppercase(), style = MbTypography.footerLabel, color = chrome)
            }
        }
    }
}
