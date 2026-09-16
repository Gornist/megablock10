package com.megablok10.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Text
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.megablok10.app.chat.ChatStore
import com.megablok10.app.data.ChatMessageEntity
import com.megablok10.app.data.TransactionEntity
import com.megablok10.app.data.TransactionStatus
import com.megablok10.app.identity.ContactStore
import com.megablok10.app.identity.Identity
import com.megablok10.app.presence.PresenceService
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.qr.Mb10QrCodec
import com.megablok10.app.ui.theme.AppButton
import com.megablok10.app.ui.theme.AppTextField
import com.megablok10.app.ui.theme.ButtonVariant
import com.megablok10.app.ui.theme.ChamferedPanel
import com.megablok10.app.ui.theme.ChipTone
import com.megablok10.app.ui.theme.DottedDivider
import com.megablok10.app.ui.theme.EmptyState
import com.megablok10.app.ui.theme.HexBullet
import com.megablok10.app.ui.theme.IBMPlexSans
import com.megablok10.app.ui.theme.JetBrainsMono
import com.megablok10.app.ui.theme.Jura
import com.megablok10.app.ui.theme.MB10Colors
import com.megablok10.app.ui.theme.OnlineDot
import com.megablok10.app.ui.theme.StatusChip
import com.megablok10.app.ui.theme.chamferShape
import com.megablok10.app.wallet.TransactionStore
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

private sealed class ChatDestination {
    object Faction : ChatDestination()
    data class Direct(val peerPubKeyB64: String) : ChatDestination()
}

/**
 * openedWithContactKey — publicKey контакта, с которым нужно сразу открыть
 * личный тред (кнопка "Сообщение" в контактах). onContactConsumed сразу
 * обнуляет запрос на стороне AppRoot, чтобы повторный визит на вкладку без
 * нового тапа не переоткрывал тот же тред.
 *
 * Инбокс, а не два статичных сегмента (Фракция/Личные), как было раньше:
 * фракция закреплена первой строкой, ниже — реальные диалоги, отсортированные
 * по времени последнего сообщения, с превью — тот же паттерн, что в обычных
 * мессенджерах. Контакт, с которым ещё не переписывались, в списке не
 * появится — им начинают через "+", а не браузят отдельным табом.
 */
@Composable
fun ChatScreen(
    identity: Identity,
    openedWithContactKey: String? = null,
    onContactConsumed: () -> Unit = {},
    onNestedChange: (Boolean) -> Unit = {}
) {
    var destination by remember { mutableStateOf<ChatDestination?>(null) }
    var showContactPicker by remember { mutableStateOf(false) }

    LaunchedEffect(openedWithContactKey) {
        if (openedWithContactKey != null) {
            destination = ChatDestination.Direct(openedWithContactKey)
            onContactConsumed()
        }
    }

    // Шапка приложения и таббар прячутся, пока открыт тред/пикер — у обоих уже есть свой back-заголовок.
    LaunchedEffect(destination, showContactPicker) {
        onNestedChange(destination != null || showContactPicker)
    }

    when {
        showContactPicker -> NewChatPicker(
            onPick = { key -> showContactPicker = false; destination = ChatDestination.Direct(key) },
            onBack = { showContactPicker = false }
        )
        destination is ChatDestination.Faction -> FactionThread(identity, onBack = { destination = null })
        destination is ChatDestination.Direct -> DirectThread(
            identity = identity,
            peerPubKeyB64 = (destination as ChatDestination.Direct).peerPubKeyB64,
            onBack = { destination = null }
        )
        else -> ConversationInbox(
            identity = identity,
            onOpenFaction = { destination = ChatDestination.Faction },
            onOpenDirect = { key -> destination = ChatDestination.Direct(key) },
            onNewChat = { showContactPicker = true }
        )
    }
}

