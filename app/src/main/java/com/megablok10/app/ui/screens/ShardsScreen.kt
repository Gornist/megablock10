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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.ui.theme.ChamferedPanel
import com.megablok10.app.ui.theme.HexBullet
import com.megablok10.app.ui.theme.IBMPlexSans
import com.megablok10.app.ui.theme.JetBrainsMono
import com.megablok10.app.ui.theme.Jura
import com.megablok10.app.ui.theme.MB10Colors
import com.megablok10.app.ui.theme.chamferShape

internal enum class ShardBadge(val text: String, val color: Color) {
    Public("открыт", MB10Colors.inkMuted),
    Locked("зашифрован", MB10Colors.accentHack),
    Fragment("фрагмент", MB10Colors.accentPrimary),
    Compromised("скомпрометирован", MB10Colors.danger)
}

internal fun resolveBadge(raw: String): ShardBadge =
    ShardBadge.entries.find { it.name.equals(raw, ignoreCase = true) } ?: ShardBadge.Public

/**
 * Шарды теперь сегмент внутри общего экрана Кибердеки (CyberdeckScreen), а не
 * отдельный таб — сканирование ушло на общую кнопку "Сканировать объект"
 * наверху того экрана, здесь остались только карточка ряда и полноэкранный
 * оверлей чтения, переиспользуемые оттуда.
 */
@Composable
internal fun ShardCard(shard: Mb10Qr.Shard, onClick: () -> Unit) {
    val badge = remember(shard.badge) { resolveBadge(shard.badge) }
    ChamferedPanel(
        borderColor = MB10Colors.inkFaint,
        fillColor = MB10Colors.bg1,
        cut = 6.dp,
        contentPadding = 0.dp,
        modifier = Modifier.fillMaxWidth().padding(bottom = 12.dp).clickable(onClick = onClick)
    ) {
        Column(Modifier.padding(11.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(shard.title, color = MB10Colors.ink0, fontFamily = IBMPlexSans, fontSize = 13.5.sp, modifier = Modifier.weight(1f))
                Spacer(Modifier.width(8.dp))
                ShardBadgeChip(badge)
            }
            Spacer(Modifier.height(5.dp))
            Text(shard.meta, color = MB10Colors.inkMuted, fontFamily = JetBrainsMono, fontSize = 10.sp)
            if (shard.moneyAmount > 0) {
                Spacer(Modifier.height(5.dp))
                ShardMoneyRow(shard.moneyAmount)
            }
        }
    }
}

/** Деньги уже зачислены в момент скана — это не кнопка, а подтверждение находки. */
@Composable
private fun ShardMoneyRow(amount: Long) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        HexBullet(MB10Colors.accentAction, size = 7.dp)
        Spacer(Modifier.width(6.dp))
        Text("+$amount €$", color = MB10Colors.accentAction, fontFamily = JetBrainsMono, fontSize = 10.5.sp, fontWeight = FontWeight.Medium)
    }
}

@Composable
internal fun ShardDetailOverlay(shard: Mb10Qr.Shard, onClose: () -> Unit, onOpenHack: () -> Unit) {
    val badge = remember(shard.badge) { resolveBadge(shard.badge) }
    Column(Modifier.fillMaxSize().background(MB10Colors.bg0).padding(16.dp)) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth().clickable(onClick = onClose).padding(vertical = 6.dp)
        ) {
            Text("←", color = MB10Colors.ink0, fontFamily = JetBrainsMono, fontSize = 16.sp)
            Spacer(Modifier.width(8.dp))
            Text("Назад к шардам", color = MB10Colors.inkMuted, fontFamily = JetBrainsMono, fontSize = 11.sp)
        }
        Spacer(Modifier.height(16.dp))

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.Top
        ) {
            Text(
                shard.title,
                color = MB10Colors.ink0, fontFamily = Jura, fontWeight = FontWeight.Bold, fontSize = 19.sp,
                modifier = Modifier.weight(1f)
            )
            Spacer(Modifier.width(8.dp))
            ShardBadgeChip(badge)
        }
        Spacer(Modifier.height(4.dp))
        Text(shard.meta, color = MB10Colors.inkMuted, fontFamily = JetBrainsMono, fontSize = 10.5.sp)
        if (shard.moneyAmount > 0) {
            Spacer(Modifier.height(8.dp))
            ShardMoneyRow(shard.moneyAmount)
        }
        Spacer(Modifier.height(16.dp))

        Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
            Text(shard.body, color = MB10Colors.ink0, fontFamily = IBMPlexSans, fontSize = 14.sp, lineHeight = 21.sp)
            Spacer(Modifier.height(16.dp))
        }

        if (shard.decryptAction) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .border(1.dp, MB10Colors.accentHack, chamferShape(6.dp))
                    .clickable(onClick = onOpenHack)
                    .padding(vertical = 10.dp)
            ) {
                Text(
                    "Расшифровать",
                    color = MB10Colors.accentHack, fontFamily = JetBrainsMono, fontSize = 12.sp, fontWeight = FontWeight.Medium,
                    textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth()
                )
            }
        }
    }
}

@Composable
private fun ShardBadgeChip(badge: ShardBadge) {
    // Не через общий Chip: здесь текст всегда в полную яркость, а приглушена
    // только рамка/заливка — нюанс, которого нет у других чипов в приложении.
    Box(
        modifier = Modifier
            .background(badge.color.copy(alpha = 0.08f), chamferShape(4.dp))
            .border(1.dp, badge.color.copy(alpha = if (badge == ShardBadge.Public) 1f else 0.4f), chamferShape(4.dp))
            .padding(horizontal = 7.dp, vertical = 2.dp)
    ) {
        Text(badge.text, color = badge.color, fontFamily = JetBrainsMono, fontSize = 9.5.sp)
    }
}
