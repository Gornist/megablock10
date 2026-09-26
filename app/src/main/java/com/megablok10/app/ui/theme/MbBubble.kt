package com.megablok10.app.ui.theme

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.GenericShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp

/**
 * Пузырь сообщения — отдельная форма с хвостиком со стороны отправителя (раздел 4 гайдлайна), не одна из трёх
 * форм среза [MbChamferForm]: срез 8 dp у верхнего угла со стороны собеседника, хвостик — скошенный нижний край
 * с отступом 13 dp от края отправителя.
 */
@Composable
private fun mbBubbleShape(fromMe: Boolean, cut: Dp, tailNotch: Dp, tailInset: Dp): Shape {
    val cutPx = with(LocalDensity.current) { cut.toPx() }
    val notchPx = with(LocalDensity.current) { tailNotch.toPx() }
    val insetPx = with(LocalDensity.current) { tailInset.toPx() }
    return GenericShape { size, _ ->
        val c = cutPx.coerceIn(0f, minOf(size.width, size.height))
        val n = notchPx.coerceIn(0f, size.height)
        val i = insetPx.coerceIn(0f, size.width)
        if (!fromMe) {
            moveTo(0f, 0f)
            lineTo(size.width - c, 0f)
            lineTo(size.width, c)
            lineTo(size.width, size.height - n)
            lineTo(i, size.height - n)
            lineTo(0f, size.height)
            close()
        } else {
            moveTo(c, 0f)
            lineTo(size.width, 0f)
            lineTo(size.width, size.height)
            lineTo(size.width - i, size.height - n)
            lineTo(0f, size.height - n)
            lineTo(0f, c)
            close()
        }
    }
}

@Composable
private fun bubbleBackground(fromMe: Boolean, fill: Color, edge: Color): Modifier {
    val outer = mbBubbleShape(fromMe, cut = 8.dp, tailNotch = 9.dp, tailInset = 13.dp)
    val inner = mbBubbleShape(fromMe, cut = 7.dp, tailNotch = 8.dp, tailInset = 12.dp)
    return Modifier.background(edge, outer).padding(1.dp).background(fill, inner)
}

/** Входящее — слева, тёмное с бирюзовой рамкой; своё — справа, зелёное. Ширина по тексту — до 82% отдаёт вызывающий экран. */
@Composable
fun MbBubble(fromMe: Boolean, text: String, meta: String, modifier: Modifier = Modifier) {
    val c = LocalMbColors.current
    val fill = if (fromMe) c.bubbleOwnFill else c.bubbleInFill
    val edge = if (fromMe) c.bubbleOwnEdge else c.bubbleInEdge
    val ink = if (fromMe) c.bubbleOwnText else c.bubbleInText
    val metaColor = if (fromMe) Color(0xFFA9E8C3) else c.ink2
    Column(
        modifier
            .then(bubbleBackground(fromMe, fill, edge))
            .padding(start = 10.dp, top = 7.dp, end = 10.dp, bottom = 16.dp),
        verticalArrangement = Arrangement.spacedBy(3.dp)
    ) {
        Text(text, style = MbTypography.messageText, color = ink)
        Text(meta, style = MbTypography.meta.copy(letterSpacing = 0.04f.em), color = metaColor, modifier = Modifier.align(Alignment.End))
    }
}

/**
 * Перевод (или передача предмета — тот же вид, гайдлайн отдельную карточку для неё не определяет) — пузырь своего вида:
 * заголовок «ПЕРЕВОД · …», значение крупно, статус строкой (обычно [MbStatusText]). Прототип рисует только свой (зелёный)
 * вариант; [fromMe] = false — входящий, теми же цветами, что обычный входящий пузырь ([MbBubble]).
 */
@Composable
fun MbPayBubble(head: String, value: String, modifier: Modifier = Modifier, fromMe: Boolean = true, note: @Composable () -> Unit) {
    val c = LocalMbColors.current
    val fill = if (fromMe) Color(0xFF0F1A14) else c.bubbleInFill
    val edge = if (fromMe) c.ok else c.bubbleInEdge
    val headColor = if (fromMe) c.ok else c.bubbleInText
    val valueColor = if (fromMe) Color(0xFFF1FFF6) else c.bubbleInText
    Column(
        modifier
            .then(bubbleBackground(fromMe, fill, edge))
            .padding(start = 10.dp, top = 7.dp, end = 10.dp, bottom = 16.dp),
        verticalArrangement = Arrangement.spacedBy(3.dp)
    ) {
        Text(head.uppercase(), style = MbTypography.tagLabel.copy(letterSpacing = 0.1f.em), color = headColor)
        Text(value, style = TextStyle(fontFamily = FiraSansCondensed, fontWeight = FontWeight.Medium, fontSize = 22.sp), color = valueColor)
        note()
    }
}

/** «— СЕГОДНЯ —» по центру ленты сообщений. */
@Composable
fun MbDaySep(text: String, modifier: Modifier = Modifier) {
    Text(
        "— ${text.uppercase()} —",
        style = MbTypography.tagLabel.copy(letterSpacing = 0.1f.em),
        color = LocalMbColors.current.chrome.copy(alpha = 0.8f),
        modifier = modifier.fillMaxWidth(),
        textAlign = TextAlign.Center
    )
}

/** Поле ввода (форма tab) + квадратная кнопка отправки 48 dp. Действия переписки — в Breadcrumb, не здесь (клавиатура). */
@Composable
fun MbComposer(
    value: String,
    onValueChange: (String) -> Unit,
    onSend: () -> Unit,
    modifier: Modifier = Modifier,
    placeholder: String = "Сообщение"
) {
    val c = LocalMbColors.current
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(
            Modifier
                .weight(1f)
                .heightIn(min = MbDimens.rowHeight)
                .mbFrame(fill = Color(0xFF140D10), edge = Color(0xFF6B3337), form = MbChamferForm.Tab, cut = 8.dp)
                .padding(horizontal = 12.dp),
            contentAlignment = Alignment.CenterStart
        ) {
            if (value.isEmpty()) Text(placeholder, style = MbTypography.dialogText, color = c.ink3)
            BasicTextField(
                value = value,
                onValueChange = onValueChange,
                textStyle = MbTypography.dialogText.copy(color = c.ink),
                cursorBrush = SolidColor(c.acc),
                // Плейсхолдер — соседний Text, не связанный с полем: без этого TalkBack получает пустое поле без
                // подписи (найдено на реальном устройстве, M6 плана миграции — Т13; первый же сценарий чек-листа,
                // «прочитать сообщение и ответить», упирался в немое поле ответа).
                modifier = Modifier.fillMaxWidth().semantics { contentDescription = placeholder }
            )
        }
        Box(
            Modifier
                .size(MbDimens.rowHeight)
                .mbFrame(fill = c.acc, edge = c.acc, form = MbChamferForm.Std, cut = 8.dp)
                .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = onSend),
            contentAlignment = Alignment.Center
        ) {
            Icon(painterResource(MbIcons.Send), contentDescription = "Отправить", tint = c.accInk, modifier = Modifier.size(18.dp))
        }
    }
}
