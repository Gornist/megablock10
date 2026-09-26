package com.megablok10.app.ui.screens

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import com.megablok10.app.data.CallDirection
import com.megablok10.app.data.CallLogEntity
import com.megablok10.app.data.CallOutcome
import com.megablok10.kit.mesh.OnlinePlayer
import com.megablok10.app.di.callsViewModel
import com.megablok10.app.ui.appViewModel
import com.megablok10.app.ui.theme.AppSnack
import com.megablok10.app.ui.theme.LocalMbColors
import com.megablok10.app.ui.theme.MbDimens
import com.megablok10.app.ui.theme.MbEmptyState
import com.megablok10.app.ui.theme.MbIconButton
import com.megablok10.app.ui.theme.MbIcons
import com.megablok10.app.ui.theme.MbListItem
import com.megablok10.app.ui.theme.MbListItemState
import com.megablok10.app.ui.theme.MbSectionTitle
import com.megablok10.app.ui.theme.MbTypography
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Журнал звонков со своим списком контактов сверху («Контакты» — прототип, docs/ux/prototype/mb10-ui-kit.html, S.calls):
 * тап по строке контакта или журнала звонит тому же собеседнику, если он сейчас в сети. Отдельного экрана-пикера «+»
 * (как раньше) больше нет — на площадке игроков немного, список контактов виден целиком без поиска.
 */
@Composable
fun CallsScreen(onCallPeer: (OnlinePlayer) -> Unit) {
    val calls = appViewModel { callsViewModel() }
    val callLog by calls.log.collectAsStateWithLifecycle()
    val directory by calls.contacts.collectAsStateWithLifecycle()

    fun tryCall(peerPubKeyB64: String, callsign: String) {
        val peer = directory.peer(peerPubKeyB64)
        if (peer == null) AppSnack.show("$callsign сейчас не в сети") else onCallPeer(peer)
    }

    Column(Modifier.fillMaxSize().padding(horizontal = MbDimens.screenPadding)) {
        if (directory.contacts.isEmpty() && callLog.isEmpty()) {
            Box(Modifier.weight(1f)) {
                MbEmptyState(MbIcons.Phone, "Звонков пока не было", "Отсканируйте QR-код другого игрока в Профиле, чтобы иметь возможность позвонить.")
            }
        } else {
            LazyColumn(Modifier.weight(1f)) {
                if (directory.contacts.isNotEmpty()) {
                    item { MbSectionTitle("Контакты", meta = "${directory.contacts.size}") }
                    items(directory.contacts, key = { "c:${it.publicKeyB64}" }) { c ->
                        val online = c.publicKeyB64 in directory.onlineKeys
                        MbListItem(
                            title = c.callsign,
                            sub = (if (online) "в сети" else "не в сети") + " · ${c.faction}",
                            lead = { Icon(painterResource(MbIcons.User), contentDescription = null) },
                            state = if (online) MbListItemState.Normal else MbListItemState.Off,
                            trail = listOf({ MbIconButton(MbIcons.Phone, "Позвонить", { tryCall(c.publicKeyB64, c.callsign) }) }),
                            onClick = { tryCall(c.publicKeyB64, c.callsign) }
                        )
                    }
                }
                if (callLog.isNotEmpty()) {
                    item { MbSectionTitle("Недавние") }
                    items(callLog, key = { "l:${it.id}" }) { entry -> CallLogRow(entry, onClick = { tryCall(entry.peerPubKeyB64, entry.peerCallsign) }) }
                }
            }
        }
    }
}

/** Только метаданные звонка — направление, итог, время, длительность для состоявшихся. Само аудио сюда никогда не попадает, ни в каком виде. */
@Composable
internal fun CallLogRow(entry: CallLogEntity, onClick: () -> Unit) {
    val timeFormatter = remember { SimpleDateFormat("HH:mm", Locale.getDefault()) }
    val c = LocalMbColors.current
    val outgoing = entry.direction == CallDirection.OUTGOING
    val icon: Int
    val tone: androidx.compose.ui.graphics.Color
    val label: String
    when (entry.outcome) {
        CallOutcome.COMPLETED -> { icon = if (outgoing) MbIcons.Out else MbIcons.In; tone = c.ok; label = if (outgoing) "исходящий" else "входящий" }
        CallOutcome.MISSED -> { icon = MbIcons.Miss; tone = c.bad; label = "пропущенный" }
        CallOutcome.DECLINED -> { icon = MbIcons.Miss; tone = c.bad; label = "отклонён" }
        CallOutcome.UNREACHABLE -> { icon = MbIcons.Miss; tone = c.bad; label = "не в сети" }
        else -> { icon = if (outgoing) MbIcons.Out else MbIcons.In; tone = c.ink3; label = "отменён" }
    }
    val duration = if (entry.outcome == CallOutcome.COMPLETED) formatDuration(entry.endedAt - entry.startedAt) else "—"
    MbListItem(
        title = entry.peerCallsign,
        sub = label,
        lead = { Icon(painterResource(icon), contentDescription = null, tint = tone) },
        trail = listOf(
            { Text(timeFormatter.format(Date(entry.startedAt)), style = MbTypography.meta, color = c.ink2) },
            { Text(duration, style = MbTypography.meta, color = c.ink2) }
        ),
        onClick = onClick
    )
}

private fun formatDuration(millis: Long): String {
    val totalSeconds = (millis / 1000).coerceAtLeast(0)
    val minutes = totalSeconds / 60
    val seconds = totalSeconds % 60
    return "%d:%02d".format(minutes, seconds)
}
