package com.megablok10.app.ui.nav

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.megablok10.app.identity.Identity
import com.megablok10.app.ui.theme.ChamferedPanel
import com.megablok10.app.ui.theme.DottedDivider
import com.megablok10.app.ui.theme.HexBullet
import com.megablok10.app.ui.theme.Jura
import com.megablok10.app.ui.theme.JetBrainsMono
import com.megablok10.app.ui.theme.MB10Colors

enum class AppTab(val label: String) {
    Chat("Чат"),
    Calls("Звонки"),
    Hack("Кибердека"),
    Wallet("Финансы")
}

/**
 * Шапка приложения — позывной, фракция. Позывной+фракция — ещё и вход в
 * Профиль (Профиль/Настройки больше не таб, а экран за аватаром, как в
 * обычных мессенджерах).
 *
 * Раньше здесь же был баннер "карантин, 3ч 12м с изоляции" — убран: текст
 * утверждал "обновляется вручную мастером", но в Мастерской нет и не было
 * ни одного поля, которым мастер мог бы это обновить — обновить можно было
 * только правкой исходников. Просто застывший текст на каждом экране
 * приложения, ничего не сообщающий.
 */
@Composable
fun AppHeader(identity: Identity, onOpenProfile: () -> Unit = {}) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth().clickable(onClick = onOpenProfile),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(identity.callsign, color = MB10Colors.ink0, fontFamily = Jura, fontWeight = FontWeight.Bold, fontSize = 19.sp)
            ChamferedPanel(
                borderColor = MB10Colors.inkFaint,
                fillColor = MB10Colors.bg1,
                cut = 6.dp,
                contentPadding = 0.dp
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    modifier = Modifier.padding(start = 6.dp, end = 8.dp, top = 3.dp, bottom = 3.dp)
                ) {
                    HexBullet(MB10Colors.accentPrimary, size = 8.dp)
                    Text(identity.faction, color = MB10Colors.inkMuted, fontFamily = JetBrainsMono, fontSize = 10.sp)
                }
            }
        }
    }
    DottedDivider()
}

@Composable
fun AppTabBar(selected: AppTab, onSelect: (AppTab) -> Unit) {
    Column {
        DottedDivider()
        Row(Modifier.fillMaxWidth().background(MB10Colors.bg1)) {
            AppTab.entries.forEach { tab ->
                val active = tab == selected
                // inkFaint (тёмно-коричневый) на bg1 (тёмно-синий) почти неразличимы — оба
                // около-чёрные с разным подтоном. Приглушённый ink0 вместо этого читается
                // как "тусклый циан", а не как отдельный несвязанный оттенок.
                val color = if (active) MB10Colors.accentPrimary else MB10Colors.ink0.copy(alpha = 0.35f)
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .clickable { onSelect(tab) }
                        .padding(top = 9.dp, bottom = 8.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    when (tab) {
                        AppTab.Chat -> ChatTabIcon(color)
                        AppTab.Calls -> CallsTabIcon(color)
                        AppTab.Hack -> HackTabIcon(color)
                        AppTab.Wallet -> WalletTabIcon(color)
                    }
                    Spacer(Modifier.height(4.dp))
                    Text(tab.label, color = color, fontFamily = JetBrainsMono, fontSize = 9.sp)
                }
            }
        }
    }
}

@Composable
fun MainScaffold(
    identity: Identity,
    selectedTab: AppTab,
    onSelectTab: (AppTab) -> Unit,
    onOpenProfile: () -> Unit = {},
    content: @Composable (AppTab) -> Unit
) {
    Column(Modifier.fillMaxSize().background(MB10Colors.bg0)) {
        AppHeader(identity, onOpenProfile)
        Box(Modifier.weight(1f)) {
            content(selectedTab)
        }
        AppTabBar(selected = selectedTab, onSelect = onSelectTab)
    }
}
