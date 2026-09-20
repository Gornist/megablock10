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
import com.megablok10.app.breach.DecryptRules
import com.megablok10.app.breach.Daemon
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.ui.theme.AppButton
import com.megablok10.app.ui.theme.ButtonVariant
import com.megablok10.app.ui.theme.ChamferedSurface
import com.megablok10.app.ui.theme.HexBullet
import com.megablok10.app.ui.theme.IBMPlexSans
import com.megablok10.app.ui.theme.JetBrainsMono
import com.megablok10.app.ui.theme.Jura
import com.megablok10.app.ui.theme.MB10Colors
import com.megablok10.app.ui.theme.chamferShape

internal enum class ShardBadge(val text: String, val color: Color) {
    Public("открыт", MB10Colors.inkSecondary),
    Locked("зашифрован", MB10Colors.accentNetrun),
    Fragment("фрагмент", MB10Colors.accentAction),
    Compromised("скомпрометирован", MB10Colors.accentDanger)
}

/**
 * Ярлык вычисляется из decryptAction+decrypted+tier, а не хранится отдельным
 * полем (ревизия v9) — раньше мастер мог задать badge и decryptAction
 * противоречиво (например "зашифрован" на шарде, который на деле открыт
 * сразу), теперь такого рассинхрона в принципе не может возникнуть.
 */
internal fun resolveBadge(shard: Mb10Qr.Shard): ShardBadge = when {
    shard.decryptAction && !shard.decrypted -> ShardBadge.Locked
    shard.tier <= 1 -> ShardBadge.Public
    shard.tier == 2 -> ShardBadge.Fragment
    else -> ShardBadge.Compromised
}

/**
 * Шарды теперь сегмент внутри общего экрана Кибердеки (CyberdeckScreen), а не
 * отдельный таб — сканирование ушло на общую кнопку "Сканировать объект"
 * наверху того экрана, здесь остались только карточка ряда и полноэкранный
 * оверлей чтения, переиспользуемые оттуда.
 */
@Composable
internal fun ShardCard(shard: Mb10Qr.Shard, onClick: () -> Unit) {
    val badge = remember(shard) { resolveBadge(shard) }
    ChamferedSurface(
        borderColor = MB10Colors.borderMuted,
        fillColor = MB10Colors.surfaceRaised,
        cut = 6.dp,
        contentPadding = 0.dp,
        modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp).clickable(onClick = onClick)
    ) {
        Column(Modifier.padding(11.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(shard.title, color = MB10Colors.inkPrimary, fontFamily = IBMPlexSans, fontSize = 13.5.sp, modifier = Modifier.weight(1f))
                Spacer(Modifier.width(8.dp))
                ShardBadgeChip(badge)
            }
            Spacer(Modifier.height(5.dp))
            Text(shard.meta, color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 11.sp)
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
        Text("+$amount €$", color = MB10Colors.accentAction, fontFamily = JetBrainsMono, fontSize = 11.sp, fontWeight = FontWeight.Medium)
    }
}

@Composable
internal fun ShardDetailOverlay(shard: Mb10Qr.Shard, decrypter: Daemon?, onClose: () -> Unit, onOpenHack: () -> Unit, onTransfer: () -> Unit) {
    val badge = remember(shard) { resolveBadge(shard) }
    Column(Modifier.fillMaxSize().background(MB10Colors.surfaceBase).padding(16.dp)) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth().clickable(onClick = onClose).padding(vertical = 6.dp)
        ) {
            Text("←", color = MB10Colors.inkPrimary, fontFamily = JetBrainsMono, fontSize = 16.sp)
            Spacer(Modifier.width(8.dp))
            Text("Назад к шардам", color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 11.sp)
        }
        Spacer(Modifier.height(16.dp))

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.Top
        ) {
            Text(
                shard.title,
                color = MB10Colors.inkPrimary, fontFamily = Jura, fontWeight = FontWeight.Bold, fontSize = 19.sp,
                modifier = Modifier.weight(1f)
            )
            Spacer(Modifier.width(8.dp))
            ShardBadgeChip(badge)
        }
        Spacer(Modifier.height(4.dp))
        Text(shard.meta, color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 11.sp)
        if (shard.valueHint.isNotEmpty()) {
            Spacer(Modifier.height(4.dp))
            Text(shard.valueHint, color = MB10Colors.inkTertiary, fontFamily = IBMPlexSans, fontSize = 11.sp)
        }
        if (shard.moneyAmount > 0) {
            Spacer(Modifier.height(8.dp))
            ShardMoneyRow(shard.moneyAmount)
        }
        Spacer(Modifier.height(16.dp))

        val locked = shard.decryptAction && !shard.decrypted
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
            if (locked) {
                Text(
                    if (decrypter != null) "Содержимое зашифровано. Дешифратор «${decrypter.name}» готов — взломайте шифр-замок, чтобы прочитать."
                    else "Содержимое зашифровано. Нужен демон-дешифратор тира ${shard.tier} или выше — в вашей коллекции такого нет.",
                    color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 12.sp, lineHeight = 18.sp
                )
                Spacer(Modifier.height(12.dp))
                Text(
                    DecryptRules.garble(shard.body, shard.id.hashCode().toLong()),
                    color = MB10Colors.inkTertiary, fontFamily = JetBrainsMono, fontSize = 12.sp, lineHeight = 18.sp
                )
            } else {
                Text(shard.body, color = MB10Colors.inkPrimary, fontFamily = IBMPlexSans, fontSize = 14.sp, lineHeight = 21.sp)
            }
            Spacer(Modifier.height(16.dp))
        }

        if (locked) {
            val enabled = decrypter != null
            val color = if (enabled) MB10Colors.accentNetrun else MB10Colors.inkTertiary
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .border(1.dp, color, chamferShape(6.dp))
                    .clickable(enabled = enabled, onClick = onOpenHack)
                    .padding(vertical = 10.dp)
            ) {
                Text(
                    if (enabled) "Расшифровать" else "Расшифровать (нужен дешифратор)",
                    color = color, fontFamily = JetBrainsMono, fontSize = 12.sp, fontWeight = FontWeight.Medium,
                    textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth()
                )
            }
            Spacer(Modifier.height(8.dp))
        }
        AppButton("Передать другому игроку", modifier = Modifier.fillMaxWidth(), variant = ButtonVariant.Secondary, onClick = onTransfer)
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
        Text(badge.text, color = badge.color, fontFamily = JetBrainsMono, fontSize = 11.sp)
    }
}
