package com.megablok10.app.ui.screens

import com.megablok10.app.ui.theme.AppSnack
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.megablok10.app.data.CallDirection
import com.megablok10.app.data.CallLogEntity
import com.megablok10.app.data.CallOutcome
import com.megablok10.kit.mesh.OnlinePlayer
import com.megablok10.app.di.callsViewModel
import com.megablok10.app.identity.ContactsView
import com.megablok10.app.ui.appViewModel
import com.megablok10.app.ui.theme.AppTextField
import com.megablok10.app.ui.theme.CompactActionButton
import com.megablok10.app.ui.theme.DottedDivider
import com.megablok10.app.ui.theme.EmptyState
import com.megablok10.app.ui.theme.IBMPlexSans
import com.megablok10.app.ui.theme.JetBrainsMono
import com.megablok10.app.ui.theme.ListRow
import com.megablok10.app.ui.theme.MB10Colors
import com.megablok10.app.ui.theme.OnlineDot
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Журнал звонков — своя вкладка, а не похороненный внизу Профиля список,
 * как раньше. "+" открывает пикер контактов для нового звонка; тап по
 * строке лога перезванивает тому же собеседнику, если он сейчас в сети.
 */
@Composable
fun CallsScreen(onCallPeer: (OnlinePlayer) -> Unit) {
    val calls = appViewModel { callsViewModel() }
    val callLog by calls.log.collectAsStateWithLifecycle()
    val directory by calls.contacts.collectAsStateWithLifecycle()
    var showPicker by remember { mutableStateOf(false) }

    fun tryCall(peerPubKeyB64: String, callsign: String) {
        val peer = directory.peer(peerPubKeyB64)
        if (peer == null) {
            AppSnack.show("$callsign сейчас не в сети")
        } else {
            onCallPeer(peer)
        }
    }

    if (showPicker) {
        NewCallPicker(
            directory = directory,
            onPick = { key, callsign -> showPicker = false; tryCall(key, callsign) },
            onBack = { showPicker = false }
        )
        return
    }

    Column(Modifier.fillMaxSize().padding(16.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Text("Звонки", color = MB10Colors.inkPrimary, fontFamily = IBMPlexSans, fontSize = 15.sp, fontWeight = FontWeight.Medium)
            CompactActionButton("+ Новый звонок", onClick = { showPicker = true })
        }
        Spacer(Modifier.height(10.dp))

        if (callLog.isEmpty()) {
            EmptyState("Звонков пока не было.")
        } else {
            LazyColumn(Modifier.fillMaxSize()) {
                items(callLog, key = { it.id }) { entry ->
                    CallLogRow(entry, onClick = { tryCall(entry.peerPubKeyB64, entry.peerCallsign) })
                    DottedDivider()
                }
            }
        }
    }
}

/** Только метаданные звонка — направление, итог, время, длительность для состоявшихся. Само аудио сюда никогда не попадает, ни в каком виде. */
@Composable
private fun CallLogRow(entry: CallLogEntity, onClick: () -> Unit) {
    val timeFormatter = remember { SimpleDateFormat("HH:mm", Locale.getDefault()) }
    val outcomeLabel = when (entry.outcome) {
        CallOutcome.COMPLETED -> "Завершён · ${formatDuration(entry.endedAt - entry.startedAt)}"
        CallOutcome.DECLINED -> "Отклонён"
        CallOutcome.CANCELLED -> "Отменён"
        CallOutcome.MISSED -> "Пропущен"
        CallOutcome.UNREACHABLE -> "Не в сети"
        else -> entry.outcome
    }
    val outcomeColor = when (entry.outcome) {
        CallOutcome.COMPLETED -> MB10Colors.accentAction
        CallOutcome.MISSED, CallOutcome.UNREACHABLE -> MB10Colors.accentDanger
        else -> MB10Colors.inkSecondary
    }
    ListRow(
        onClick = onClick,
        leading = {
            Text(
                if (entry.direction == CallDirection.OUTGOING) "↗" else "↙",
                color = MB10Colors.inkTertiary, fontFamily = JetBrainsMono, fontSize = 14.sp,
                modifier = Modifier.width(10.dp)
            )
        },
        trailing = { Text(timeFormatter.format(Date(entry.startedAt)), color = MB10Colors.inkTertiary, fontFamily = JetBrainsMono, fontSize = 11.sp) }
    ) {
        Text(entry.peerCallsign, color = MB10Colors.inkPrimary, fontFamily = IBMPlexSans, fontSize = 13.sp)
        Text(outcomeLabel, color = outcomeColor, fontFamily = JetBrainsMono, fontSize = 11.sp)
    }
}

private fun formatDuration(millis: Long): String {
    val totalSeconds = (millis / 1000).coerceAtLeast(0)
    val minutes = totalSeconds / 60
    val seconds = totalSeconds % 60
    return "%d:%02d".format(minutes, seconds)
}

/** Список контактов для старта нового звонка (кнопка "+") — сам звонок пойдёт, только если контакт сейчас в сети. */
@Composable
private fun NewCallPicker(directory: ContactsView, onPick: (String, String) -> Unit, onBack: () -> Unit) {
    val contacts = directory.contacts
    val onlineKeys = directory.onlineKeys
    var query by remember { mutableStateOf("") }
    val filtered = remember(contacts, query) {
        if (query.isBlank()) contacts
        else contacts.filter { it.callsign.contains(query, ignoreCase = true) || it.faction.contains(query, ignoreCase = true) }
    }

    Column(Modifier.fillMaxSize().padding(16.dp)) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth().clickable(onClick = onBack).padding(bottom = 8.dp)
        ) {
            Text("←", color = MB10Colors.inkPrimary, fontFamily = JetBrainsMono, fontSize = 16.sp)
            Spacer(Modifier.width(8.dp))
            Text("Новый звонок", color = MB10Colors.inkPrimary, fontFamily = IBMPlexSans, fontSize = 14.sp)
        }

        if (contacts.isEmpty()) {
            EmptyState("Пока нет контактов. Отсканируйте QR-код другого игрока в Профиле, чтобы иметь возможность позвонить.")
            return@Column
        }

        AppTextField(value = query, onValueChange = { query = it }, placeholder = "Позывной или фракция", modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.height(10.dp))

        if (filtered.isEmpty()) {
            EmptyState("Ничего не нашлось.")
            return@Column
        }

        LazyColumn(Modifier.fillMaxSize()) {
            items(filtered, key = { it.publicKeyB64 }) { c ->
                ListRow(
                    onClick = { onPick(c.publicKeyB64, c.callsign) },
                    leading = { OnlineDot(c.publicKeyB64 in onlineKeys) }
                ) {
                    Text(c.callsign, color = MB10Colors.inkPrimary, fontFamily = IBMPlexSans, fontSize = 13.sp)
                    Text(c.faction, color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 11.sp)
                }
            }
        }
    }
}