@Composable
private fun ConversationInbox(identity: Identity, onOpenFaction: () -> Unit, onOpenDirect: (String) -> Unit, onNewChat: () -> Unit) {
    val context = LocalContext.current
    val factionMessages by ChatStore.observeFaction(context, identity.faction).collectAsState(initial = emptyList())
    val recentThreads by ChatStore.observeRecentDirectThreads(context, identity.publicKeyB64).collectAsState(initial = emptyList())
    val contacts by ContactStore.observeAll(context).collectAsState(initial = emptyList())
    val onlinePeers by PresenceService.peers.collectAsState()
    val onlineKeys = remember(onlinePeers) { onlinePeers.map { it.pubKeyB64 }.toSet() }
    val lastFactionMessage = factionMessages.lastOrNull()

    Column(Modifier.fillMaxSize().padding(16.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Text("Чаты", color = MB10Colors.ink0, fontFamily = IBMPlexSans, fontSize = 15.sp, fontWeight = FontWeight.Medium)
            Box(
                modifier = Modifier
                    .background(MB10Colors.accentPrimary, chamferShape(5.dp))
                    .clickable(onClick = onNewChat)
                    .padding(horizontal = 12.dp, vertical = 6.dp)
            ) {
                Text("+ Новый чат", color = MB10Colors.onAccent, fontFamily = JetBrainsMono, fontSize = 10.5.sp, fontWeight = FontWeight.Medium)
            }
        }
        Spacer(Modifier.height(10.dp))

        LazyColumn(Modifier.fillMaxSize()) {
            item {
                ConversationRow(
                    title = "Фракция: ${identity.faction}",
                    preview = lastFactionMessage?.let { (if (it.fromPubKeyB64 == identity.publicKeyB64) "Вы: " else "${it.fromCallsign}: ") + previewBody(it.body) }
                        ?: "Пока нет сообщений",
                    time = lastFactionMessage?.timestamp,
                    onClick = onOpenFaction
                )
            }
            items(recentThreads, key = { it.id }) { msg ->
                val peerKey = if (msg.fromPubKeyB64 == identity.publicKeyB64) msg.toPubKeyB64 else msg.fromPubKeyB64
                val contact = contacts.find { it.publicKeyB64 == peerKey }
                ConversationRow(
                    title = contact?.callsign ?: "Неизвестный контакт",
                    preview = (if (msg.fromPubKeyB64 == identity.publicKeyB64) "Вы: " else "") + previewBody(msg.body),
                    time = msg.timestamp,
                    online = peerKey in onlineKeys,
                    onClick = { onOpenDirect(peerKey) }
                )
            }
        }
    }
}

