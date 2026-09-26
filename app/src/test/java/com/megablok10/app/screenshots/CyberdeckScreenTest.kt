package com.megablok10.app.screenshots

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import com.megablok10.app.breach.Daemon
import com.megablok10.app.breach.DaemonEffect
import com.megablok10.app.breach.Tier
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.ui.screens.ShardDetailDialog
import com.megablok10.app.ui.theme.LocalMbColors
import com.megablok10.app.ui.theme.MbColorsDefault
import com.megablok10.app.ui.theme.MbEmptyState
import com.megablok10.app.ui.theme.MbIcons
import com.megablok10.app.ui.theme.MbListItem
import com.megablok10.app.ui.theme.MbTag
import com.megablok10.app.ui.theme.MbTagTone
import com.megablok10.app.ui.theme.MbTypography
import org.junit.Rule
import org.junit.Test

/** M4.4 плана миграции: Кибердека (демоны, шарды, диалог чтения) — фейковые данные. */
class CyberdeckScreenTest {
    @get:Rule
    val paparazzi = Paparazzi(deviceConfig = DeviceConfig.PIXEL_5.copy(softButtons = false), maxPercentDifference = 0.5)

    private fun snap(name: String, content: @Composable () -> Unit) {
        paparazzi.snapshot(name) {
            CompositionLocalProvider(LocalMbColors provides MbColorsDefault) {
                Box(Modifier.background(MbColorsDefault.bg).padding(10.dp)) {
                    Column { content() }
                }
            }
        }
    }

    private fun shard(title: String, meta: String, tier: Int, decryptAction: Boolean = false, decrypted: Boolean = false, money: Long = 0) =
        Mb10Qr.Shard(id = title, title = title, meta = meta, valueHint = "", body = "тело", tier = tier, decryptAction = decryptAction, decrypted = decrypted, moneyAmount = money)

    @Test
    fun daemonList() = snap("cyberdeck_daemons") {
        MbListItem(
            title = "Призрак · ${Tier.HARD.label}", sub = "убирает ваш ID из сигнала СБ · 3 ячейки", subWrap = true,
            trail = listOf({ androidx.compose.material3.Text("1C BD 55", style = MbTypography.demonCode, color = LocalMbColors.current.acc) }),
            plate = true
        )
        MbListItem(
            title = "Перекос · ${Tier.BASE.label}", sub = "+10 мин к задержке сигнала СБ · 2 ячейки", subWrap = true,
            trail = listOf({ androidx.compose.material3.Text("E9 7A", style = MbTypography.demonCode, color = LocalMbColors.current.acc) }),
            plate = true
        )
    }

    @Test
    fun shardList() = snap("cyberdeck_shards") {
        MbListItem(title = "Письмо Шептуну", trail = listOf({ MbTag("новый", filled = true) }), plate = true, mark = true)
        MbListItem(title = "Карта доступа · фрагмент 1/3 из сейфа диспетчерской", titleWrap = true, plate = true, mark = true)
        MbListItem(title = "Накладная склада 12", trail = listOf({ MbTag("нужен дешифратор", tone = MbTagTone.Warn) }), plate = true, mark = true)
    }

    @Test
    fun emptyState() = snap("cyberdeck_empty") {
        MbEmptyState(MbIcons.Shard, "Шардов пока нет", "Отсканируйте QR-метку контейнера — найденные шарды появятся здесь.")
    }

    @Test
    fun shardDialogLocked() = snap("cyberdeck_shard_dialog_locked") {
        ShardDetailDialog(
            shard = shard("Накладная склада 12", "Тир 2 · открыт из сейфа", tier = 2, decryptAction = true, decrypted = false),
            decrypter = Daemon("d1", "Дешифратор", listOf("BD", "BD", "1C", "55"), tier = Tier.HARD, effect = DaemonEffect.DECRYPT),
            onClose = {}, onOpenHack = {}, onTransfer = {}
        )
    }
}
