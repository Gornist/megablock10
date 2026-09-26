package com.megablok10.app.ui.theme

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp

/** Один пункт нижнего меню: иконка, подпись (видна только у активного) и число непрочитанного/пропущенного. */
class MbNavItem(val id: String, val icon: Int, val label: String, val badge: Int = 0)

/**
 * Оболочка приложения (раздел 5 гайдлайна): шапка (портрет → профиль, позывной, фракция, €$, узлы) скрывается на
 * вложенных экранах ([header] = false — там заголовок даёт `MbBreadcrumb`), нижнее меню — всегда (так в прототипе,
 * даже на экране взлома). Системные отступы (edge-to-edge) — здесь; сама Activity ещё не включает edge-to-edge
 * глобально (M5, когда все экраны перенесены — иначе старые непереехавшие экраны полезут под системные панели).
 */
@Composable
fun MbAppShell(
    items: List<MbNavItem>,
    selectedId: String?,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier,
    header: Boolean = true,
    portraitLetter: String = "",
    callsign: String = "",
    faction: String = "",
    balance: String = "",
    onlineNodes: Int = 0,
    onOpenProfile: () -> Unit = {},
    overlay: (@Composable BoxScope.() -> Unit)? = null,
    content: @Composable () -> Unit
) {
    val c = LocalMbColors.current
    Box(modifier.fillMaxSize().background(c.bg)) {
        Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.statusBars)) {
            if (header) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable(onClick = onOpenProfile)
                        .drawBehind {
                            drawLine(c.chrome, Offset(10.dp.toPx(), size.height), Offset(size.width - 10.dp.toPx(), size.height), strokeWidth = 1.dp.toPx())
                        }
                        .padding(horizontal = 10.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(9.dp)
                ) {
                    MbPortrait(portraitLetter, size = MbDimens.portraitHeader, ink = c.chrome)
                    Column(Modifier.weight(1f)) {
                        Text(callsign.uppercase(), style = MbTypography.headerCallsign, color = c.ink)
                        Text(faction, style = MbTypography.meta.copy(letterSpacing = 0.05f.em), color = c.chrome.copy(alpha = 0.85f))
                    }
                    Text(
                        balance,
                        style = MbTypography.meta.copy(fontSize = 11.sp, letterSpacing = 0.04f.em, fontWeight = FontWeight.SemiBold),
                        color = c.money
                    )
                    // Прототип рисует чип только «в сети» (зелёный) — ноль узлов (игрок изолирован от меш-сети) он не
                    // показывает вовсе, но это реальный и важный для игрока случай (было отдельным красным текстом в
                    // старой шапке, AppShell.kt): здесь тот же чип переключается на bad, а не тихо остаётся зелёным.
                    val nodesTone = if (onlineNodes > 0) c.ok else c.bad
                    Row(
                        modifier = Modifier
                            .mbFrame(fill = c.bg, edge = nodesTone, form = MbChamferForm.Tab, cut = 4.dp)
                            .padding(horizontal = 8.dp, vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Box(Modifier.size(6.dp).background(nodesTone, CircleShape))
                        Text("$onlineNodes УЗЛОВ", style = MbTypography.metaStatus.copy(letterSpacing = 0.06f.em), color = nodesTone)
                    }
                }
            }
            Box(Modifier.weight(1f)) { content() }
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .windowInsetsPadding(WindowInsets.navigationBars)
                    .padding(horizontal = 8.dp)
                    .padding(bottom = 10.dp, top = 4.dp)
            ) {
                items.forEach { item ->
                    val on = item.id == selectedId
                    val lineColor = if (on) c.acc else c.navLine
                    val iconColor = if (on) c.acc else c.navIdle
                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .heightIn(min = MbDimens.bottomMenuHeight)
                            .clickable { onSelect(item.id) }
                            .drawBehind { drawLine(lineColor, Offset(0f, size.height), Offset(size.width, size.height), strokeWidth = 3.dp.toPx()) }
                            .padding(top = 6.dp, bottom = 5.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Box {
                            Icon(
                                painterResource(item.icon),
                                contentDescription = "${item.label}${if (item.badge > 0) ", новых: ${item.badge}" else ""}",
                                tint = iconColor,
                                modifier = Modifier.size(24.dp)
                            )
                            if (item.badge > 0 && !on) {
                                Box(
                                    modifier = Modifier
                                        .align(Alignment.TopEnd)
                                        .padding(start = 15.dp)
                                        .defaultMinSize(minWidth = 17.dp, minHeight = 17.dp)
                                        .mbFrame(fill = c.money, edge = c.money, form = MbChamferForm.Tab, cut = 4.dp)
                                        .padding(horizontal = 4.dp),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Text("${item.badge}", style = MbTypography.tagLabel, color = c.onMoney)
                                }
                            }
                        }
                        if (on) {
                            Spacer(Modifier.size(3.dp))
                            Text(item.label.uppercase(), style = MbTypography.menuLabel, color = c.acc)
                        }
                    }
                }
            }
        }
        if (overlay != null) Box(Modifier.fillMaxSize(), content = overlay)
    }
}
