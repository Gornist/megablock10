package com.megablok10.app.ui.screens

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import com.megablok10.app.breach.Daemon
import com.megablok10.app.breach.DaemonPicker
import com.megablok10.app.items.ItemTransferStore
import com.megablok10.app.netrun.NetrunEntryState
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.ui.theme.LocalMbColors
import com.megablok10.app.ui.theme.MbBanner
import com.megablok10.app.ui.theme.MbBannerTone
import com.megablok10.app.ui.theme.MbBreadcrumb
import com.megablok10.app.ui.theme.MbBuffer
import com.megablok10.app.ui.theme.MbButton
import com.megablok10.app.ui.theme.MbButtonKind
import com.megablok10.app.ui.theme.MbDialog
import com.megablok10.app.ui.theme.MbDialogAction
import com.megablok10.app.ui.theme.MbDimens
import com.megablok10.app.ui.theme.MbEmptyState
import com.megablok10.app.ui.theme.MbIconButton
import com.megablok10.app.ui.theme.MbIcons
import com.megablok10.app.ui.theme.MbListItem
import com.megablok10.app.ui.theme.MbPanel
import com.megablok10.app.ui.theme.MbProgress
import com.megablok10.app.ui.theme.MbSectionTitle
import com.megablok10.app.ui.theme.MbTag
import com.megablok10.app.ui.theme.MbTypography

/** Название стойки для игрока: «стойка t03» (подпись из QR — отдельной строкой, если есть). */
fun rackTitle(rack: Mb10Qr.Rack): String = rack.label.ifBlank { "Стойка ${rack.terminal}" }

/**
 * Выбор деки перед входом в «Сеть»: демоны из коллекции в пределах RAM и один из выбранных — в защищённый слот (он возвращается
 * на телефон при любом исходе). Состояние — снаружи ([chosen], [protectedId]); подтверждение — окно «Войти в Сеть?».
 */
@Composable
fun NetrunDeckPicker(
    rack: Mb10Qr.Rack,
    daemons: List<Daemon>,
    ramCapacity: Int,
    chosen: Set<String>,
    protectedId: String?,
    onToggle: (String) -> Unit,
    onProtect: (String) -> Unit,
    onEnter: () -> Unit,
    onCancel: () -> Unit,
) {
    val eligible = daemons.filter { ItemTransferStore.isTransferable(it) }
    val picked = eligible.filter { it.id in chosen }
    val used = picked.sumOf { it.sequence.size }
    val canEnter = picked.isNotEmpty() && used <= ramCapacity && picked.any { it.id == protectedId }
    var confirming by remember { mutableStateOf(false) }

    Column(Modifier.fillMaxSize().padding(horizontal = MbDimens.screenPadding)) {
        MbBreadcrumb(parts = listOf("Кибердека", rackTitle(rack)), icon = MbIcons.Hack) {
            MbIconButton(MbIcons.Close, "Отмена", onCancel)
        }
        Spacer(Modifier.height(MbDimens.blockGap))
        MbPanel("Дека", meta = "$used / $ramCapacity" + if (used > ramCapacity) " — снимите демон" else "") {
            MbBuffer(codes = picked.flatMap { it.sequence }, size = ramCapacity)
        }
        Spacer(Modifier.height(MbDimens.blockGap))
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
            if (eligible.isEmpty()) {
                MbEmptyState(MbIcons.Hack, "Нечего сдавать", "Стартового демона в Сеть не отдать. Добудьте демонов, взломав контейнеры.")
            } else {
                DaemonPicker(daemons = eligible, chosen = chosen, remainingBuffer = ramCapacity - used, onToggle = onToggle)
            }
            if (picked.isNotEmpty()) {
                MbSectionTitle("Защищённый слот", meta = "вернётся при любом исходе")
                Spacer(Modifier.height(MbDimens.rowGap))
                picked.forEach { daemon ->
                    val isProtected = daemon.id == protectedId
                    MbListItem(
                        title = daemon.name,
                        sub = if (isProtected) "возвращается на телефон" else "в Сети можно потерять",
                        trail = if (isProtected) listOf({ MbTag("защищён", filled = true) }) else emptyList(),
                        plate = true,
                        onClick = { onProtect(daemon.id) }
                    )
                }
            }
        }
        Spacer(Modifier.height(MbDimens.blockGap))
        MbButton("Войти в Сеть", onClick = { confirming = true }, enabled = canEnter, keyIcon = MbIcons.Hack, modifier = Modifier.padding(bottom = MbDimens.blockGap))
    }

    if (confirming) {
        val keep = picked.firstOrNull { it.id == protectedId }
        MbDialog(
            onDismissRequest = { confirming = false },
            icon = MbIcons.Hack,
            title = "Войти в Сеть?",
            actions = listOf(
                MbDialogAction("Отмена", MbButtonKind.Quiet, onClick = { confirming = false }),
                MbDialogAction("Войти", MbButtonKind.Primary, MbIcons.Hack, onClick = { confirming = false; onEnter() })
            )
        ) {
            Text(
                "В Сеть уходит демонов: ${picked.size}. «${keep?.name.orEmpty()}» вернётся на телефон при любом исходе, остальных в Сети можно потерять.",
                style = MbTypography.rowSub, color = LocalMbColors.current.ink2
            )
        }
    }
}

