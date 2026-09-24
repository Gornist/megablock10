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
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.megablok10.app.identity.Identity
import com.megablok10.app.ui.LocalAppGraph
import com.megablok10.app.ui.theme.ChamferedSurface
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
    val peers by LocalAppGraph.current.presence.peers.collectAsState()

    // Одна строка ~44 dp: позывной · фракция слева, узлы меш-сети справа. Раньше это были три строки и пунктир (≈104 dp).
    // Норма («узлы есть») — одна точка и число; текст нужен только когда связи нет — тогда он красный и заметен.
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onOpenProfile).padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(identity.callsign, color = MB10Colors.inkPrimary, fontFamily = Jura, fontWeight = FontWeight.Bold, fontSize = 17.sp, maxLines = 1)
        Spacer(Modifier.width(8.dp))
        ChamferedSurface(
            borderColor = MB10Colors.borderMuted,
            fillColor = MB10Colors.surfaceRaised,
            cut = 5.dp,
            contentPadding = 0.dp
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(5.dp),
                modifier = Modifier.padding(start = 6.dp, end = 8.dp, top = 2.dp, bottom = 2.dp)
            ) {
                HexBullet(MB10Colors.accentAction, size = 7.dp)
                Text(identity.faction, color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 11.sp, maxLines = 1)
            }
        }
        Spacer(Modifier.weight(1f))
        // Живой статус меш-сети — реальное число узлов из PresenceService (NSD-обнаружение), не заглушка.
        if (peers.isNotEmpty()) {
            HexBullet(MB10Colors.inkPrimary, size = 7.dp)
            Spacer(Modifier.width(5.dp))
            Text("${peers.size}", color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 12.sp)
        } else {
            HexBullet(MB10Colors.accentDanger, size = 7.dp)
            Spacer(Modifier.width(5.dp))
            Text("нет узлов", color = MB10Colors.accentDanger, fontFamily = JetBrainsMono, fontSize = 11.sp)
        }
    }
}

@Composable
fun AppTabBar(selected: AppTab, onSelect: (AppTab) -> Unit) {
    Column {
        DottedDivider()
        Row(Modifier.fillMaxWidth().background(MB10Colors.surfaceRaised)) {
            AppTab.entries.forEach { tab ->
                val active = tab == selected
                // inkFaint (тёмно-коричневый) на bg1 (тёмно-синий) почти неразличимы — оба
                // около-чёрные с разным подтоном. Приглушённый ink0 вместо этого читается
                // как "тусклый циан", а не как отдельный несвязанный оттенок.
                val color = if (active) MB10Colors.accentAction else MB10Colors.inkPrimary.copy(alpha = 0.35f)
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .clickable { onSelect(tab) }
                        .padding(top = 6.dp, bottom = 5.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    when (tab) {
                        AppTab.Chat -> ChatTabIcon(color)
                        AppTab.Calls -> CallsTabIcon(color)
                        AppTab.Hack -> HackTabIcon(color)
                        AppTab.Wallet -> WalletTabIcon(color)
                    }
                    Spacer(Modifier.height(2.dp))
                    Text(tab.label, color = color, fontFamily = JetBrainsMono, fontSize = 11.sp)
                }
            }
        }
    }
}

/**
 * hideChrome — вложенный экран внутри таба (тред чата, деталь шарда) сам
 * несёт свой back-заголовок; шапка приложения и таббар над ним были бы
 * вторым, конкурирующим заголовком и второй "точкой выхода" одновременно.
 * Таб, который сейчас активен, сам решает, когда он "вложен" — MainScaffold
 * только прячет/показывает chrome по этому единственному флагу.
 */
@Composable
fun MainScaffold(
    identity: Identity,
    selectedTab: AppTab,
    onSelectTab: (AppTab) -> Unit,
    onOpenProfile: () -> Unit = {},
    hideChrome: Boolean = false,
    content: @Composable (AppTab) -> Unit
) {
    Column(Modifier.fillMaxSize().background(MB10Colors.surfaceBase)) {
        if (!hideChrome) AppHeader(identity, onOpenProfile)
        // Состояние rememberSaveable каждой вкладки (сегмент Кибердеки и т. п.) переживает переключение вкладок.
        val stateHolder = rememberSaveableStateHolder()
        Box(Modifier.weight(1f)) {
            stateHolder.SaveableStateProvider(selectedTab.name) { content(selectedTab) }
        }
        if (!hideChrome) AppTabBar(selected = selectedTab, onSelect = onSelectTab)
    }
}
