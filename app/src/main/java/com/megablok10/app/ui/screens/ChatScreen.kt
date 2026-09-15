package com.megablok10.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.megablok10.app.chat.ChatStore
import com.megablok10.app.data.ChatMessageEntity
import com.megablok10.app.identity.ContactStore
import com.megablok10.app.identity.Identity
import com.megablok10.app.presence.PresenceService
import com.megablok10.app.ui.theme.ChamferedPanel
import com.megablok10.app.ui.theme.IBMPlexSans
import com.megablok10.app.ui.theme.JetBrainsMono
import com.megablok10.app.ui.theme.MB10Colors
import com.megablok10.app.ui.theme.chamferShape
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Locale

/**
 * openedWithContactKey — publicKey контакта, с которым нужно сразу открыть
 * личный тред (кнопка "Сообщение" в контактах). onContactConsumed сразу
 * обнуляет запрос на стороне AppRoot, чтобы повторный визит на вкладку без
 * нового тапа не переоткрывал тот же тред.
 */
@Composable
fun ChatScreen(identity: Identity, openedWithContactKey: String? = null, onContactConsumed: () -> Unit = {}) {
    var activeSegment by remember { mutableStateOf(0) }
    var selectedContactKey by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(openedWithContactKey) {
        if (openedWithContactKey != null) {
            activeSegment = 1
            selectedContactKey = openedWithContactKey
            onContactConsumed()
        }
    }

    Column(Modifier.fillMaxSize().padding(16.dp)) {
        ChamferedPanel(
            borderColor = MB10Colors.inkFaint,
            fillColor = MB10Colors.bg1,
            cut = 6.dp,
            contentPadding = 0.dp,
            modifier = Modifier.fillMaxWidth()
        ) {
            Row(Modifier.fillMaxWidth()) {
                listOf("Фракция", "Личные").forEachIndexed { i, label ->
                    val active = i == activeSegment
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .background(if (active) MB10Colors.bg2 else MB10Colors.bg1)
                            .clickable { activeSegment = i }
                            .padding(vertical = 8.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            label,
                            color = if (active) MB10Colors.ink0 else MB10Colors.inkMuted,
                            fontFamily = IBMPlexSans,
                            fontSize = 13.sp
                        )
                    }
                }
            }
        }
        Spacer(Modifier.height(10.dp))

        if (activeSegment == 0) {
            FactionThread(identity)
        } else {
            val key = selectedContactKey
            if (key == null) {
                ContactPicker(onPick = { selectedContactKey = it })
            } else {
                DirectThread(identity = identity, peerPubKeyB64 = key, onBack = { selectedContactKey = null })
            }
        }
    }
}

@Composable
private fun FactionThread(identity: Identity) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val messages by ChatStore.observeFaction(context, identity.faction).collectAsState(initial = emptyList())

    Column(Modifier.fillMaxSize()) {
        MessageList(messages = messages, myPubKey = identity.publicKeyB64, showSender = true, emptyText = "Пока нет сообщений во фракции.")
        MessageInput(placeholder = "Сообщение фракции") { body ->
            scope.launch { ChatStore.sendFaction(context, identity, body) }
        }
    }
}

@Composable
private fun DirectThread(identity: Identity, peerPubKeyB64: String, onBack: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val contacts by ContactStore.observeAll(context).collectAsState(initial = emptyList())
    val onlinePeers by PresenceService.peers.collectAsState()

    val contact = contacts.find { it.publicKeyB64 == peerPubKeyB64 }
    val peer = onlinePeers.find { it.pubKeyB64 == peerPubKeyB64 }
    val messages by ChatStore.observeDirect(context, identity.publicKeyB64, peerPubKeyB64).collectAsState(initial = emptyList())

    Column(Modifier.fillMaxSize()) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth().clickable(onClick = onBack).padding(bottom = 8.dp)
        ) {
            Text("←", color = MB10Colors.ink0, fontFamily = JetBrainsMono, fontSize = 16.sp)
            Spacer(Modifier.width(8.dp))
            Text(contact?.callsign ?: "Неизвестный контакт", color = MB10Colors.ink0, fontFamily = IBMPlexSans, fontSize = 14.sp, modifier = Modifier.weight(1f))
            OnlineDot(online = peer != null)
            Spacer(Modifier.width(6.dp))
            Text(if (peer != null) "в сети" else "не в сети", color = MB10Colors.inkMuted, fontFamily = JetBrainsMono, fontSize = 10.sp)
        }

        MessageList(messages = messages, myPubKey = identity.publicKeyB64, showSender = false, emptyText = "Пока нет сообщений с ${contact?.callsign ?: "этим контактом"}.")
        MessageInput(placeholder = if (peer != null) "Личное сообщение" else "Личное сообщение (получатель не в сети)") { body ->
            scope.launch { ChatStore.sendDirect(context, identity, peerPubKeyB64, peer, body) }
        }
    }
}

