package com.megablok10.app.ui.screens

import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import com.megablok10.app.breach.DecryptRules
import com.megablok10.app.breach.Daemon
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.ui.theme.LocalMbColors
import com.megablok10.app.ui.theme.MbButtonKind
import com.megablok10.app.ui.theme.MbDialog
import com.megablok10.app.ui.theme.MbDialogAction
import com.megablok10.app.ui.theme.MbDimens
import com.megablok10.app.ui.theme.MbIcons
import com.megablok10.app.ui.theme.MbTypography
import com.megablok10.app.ui.theme.formatMoney

internal enum class ShardBadge(val text: String) {
    Public("открыт"),
    Locked("зашифрован"),
    Fragment("фрагмент"),
    Compromised("скомпрометирован")
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
 * Шард читается только в окне (раздел 5 гайдлайна), не блоком под списком — реальный MbDialog (не карточка), чтобы
 * не перехватывать нажатия у списка под ним. «Расшифровать» открывает мини-взлом этого конкретного шарда
 * (ShardDecryptFlow в CyberdeckScreen), а не общий сегмент «Демоны».
 */
@Composable
internal fun ShardDetailDialog(shard: Mb10Qr.Shard, decrypter: Daemon?, onClose: () -> Unit, onOpenHack: () -> Unit, onTransfer: () -> Unit) {
    val c = LocalMbColors.current
    val locked = shard.decryptAction && !shard.decrypted
    val secondAction = if (locked) {
        if (decrypter != null) MbDialogAction("Расшифровать", MbButtonKind.Quiet, MbIcons.Hack, onOpenHack) else null
    } else {
        MbDialogAction("Передать", MbButtonKind.Quiet, onClick = onTransfer)
    }
    MbDialog(
        onDismissRequest = onClose,
        icon = MbIcons.Shard,
        title = "Шард · ${shard.title}",
        actions = listOfNotNull(MbDialogAction("Закрыть", MbButtonKind.Quiet, onClick = onClose), secondAction),
        wideActions = secondAction != null
    ) {
        if (shard.meta.isNotEmpty()) Text(shard.meta, style = MbTypography.meta, color = c.ink3)
        if (shard.moneyAmount > 0) Text("+${formatMoney(shard.moneyAmount)}", style = MbTypography.dialogText, color = c.ok)
        Spacer(Modifier.height(MbDimens.rowGap))
        if (locked) {
            Text(
                if (decrypter != null) "Содержимое зашифровано. Дешифратор «${decrypter.name}» готов — взломайте шифр-замок, чтобы прочитать."
                else "Содержимое зашифровано. Нужен демон-дешифратор тира ${shard.tier} или выше — в вашей коллекции такого нет.",
                style = MbTypography.dialogText
            )
            Spacer(Modifier.height(MbDimens.rowGap))
            Text(
                remember(shard) { DecryptRules.garble(shard.body, shard.id.hashCode().toLong()) },
                style = MbTypography.meta,
                color = c.ink3
            )
        } else {
            Text(shard.body, style = MbTypography.dialogText)
            if (shard.valueHint.isNotEmpty()) {
                Spacer(Modifier.height(MbDimens.rowGap))
                Text(shard.valueHint, style = MbTypography.meta, color = c.ink3)
            }
        }
    }
}