@Composable
private fun ConversationRow(title: String, preview: String, time: Long?, online: Boolean? = null, onClick: () -> Unit) {
    val timeFormat = remember { SimpleDateFormat("HH:mm", Locale.getDefault()) }
    Column(Modifier.fillMaxWidth().clickable(onClick = onClick)) {
        Row(Modifier.fillMaxWidth().padding(vertical = 11.dp), verticalAlignment = Alignment.CenterVertically) {
            if (online != null) {
                OnlineDot(online)
                Spacer(Modifier.width(10.dp))
            } else {
                Spacer(Modifier.width(17.dp))
            }
            Column(Modifier.weight(1f)) {
                Text(title, color = MB10Colors.ink0, fontFamily = IBMPlexSans, fontSize = 13.sp)
                Spacer(Modifier.height(2.dp))
                Text(preview, color = MB10Colors.inkMuted, fontFamily = IBMPlexSans, fontSize = 11.5.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            if (time != null) {
                Spacer(Modifier.width(8.dp))
                Text(timeFormat.format(time), color = MB10Colors.inkFaint, fontFamily = JetBrainsMono, fontSize = 10.sp)
            }
        }
        DottedDivider()
    }
}

@Composable
private fun FactionThread(identity: Identity, onBack: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val messages by ChatStore.observeFaction(context, identity.faction).collectAsState(initial = emptyList())

    Column(Modifier.fillMaxSize().padding(16.dp)) {
        ThreadHeader(title = "Фракция: ${identity.faction}", onBack = onBack)
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
    val transactions by TransactionStore.observeAll(context).collectAsState(initial = emptyList())

    val contact = contacts.find { it.publicKeyB64 == peerPubKeyB64 }
    val peer = onlinePeers.find { it.pubKeyB64 == peerPubKeyB64 }
    val messages by ChatStore.observeDirect(context, identity.publicKeyB64, peerPubKeyB64).collectAsState(initial = emptyList())

    // Отправитель видит чек получателя как обычное входящее сообщение — фиксируем
    // подтверждение автоматически, без ручного шага. Повторный вызов на уже
    // подтверждённой транзакции безопасен (см. TransactionDao.confirm — WHERE status='PENDING').
    LaunchedEffect(messages) {
        messages.forEach { msg ->
            if (msg.fromPubKeyB64 != identity.publicKeyB64) {
                val decoded = Mb10QrCodec.decode(msg.body)
                if (decoded is Mb10Qr.Receipt) {
                    TransactionStore.verifyAndConfirmReceipt(context, decoded.id, decoded)
                }
            }
        }
    }

    Column(Modifier.fillMaxSize().padding(16.dp)) {
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

        MessageList(
            messages = messages,
            myPubKey = identity.publicKeyB64,
            showSender = false,
            emptyText = "Пока нет сообщений с ${contact?.callsign ?: "этим контактом"}.",
            transactions = transactions,
            onAcceptTransaction = { tx ->
                scope.launch {
                    val credited = TransactionStore.recordIncoming(context, identity.publicKeyB64, tx)
                    if (credited) {
                        val receipt = TransactionStore.buildReceipt(context, identity, tx.id)
                        ChatStore.sendDirect(context, identity, tx.fromPubKeyB64, peer, Mb10QrCodec.encodeReceipt(receipt))
                    }
                }
            }
        )
        MessageInput(placeholder = if (peer != null) "Личное сообщение" else "Личное сообщение (получатель не в сети)") { body ->
            scope.launch { ChatStore.sendDirect(context, identity, peerPubKeyB64, peer, body) }
        }
    }
}

@Composable
private fun ThreadHeader(title: String, onBack: () -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth().clickable(onClick = onBack).padding(bottom = 8.dp)
    ) {
        Text("←", color = MB10Colors.ink0, fontFamily = JetBrainsMono, fontSize = 16.sp)
        Spacer(Modifier.width(8.dp))
        Text(title, color = MB10Colors.ink0, fontFamily = IBMPlexSans, fontSize = 14.sp)
    }
}

/** Список контактов для старта НОВОГО диалога (кнопка "+" в инбоксе) — не путать с самим инбоксом уже идущих переписок. */
@Composable
private fun NewChatPicker(onPick: (String) -> Unit, onBack: () -> Unit) {
    val context = LocalContext.current
    val contacts by ContactStore.observeAll(context).collectAsState(initial = emptyList())
    val onlinePeers by PresenceService.peers.collectAsState()
    val onlineKeys = remember(onlinePeers) { onlinePeers.map { it.pubKeyB64 }.toSet() }
    var query by remember { mutableStateOf("") }
    val filtered = remember(contacts, query) {
        if (query.isBlank()) contacts
        else contacts.filter { it.callsign.contains(query, ignoreCase = true) || it.faction.contains(query, ignoreCase = true) }
    }

    Column(Modifier.fillMaxSize().padding(16.dp)) {
        ThreadHeader(title = "Новый чат", onBack = onBack)

        if (contacts.isEmpty()) {
            EmptyState("Пока нет контактов. Отсканируйте QR-код другого игрока в Профиле, чтобы начать с ним переписку.")
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
}

private sealed class ChatEntry {
    data class DaySeparator(val label: String) : ChatEntry()
    data class Msg(val message: ChatMessageEntity) : ChatEntry()
}

/** День меняется — вставляется разделитель. Тот же принцип, что и в обычных мессенджерах: не нужно вычислять дату по каждому сообщению вручную. */
private fun buildChatEntries(messages: List<ChatMessageEntity>): List<ChatEntry> {
    val cal = Calendar.getInstance()
    val today = Calendar.getInstance()
    val entries = mutableListOf<ChatEntry>()
    var lastDay = -1
    var lastYear = -1
    messages.forEach { msg ->
        cal.timeInMillis = msg.timestamp
        val day = cal.get(Calendar.DAY_OF_YEAR)
        val year = cal.get(Calendar.YEAR)
        if (day != lastDay || year != lastYear) {
            entries += ChatEntry.DaySeparator(dayLabel(cal, today))
            lastDay = day
            lastYear = year
        }
        entries += ChatEntry.Msg(msg)
    }
    return entries
}

private fun dayLabel(day: Calendar, today: Calendar): String {
    val sameYear = today.get(Calendar.YEAR) == day.get(Calendar.YEAR)
    val diff = today.get(Calendar.DAY_OF_YEAR) - day.get(Calendar.DAY_OF_YEAR)
    return when {
        sameYear && diff == 0 -> "Сегодня"
        sameYear && diff == 1 -> "Вчера"
        else -> SimpleDateFormat("d MMMM", Locale("ru")).format(day.time)
    }
}

/** Тело перевода/чека в теле сообщения — та же строка, что раньше шла в QR-картинку. В превью инбокса это должен быть человеческий текст, а не сырая строка вида "MB10:TX:v1:...". */
private fun previewBody(body: String): String = when (val decoded = Mb10QrCodec.decode(body)) {
    is Mb10Qr.Transaction -> "Перевод ${decoded.amount} €$" + if (decoded.memo.isNotBlank()) " · ${decoded.memo}" else ""
    is Mb10Qr.Receipt -> "Платёж подтверждён"
    else -> body
}

@Composable
private fun ColumnScope.MessageList(
    messages: List<ChatMessageEntity>,
    myPubKey: String,
    showSender: Boolean,
    emptyText: String,
    transactions: List<TransactionEntity> = emptyList(),
    onAcceptTransaction: ((Mb10Qr.Transaction) -> Unit)? = null
) {
    if (messages.isEmpty()) {
        Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
            EmptyState(emptyText)
        }
        return
    }
    val entries = remember(messages) { buildChatEntries(messages) }
    LazyColumn(modifier = Modifier.weight(1f)) {
        items(entries) { entry ->
            when (entry) {
                is ChatEntry.DaySeparator -> DaySeparatorLabel(entry.label)
                is ChatEntry.Msg -> MessageBubble(
                    msg = entry.message,
                    self = entry.message.fromPubKeyB64 == myPubKey,
                    showSender = showSender,
                    transactions = transactions,
                    onAcceptTransaction = onAcceptTransaction
                )
            }
        }
    }
}

@Composable
private fun DaySeparatorLabel(label: String) {
    Row(Modifier.fillMaxWidth().padding(vertical = 10.dp), horizontalArrangement = Arrangement.Center) {
        Text(label, color = MB10Colors.inkTertiary, fontFamily = JetBrainsMono, fontSize = 9.5.sp)
    }
}

@Composable
private fun MessageInput(placeholder: String, onSend: (String) -> Unit) {
    var draft by remember { mutableStateOf("") }
    val canSend = draft.isNotBlank()

    Row(
        modifier = Modifier.fillMaxWidth().padding(top = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        AppTextField(
            value = draft,
            onValueChange = { draft = it },
            placeholder = placeholder,
            modifier = Modifier.weight(1f)
        )
        Box(
            modifier = Modifier
                .background(if (canSend) MB10Colors.accentAction else MB10Colors.surfaceSunken, chamferShape(6.dp))
                .clickable(enabled = canSend) {
                    onSend(draft)
                    draft = ""
                }
                .padding(horizontal = 16.dp, vertical = 12.dp)
        ) {
            Text(
                "Отпр.",
                color = if (canSend) MB10Colors.onAccent else MB10Colors.inkTertiary,
                fontFamily = JetBrainsMono, fontSize = 12.sp, fontWeight = FontWeight.Medium
            )
        }
    }
}

/**
 * Свои сообщения — справа, тонированные акцентом; чужие — слева, нейтральные.
 * Раньше единственным отличием была двухпиксельная полоска слева от своих
 * сообщений — легко не заметить. Сторона + цвет вместе читаются мгновенно,
 * без необходимости сверяться с подписью отправителя.
 *
 * Тело сообщения может оказаться сериализованным переводом/чеком (тот же
 * формат, что раньше шёл в QR) — тогда вместо текстового пузыря рисуется
 * платёжный: с суммой и, для получателя ещё не принятого перевода, кнопкой
 * "Принять" прямо в ленте.
 */
@Composable
private fun MessageBubble(
    msg: ChatMessageEntity,
    self: Boolean,
    showSender: Boolean,
    transactions: List<TransactionEntity> = emptyList(),
    onAcceptTransaction: ((Mb10Qr.Transaction) -> Unit)? = null
) {
    val decoded = remember(msg.body) { Mb10QrCodec.decode(msg.body) }
    when (decoded) {
        is Mb10Qr.Transaction -> PaymentBubble(
            tx = decoded,
            self = self,
            senderCallsign = msg.fromCallsign,
            status = transactions.find { it.id == decoded.id }?.status,
            onAccept = if (self) null else { { onAcceptTransaction?.invoke(decoded) } }
        )
        is Mb10Qr.Receipt -> ReceiptLine()
        else -> PlainMessageBubble(msg, self, showSender)
    }
}

@Composable
private fun PlainMessageBubble(msg: ChatMessageEntity, self: Boolean, showSender: Boolean) {
    val timeFormat = remember { SimpleDateFormat("HH:mm", Locale.getDefault()) }
    Row(
        modifier = Modifier.fillMaxWidth().padding(bottom = 10.dp),
        horizontalArrangement = if (self) Arrangement.End else Arrangement.Start
    ) {
        Column(modifier = Modifier.widthIn(max = 280.dp), horizontalAlignment = if (self) Alignment.End else Alignment.Start) {
            if (showSender && !self) {
                Text(msg.fromCallsign, color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 10.sp)
                Spacer(Modifier.height(2.dp))
            }
            Box(
                modifier = Modifier
                    .background(if (self) MB10Colors.accentAction.copy(alpha = 0.16f) else MB10Colors.surfaceSunken, chamferShape(6.dp))
                    .border(1.dp, if (self) MB10Colors.accentAction.copy(alpha = 0.4f) else MB10Colors.borderMuted, chamferShape(6.dp))
                    .padding(vertical = 9.dp, horizontal = 11.dp)
            ) {
                Text(msg.body, color = MB10Colors.inkPrimary, fontFamily = IBMPlexSans, fontSize = 13.5.sp, lineHeight = 19.sp)
            }
            Spacer(Modifier.height(2.dp))
            Text(timeFormat.format(msg.timestamp), color = MB10Colors.inkTertiary, fontFamily = JetBrainsMono, fontSize = 9.5.sp)
        }
    }
}

@Composable
private fun PaymentBubble(
    tx: Mb10Qr.Transaction,
    self: Boolean,
    senderCallsign: String,
    status: String?,
    onAccept: (() -> Unit)?
) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(bottom = 10.dp),
        horizontalArrangement = if (self) Arrangement.End else Arrangement.Start
    ) {
        ChamferedPanel(
            borderColor = MB10Colors.accentAction,
            fillColor = MB10Colors.surfaceSunken,
            cut = 8.dp,
            contentPadding = 12.dp,
            modifier = Modifier.widthIn(max = 260.dp)
        ) {
            Column {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    HexBullet(MB10Colors.accentAction, size = 8.dp)
                    Spacer(Modifier.width(6.dp))
                    Text(
                        if (self) "Перевод отправлен" else "Перевод от $senderCallsign",
                        color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 10.sp
                    )
                }
                Spacer(Modifier.height(6.dp))
                Text("${tx.amount} €$", color = MB10Colors.inkPrimary, fontFamily = Jura, fontWeight = FontWeight.Bold, fontSize = 22.sp)
                if (tx.memo.isNotBlank()) {
                    Spacer(Modifier.height(2.dp))
                    Text(tx.memo, color = MB10Colors.inkSecondary, fontFamily = IBMPlexSans, fontSize = 12.sp)
                }
                Spacer(Modifier.height(8.dp))
                when {
                    self -> StatusChip(
                        if (status == TransactionStatus.CONFIRMED) "подтверждено" else "ожидает подтверждения",
                        tone = if (status == TransactionStatus.CONFIRMED) ChipTone.Action else ChipTone.Neutral
                    )
                    status == null -> AppButton("Принять", variant = ButtonVariant.Primary, modifier = Modifier.fillMaxWidth(), onClick = { onAccept?.invoke() })
                    else -> StatusChip("принято", tone = ChipTone.Action)
                }
            }
        }
    }
}

/** Чек — не полноценный пузырь, а тонкая системная строка по центру, как разделитель дня. */
@Composable
private fun ReceiptLine() {
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), horizontalArrangement = Arrangement.Center) {
        Text("✓ Получение подтверждено", color = MB10Colors.inkTertiary, fontFamily = JetBrainsMono, fontSize = 10.sp)
    }
}