/** Ход входа: отправка карточек, ожидание Моста, «Подключено к стойке N, надень очки» или отказ. */
@Composable
fun NetrunStatus(state: NetrunEntryState, onRetry: () -> Unit, onClose: () -> Unit) {
    Column(Modifier.fillMaxSize().padding(horizontal = MbDimens.screenPadding)) {
        MbBreadcrumb(parts = listOf("Кибердека", "Сеть"), icon = MbIcons.Hack) {
            MbIconButton(MbIcons.Close, "Закрыть", onClose)
        }
        Spacer(Modifier.height(MbDimens.blockGap))
        val c = LocalMbColors.current
        when (state) {
            NetrunEntryState.Idle -> Unit
            is NetrunEntryState.Sending -> MbPanel("Вход в Сеть", meta = rackTitle(state.rack)) {
                Text("Демоны уходят в Сеть…", style = MbTypography.rowSub, color = c.ink2)
                Spacer(Modifier.height(MbDimens.blockGap))
                MbProgress(percent = 35)
            }
            is NetrunEntryState.Waiting -> MbPanel("Связь с Мостом", meta = rackTitle(state.rack)) {
                if (state.timedOut) {
                    Text("Мост долго не отвечает. Проверьте, что вы в сети площадки. Сданные демоны Мост вернёт на телефон сам.", style = MbTypography.rowSub, color = c.ink2)
                    Spacer(Modifier.height(MbDimens.blockGap))
                    MbButton("Повторить запрос", onClick = onRetry, kind = MbButtonKind.Ghost, inline = true)
                } else {
                    Text("Карточки у Моста. Ждём, пока он соберёт деку на терминале…", style = MbTypography.rowSub, color = c.ink2)
                    Spacer(Modifier.height(MbDimens.blockGap))
                    MbProgress(percent = 70)
                }
            }
            is NetrunEntryState.Connected -> MbBanner(
                lead = { Icon(painterResource(MbIcons.Check), contentDescription = null, tint = c.ok) },
                title = "Подключено: ${rackTitle(state.rack)}",
                sub = "Наденьте очки. Телефон можно убрать в карман: добыча придёт сама.",
                action = { MbIconButton(MbIcons.Close, "Закрыть", onClose) }
            )
            is NetrunEntryState.Failed -> MbBanner(
                lead = { Icon(painterResource(MbIcons.Alert), contentDescription = null, tint = c.bad) },
                title = "Вход не удался",
                sub = state.text,
                tone = MbBannerTone.Danger,
                action = { MbIconButton(MbIcons.Close, "Закрыть", onClose) }
            )
        }
    }
}
