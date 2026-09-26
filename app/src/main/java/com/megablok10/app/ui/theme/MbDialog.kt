package com.megablok10.app.ui.theme

import androidx.annotation.DrawableRes
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.ProvideTextStyle
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog

enum class MbDialogTone { Default, Danger }

class MbDialogAction(val text: String, val kind: MbButtonKind, @DrawableRes val keyIcon: Int? = null, val onClick: () -> Unit)

/**
 * Видимая карточка окна без popup-окна ОС — то, что реально рисуется на экране. Отдельно от [MbDialog], чтобы
 * каталог/скриншот-тест мог снять её как обычный composable (Paparazzi не снимает содержимое настоящего [Dialog]).
 */
@Composable
fun MbDialogCard(
    icon: Int,
    title: String,
    modifier: Modifier = Modifier,
    tone: MbDialogTone = MbDialogTone.Default,
    actions: List<MbDialogAction> = emptyList(),
    wideActions: Boolean = false,
    body: @Composable ColumnScope.() -> Unit
) {
    val c = LocalMbColors.current
    val fill: Color; val edge: Color; val bar: Color; val rule: Color; val head: Color; val ink: Color
    if (tone == MbDialogTone.Danger) {
        fill = Color(0xFF3A1113); edge = c.bad; bar = Color(0xFF8E2320)
        rule = Color(0xFF6B2226); head = Color(0xFFFFB3AB); ink = Color(0xFFFFE3DF)
    } else {
        fill = c.dlgFill; edge = c.dlgEdge; bar = c.dlgBar
        rule = Color(0xFF1F4550); head = Color(0xFF7FE6F2); ink = Color(0xFFBFE9E6)
    }
    Column(modifier) {
        Box(Modifier.mbFrame(fill = fill, edge = edge, form = MbChamferForm.Dlg, cut = 12.dp)) {
            Box(Modifier.fillMaxHeight().width(7.dp).background(bar).align(Alignment.CenterStart))
            Column(Modifier.padding(start = 16.dp, bottom = 12.dp)) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .drawBehind { drawLine(rule, Offset(0f, size.height), Offset(size.width, size.height), strokeWidth = 1.dp.toPx()) }
                        .padding(start = 2.dp, top = 11.dp, end = 12.dp, bottom = 9.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(painterResource(icon), contentDescription = null, tint = c.money, modifier = Modifier.size(18.dp))
                    Text(title.uppercase(), style = MbTypography.listItemTitle.copy(fontSize = 13.sp, letterSpacing = 0.05f.em), color = head)
                }
                Column(
                    modifier = Modifier.padding(start = 2.dp, top = 9.dp, end = 14.dp),
                    verticalArrangement = Arrangement.spacedBy(5.dp)
                ) {
                    CompositionLocalProvider(LocalContentColor provides ink) {
                        ProvideTextStyle(MbTypography.dialogText.copy(color = ink)) { body() }
                    }
                }
            }
        }
        if (actions.isNotEmpty()) {
            Spacer(Modifier.height(8.dp))
            if (wideActions) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    actions.forEach { a ->
                        MbButton(a.text, a.onClick, Modifier.weight(1f), kind = a.kind, keyIcon = a.keyIcon)
                    }
                }
            } else {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.End)) {
                    actions.forEach { a ->
                        MbButton(a.text, a.onClick, Modifier.wrapContentWidth(), kind = a.kind, keyIcon = a.keyIcon, inline = true)
                    }
                }
            }
        }
    }
}

/** Одно окно на всё: объявление мастера, чтение шарда, входящий звонок, подтверждение перевода (tone = Danger). */
@Composable
fun MbDialog(
    onDismissRequest: () -> Unit,
    icon: Int,
    title: String,
    modifier: Modifier = Modifier,
    tone: MbDialogTone = MbDialogTone.Default,
    actions: List<MbDialogAction> = emptyList(),
    wideActions: Boolean = false,
    body: @Composable ColumnScope.() -> Unit
) {
    Dialog(onDismissRequest = onDismissRequest) {
        MbDialogCard(icon, title, modifier, tone, actions, wideActions, body)
    }
}

enum class MbBannerTone { Ok, Danger }

/** Плашка сверху содержимого — для того, что идёт сейчас: разговор (ok) или потеря связи (danger). */
@Composable
fun MbBanner(
    lead: @Composable () -> Unit,
    title: String,
    sub: String,
    modifier: Modifier = Modifier,
    tone: MbBannerTone = MbBannerTone.Ok,
    action: (@Composable () -> Unit)? = null
) {
    val c = LocalMbColors.current
    val fill = if (tone == MbBannerTone.Danger) Color(0xFF2A0E10) else Color(0xFF0A1A17)
    val edge = if (tone == MbBannerTone.Danger) c.bad else c.ok
    val titleColor = if (tone == MbBannerTone.Danger) Color(0xFFFFE3DF) else Color(0xFFE6FFF1)
    val subColor = if (tone == MbBannerTone.Danger) Color(0xFFFFB3AB) else c.ok
    Row(
        modifier = modifier
            .fillMaxWidth()
            .mbFrame(fill = fill, edge = edge, form = MbChamferForm.Std, cut = 8.dp)
            .padding(start = 10.dp, end = 8.dp, top = 7.dp, bottom = 7.dp),
        horizontalArrangement = Arrangement.spacedBy(9.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        lead()
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(title.uppercase(), style = MbTypography.tab.copy(letterSpacing = 0.04f.em), color = titleColor)
            Text(sub.uppercase(), style = MbTypography.meta.copy(letterSpacing = 0.06f.em), color = subColor)
        }
        if (action != null) action()
    }
}
