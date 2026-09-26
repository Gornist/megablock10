package com.megablok10.app.ui.theme

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp

enum class MbTileTone { Neutral, Ok, Money }

/** Плитка с числом (раздел 5): баланс (крупная, деньги), состояние сети (зелёная рамка — «всё в порядке»). Сетка — 2 колонки. */
@Composable
fun MbTile(
    label: String,
    modifier: Modifier = Modifier,
    value: String? = null,
    valueUnit: String? = null,
    leadingDot: Boolean = false,
    subItems: List<String> = emptyList(),
    tone: MbTileTone = MbTileTone.Neutral,
    big: Boolean = false
) {
    val c = LocalMbColors.current
    val edge = if (tone == MbTileTone.Ok) Color(0xFF2E6B52) else c.plateEdge
    val valueColor = when (tone) {
        MbTileTone.Ok -> Color(0xFFDFFFEE)
        MbTileTone.Money -> c.money
        MbTileTone.Neutral -> c.inkStrong
    }
    Column(
        modifier = modifier
            .mbFrame(fill = c.plate2, edge = edge, form = MbChamferForm.Std, cut = 8.dp)
            .padding(horizontal = 11.dp, vertical = 9.dp),
        verticalArrangement = Arrangement.spacedBy(5.dp)
    ) {
        Text(label.uppercase(), style = MbTypography.tagLabel.copy(letterSpacing = 0.1f.em), color = c.chromeDeep)
        if (value != null) {
            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                if (leadingDot) Box(Modifier.size(6.dp).background(c.ok, CircleShape))
                Text(value.uppercase(), style = if (big) MbTypography.balance else MbTypography.tileValue, color = valueColor)
                if (valueUnit != null) Text(valueUnit, style = MbTypography.meta.copy(fontSize = 15.sp, fontWeight = FontWeight.Medium), color = valueColor)
            }
        }
        if (subItems.isNotEmpty()) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                subItems.forEach { Text(it, style = MbTypography.rowSub, color = c.ink2) }
            }
        }
    }
}

/** Карточка с ведущим элементом (портрет или QR) — layout, содержимое `content` собирает вызывающая сторона. */
@Composable
fun MbCard(modifier: Modifier = Modifier, lead: @Composable () -> Unit, content: @Composable ColumnScope.() -> Unit) {
    val c = LocalMbColors.current
    Row(
        modifier = modifier
            .fillMaxWidth()
            .mbFrame(fill = c.plate2, edge = c.plateEdge, form = MbChamferForm.Std, cut = 8.dp)
            .padding(horizontal = 12.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        lead()
        Column(content = content)
    }
}

/** Портрет-буква в рамке с горизонтальной развёрткой; размеры гайдлайна — [MbDimens.portraitHeader]/Banner/Profile/Call. */
@Composable
fun MbPortrait(letter: String, modifier: Modifier = Modifier, size: Dp = MbDimens.portraitHeader, ink: Color = LocalMbColors.current.acc) {
    val cut = size * 0.15f
    Box(
        modifier = modifier
            .size(size)
            .mbFrame(fill = Color(0xFF0D1C26), edge = ink, form = MbChamferForm.Std, cut = cut)
            .drawBehind {
                val step = 3.dp.toPx()
                var x = -this.size.height
                while (x < this.size.width) {
                    drawLine(ink.copy(alpha = 0.08f), Offset(x, this.size.height), Offset(x + this.size.height, 0f), strokeWidth = 1.dp.toPx())
                    x += step
                }
            },
        contentAlignment = Alignment.Center
    ) {
        Text(letter, color = ink, style = TextStyle(fontFamily = FiraSansCondensed, fontWeight = FontWeight.Medium, fontSize = (size.value * 0.45f).sp))
    }
}

/** QR — тёмный узор на светлом фоне (иначе сканеры читают плохо), рамка `acc`. Притушенный показ по тапу — забота экрана (Профиль). */
@Composable
fun MbQr(bitmap: Bitmap, contentDescription: String, modifier: Modifier = Modifier, size: Dp = 112.dp) {
    Box(
        modifier = modifier
            .size(size)
            .mbFrame(fill = Color(0xFFE8F4F2), edge = LocalMbColors.current.acc, form = MbChamferForm.Std, cut = 10.dp)
            .padding(7.dp)
    ) {
        Image(bitmap = bitmap.asImageBitmap(), contentDescription = contentDescription, modifier = Modifier.fillMaxSize())
    }
}