@Composable
private fun ContactPicker(onPick: (String) -> Unit) {
    val context = LocalContext.current
    val contacts by ContactStore.observeAll(context).collectAsState(initial = emptyList())
    val onlinePeers by PresenceService.peers.collectAsState()
    val onlineKeys = remember(onlinePeers) { onlinePeers.map { it.pubKeyB64 }.toSet() }

    if (contacts.isEmpty()) {
        Text(
            "Пока нет контактов. Отсканируйте QR-код другого игрока в Профиле, чтобы начать с ним переписку.",
            color = MB10Colors.inkMuted, fontFamily = IBMPlexSans, fontSize = 13.sp, lineHeight = 18.sp,
            modifier = Modifier.padding(top = 8.dp)
        )
        return
    }

    LazyColumn(Modifier.fillMaxSize()) {
        items(contacts, key = { it.publicKeyB64 }) { c ->
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth().clickable { onPick(c.publicKeyB64) }.padding(vertical = 12.dp)
            ) {
                OnlineDot(online = c.publicKeyB64 in onlineKeys)
                Spacer(Modifier.width(10.dp))
                Column(Modifier.weight(1f)) {
                    Text(c.callsign, color = MB10Colors.ink0, fontFamily = IBMPlexSans, fontSize = 13.sp)
                    Text(c.faction, color = MB10Colors.inkMuted, fontFamily = JetBrainsMono, fontSize = 10.sp)
                }
            }
        }
    }
}

@Composable
private fun OnlineDot(online: Boolean) {
    Box(Modifier.size(7.dp).background(if (online) MB10Colors.ink0 else MB10Colors.inkFaint, CircleShape))
}

@Composable
private fun ColumnScope.MessageList(messages: List<ChatMessageEntity>, myPubKey: String, showSender: Boolean, emptyText: String) {
    if (messages.isEmpty()) {
        Text(emptyText, color = MB10Colors.inkMuted, fontFamily = IBMPlexSans, fontSize = 13.sp, modifier = Modifier.weight(1f))
        return
    }
    LazyColumn(modifier = Modifier.weight(1f)) {
        items(messages, key = { it.id }) { msg -> MessageBubble(msg, self = msg.fromPubKeyB64 == myPubKey, showSender = showSender) }
    }
}

@Composable
private fun MessageInput(placeholder: String, onSend: (String) -> Unit) {
    var draft by remember { mutableStateOf("") }

    Row(
        modifier = Modifier.fillMaxWidth().padding(top = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        ChamferedPanel(
            modifier = Modifier.weight(1f),
            borderColor = MB10Colors.inkFaint,
            fillColor = MB10Colors.bg2,
            cut = 6.dp,
            contentPadding = 0.dp
        ) {
            TextField(
                value = draft,
                onValueChange = { draft = it },
                placeholder = { Text(placeholder, color = MB10Colors.inkMuted, fontFamily = IBMPlexSans, fontSize = 13.sp) },
                singleLine = true,
                keyboardOptions = KeyboardOptions.Default,
                colors = TextFieldDefaults.colors(
                    focusedContainerColor = MB10Colors.bg2,
                    unfocusedContainerColor = MB10Colors.bg2,
                    focusedIndicatorColor = Color.Transparent,
                    unfocusedIndicatorColor = Color.Transparent,
                    focusedTextColor = MB10Colors.ink0,
                    unfocusedTextColor = MB10Colors.ink0
                ),
                textStyle = androidx.compose.ui.text.TextStyle(fontFamily = IBMPlexSans, fontSize = 13.sp),
                modifier = Modifier.fillMaxWidth()
            )
        }
        Box(
            modifier = Modifier
                .background(MB10Colors.accentPrimary, chamferShape(6.dp))
                .clickable(enabled = draft.isNotBlank()) {
                    onSend(draft)
                    draft = ""
                }
                .padding(horizontal = 16.dp, vertical = 12.dp)
        ) {
            Text("Отпр.", color = MB10Colors.onAccent, fontFamily = JetBrainsMono, fontSize = 12.sp, fontWeight = FontWeight.Medium)
        }
    }
}

@Composable
private fun MessageBubble(msg: ChatMessageEntity, self: Boolean, showSender: Boolean) {
    val timeFormat = remember { SimpleDateFormat("HH:mm", Locale.getDefault()) }
    Column(Modifier.fillMaxWidth().padding(bottom = 12.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(
                if (showSender) (if (self) "Вы" else msg.fromCallsign) else "",
                color = MB10Colors.inkMuted, fontFamily = JetBrainsMono, fontSize = 10.sp
            )
            Text(timeFormat.format(msg.timestamp), color = MB10Colors.inkMuted, fontFamily = JetBrainsMono, fontSize = 10.sp)
        }
        Spacer(Modifier.height(4.dp))
        Row {
            if (self) {
                Box(Modifier.width(2.dp).background(MB10Colors.accentPrimary))
            }
            Box(
                modifier = Modifier
                    .weight(1f)
                    .background(MB10Colors.bg2, chamferShape(6.dp))
                    .padding(vertical = 9.dp, horizontal = 11.dp)
            ) {
                Text(msg.body, color = MB10Colors.ink0, fontFamily = IBMPlexSans, fontSize = 13.5.sp, lineHeight = 19.sp)
            }
        }
    }
}
