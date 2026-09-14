package com.megablok10.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.megablok10.app.ui.theme.ChamferedPanel
import com.megablok10.app.ui.theme.IBMPlexSans
import com.megablok10.app.ui.theme.JetBrainsMono
import com.megablok10.app.ui.theme.MB10Colors
import com.megablok10.app.ui.theme.chamferShape

private enum class ShardBadge(val text: String, val color: Color) {
    Public("открыт", MB10Colors.inkMuted),
    Locked("зашифрован", MB10Colors.lime),
    Fragment("фрагмент 1/3", MB10Colors.yellow),
    Compromised("скомпрометирован", MB10Colors.red)
}

private data class DemoShard(
    val title: String,
    val badge: ShardBadge,
    val meta: String,
    val body: String,
    val decryptAction: Boolean = false
)

/** Демо-данные из HTML-макета — реальный Container/Shard появится на этапе "Контейнеры и лут". */
private val demoShards = listOf(
    DemoShard(
        "Отчёт техника: партия хладагента",
        ShardBadge.Public,
        "получен 20:41 · техэтаж",
        "«...партия С-9 пришла с браком клапана ещё в среду, я докладывал наверх, ответа не было...»"
    ),
    DemoShard(
        "Служебный лог клиники",
        ShardBadge.Locked,
        "получен 21:02 · клиника, уровень доступа 2",
        "Содержимое скрыто. Требуется взлом точки доступа для расшифровки.",
        decryptAction = true
    ),
    DemoShard(
        "Радиоперехват — Клемты",
        ShardBadge.Fragment,
        "получен 20:15 · техэтаж",
        "Собрано 1 из 3 фрагментов. Остальные части — у других игроков или в других локациях."
    ),
    DemoShard(
        "Записка охраны рынка",
        ShardBadge.Compromised,
        "впервые открыт Игрок_04 в 20:58",
        "Этот шард уже читал другой игрок — расчитывать на эксклюзив информации не стоит."
    )
)

@Composable
fun ShardsScreen(onOpenHack: () -> Unit) {
    Column(Modifier.fillMaxSize().padding(16.dp)) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .background(MB10Colors.lime, chamferShape(6.dp))
                .padding(vertical = 10.dp),
        ) {
            Text(
                "Сканировать QR-шард",
                color = Color(0xFF0A0A00),
                fontFamily = JetBrainsMono,
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium,
                modifier = Modifier.fillMaxWidth(),
                textAlign = androidx.compose.ui.text.style.TextAlign.Center
            )
        }
        Spacer(Modifier.height(16.dp))

        LazyColumn {
            items(demoShards) { shard -> ShardCard(shard, onOpenHack) }
        }
    }
}

@Composable
private fun ShardCard(shard: DemoShard, onOpenHack: () -> Unit) {
    ChamferedPanel(
        borderColor = MB10Colors.inkFaint,
        fillColor = MB10Colors.bg1,
        cut = 6.dp,
        contentPadding = 0.dp,
        modifier = Modifier.fillMaxWidth().padding(bottom = 12.dp)
    ) {
        Column(Modifier.padding(11.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(shard.title, color = MB10Colors.ink0, fontFamily = IBMPlexSans, fontSize = 13.5.sp, modifier = Modifier.weight(1f))
                Spacer(Modifier.width(8.dp))
                ShardBadgeChip(shard.badge)
            }
            Spacer(Modifier.height(5.dp))
            Text(shard.meta, color = MB10Colors.inkMuted, fontFamily = JetBrainsMono, fontSize = 10.sp)
            Spacer(Modifier.height(6.dp))
            Text(shard.body, color = MB10Colors.inkMuted, fontFamily = IBMPlexSans, fontSize = 12.5.sp, lineHeight = 17.sp)
            if (shard.decryptAction) {
                Spacer(Modifier.height(8.dp))
                Box(
                    modifier = Modifier
                        .border(1.dp, MB10Colors.lime, chamferShape(5.dp))
                        .clickable(onClick = onOpenHack)
                        .padding(horizontal = 10.dp, vertical = 6.dp)
                ) {
                    Text("Расшифровать", color = MB10Colors.lime, fontFamily = JetBrainsMono, fontSize = 11.sp)
                }
            }
        }
    }
}

@Composable
private fun ShardBadgeChip(badge: ShardBadge) {
    Box(
        modifier = Modifier
            .background(badge.color.copy(alpha = 0.08f), chamferShape(4.dp))
            .border(1.dp, badge.color.copy(alpha = if (badge == ShardBadge.Public) 1f else 0.4f), chamferShape(4.dp))
            .padding(horizontal = 7.dp, vertical = 2.dp)
    ) {
        Text(badge.text, color = badge.color, fontFamily = JetBrainsMono, fontSize = 9.5.sp)
    }
}
