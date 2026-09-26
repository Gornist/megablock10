package com.megablok10.app.ui.screens

import androidx.activity.compose.BackHandler
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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import com.megablok10.app.data.ChatMessageEntity
import com.megablok10.app.data.MessageStatus
import com.megablok10.app.data.ItemTransferEntity
import com.megablok10.app.data.TransactionEntity
import com.megablok10.app.data.TransactionStatus
import com.megablok10.app.identity.Identity
import com.megablok10.app.items.ItemPayload
import com.megablok10.app.breach.label
import com.megablok10.app.qr.ItemKind
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.qr.Mb10QrCodec
import com.megablok10.app.ui.theme.LocalMbColors
import com.megablok10.app.ui.theme.MbBreadcrumb
import com.megablok10.app.ui.theme.MbButton
import com.megablok10.app.ui.theme.MbBubble
import com.megablok10.app.ui.theme.MbComposer
import com.megablok10.app.ui.theme.MbDaySep
import com.megablok10.app.ui.theme.MbDimens
import com.megablok10.app.ui.theme.MbEmptyState
import com.megablok10.app.ui.theme.MbIconButton
import com.megablok10.app.ui.theme.MbIcons
import com.megablok10.app.ui.theme.MbListItem
import com.megablok10.app.ui.theme.MbMetaLine
import com.megablok10.app.ui.theme.MbMetaTone
import com.megablok10.app.ui.theme.MbPayBubble
import com.megablok10.app.ui.theme.MbStatusText
import com.megablok10.app.ui.theme.MbStatusTone
import com.megablok10.app.ui.theme.MbTag
import com.megablok10.app.ui.theme.MbTagTone
import com.megablok10.app.ui.theme.MbTypography
import com.megablok10.app.ui.theme.formatMoney
import com.megablok10.app.di.chatViewModel
import com.megablok10.app.di.directThreadViewModel
import com.megablok10.app.identity.ContactsView
import com.megablok10.app.ui.appViewModel
import com.megablok10.kit.mesh.OnlinePlayer
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
    onNestedChange: (Boolean) -> Unit = {},
    onQuickTransfer: (String) -> Unit = {},
    onQuickItem: (ItemKind, String) -> Unit = { _, _ -> },
    onCallContact: (OnlinePlayer) -> Unit = {}
) {
    val chat = appViewModel { chatViewModel() }
    val inbox by chat.state.collectAsStateWithLifecycle()
    var destination by remember { mutableStateOf<ChatDestination?>(null) }
    var showContactPicker by remember { mutableStateOf(false) }
    BackHandler(enabled = destination != null || showContactPicker) {
        if (showContactPicker) showContactPicker = false else destination = null
    }

    LaunchedEffect(openedWithContactKey) {
        if (openedWithContactKey != null) {
            destination = ChatDestination.Direct(openedWithContactKey)
            onContactConsumed()
        }
    }

    // Шапка оболочки прячется, пока открыт тред/пикер — у обоих свой Breadcrumb-заголовок (нижнее меню остаётся видно).
    LaunchedEffect(destination, showContactPicker) {
        onNestedChange(destination != null || showContactPicker)
    }

    when {
        showContactPicker -> NewChatPicker(
            directory = inbox.contacts,
            onPick = { key -> showContactPicker = false; destination = ChatDestination.Direct(key) },
            onBack = { showContactPicker = false }
        )
        destination is ChatDestination.Faction -> FactionThread(identity, inbox.factionMessages, onSend = chat::sendFaction, onBack = { destination = null })
        destination is ChatDestination.Direct -> DirectThread(
            identity = identity,
            peerPubKeyB64 = (destination as ChatDestination.Direct).peerPubKeyB64,
            onBack = { destination = null },
            onQuickTransfer = onQuickTransfer,
            onQuickItem = onQuickItem,
            onCallContact = onCallContact
        )
        else -> ConversationInbox(
            identity = identity,
            inbox = inbox,
            onOpenFaction = { destination = ChatDestination.Faction },
            onOpenDirect = { key -> destination = ChatDestination.Direct(key) },
            onNewChat = { showContactPicker = true }
        )
    }
}

@Composable
private fun ConversationInbox(
    identity: Identity,
    inbox: ChatInboxState,
    onOpenFaction: () -> Unit,
    onOpenDirect: (String) -> Unit,
    onNewChat: () -> Unit,
) {
    val recentThreads = inbox.recentThreads
    val lastFactionMessage = inbox.factionMessages.lastOrNull()

    Column(Modifier.fillMaxSize().padding(horizontal = MbDimens.screenPadding)) {
        Box(Modifier.weight(1f)) {
            if (recentThreads.isEmpty() && lastFactionMessage == null) {
                MbEmptyState(
                    icon = MbIcons.Chat,
                    title = "Чатов пока нет",
                    text = "Отсканируйте QR-код другого игрока в Профиле, чтобы начать с ним переписку."
                )
            } else {
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
                        val contact = inbox.contacts.contact(peerKey)
                        ConversationRow(
                            title = contact?.callsign ?: "Неизвестный контакт",
                            preview = (if (msg.fromPubKeyB64 == identity.publicKeyB64) "Вы: " else "") + previewBody(msg.body),
                            time = msg.timestamp,
                            onClick = { onOpenDirect(peerKey) }
                        )
                    }
                }
            }
        }
        MbButton("Новый чат", onClick = onNewChat, modifier = Modifier.padding(vertical = MbDimens.blockGap), keyIcon = MbIcons.Plus)
    }
}

@Composable
internal fun ConversationRow(title: String, preview: String, time: Long?, onClick: () -> Unit) {
    val timeFormat = remember { SimpleDateFormat("HH:mm", Locale.getDefault()) }
    MbListItem(
        title = title,
        sub = preview,
        lead = { Icon(painterResource(MbIcons.User), contentDescription = null) },
        trail = if (time != null) listOf({ Text(timeFormat.format(time), style = MbTypography.meta, color = LocalMbColors.current.ink2) }) else emptyList(),
        onClick = onClick
    )
}

@Composable
private fun FactionThread(identity: Identity, messages: List<ChatMessageEntity>, onSend: (String) -> Unit, onBack: () -> Unit) {
    var draft by remember { mutableStateOf("") }
    Column(Modifier.fillMaxSize().padding(horizontal = MbDimens.screenPadding)) {
        MbBreadcrumb(parts = listOf("Сообщения", "Фракция: ${identity.faction}"), icon = MbIcons.Mail) {
            MbIconButton(MbIcons.Close, "Назад", onBack)
        }
        Spacer(Modifier.height(MbDimens.blockGap))
        MessageList(messages = messages, myPubKey = identity.publicKeyB64, showSender = true, emptyText = "Пока нет сообщений во фракции.")
        MbComposer(
            value = draft,
            onValueChange = { draft = it },
            onSend = { if (draft.isNotBlank()) { onSend(draft); draft = "" } },
            placeholder = "Сообщение фракции"
        )
    }
}

@Composable
private fun DirectThread(
    identity: Identity,
    peerPubKeyB64: String,
    onBack: () -> Unit,
    onQuickTransfer: (String) -> Unit,
    onQuickItem: (ItemKind, String) -> Unit,
    onCallContact: (OnlinePlayer) -> Unit
) {
    // Свой экземпляр на пару «я — собеседник»: лента из базы привязана к ключам (после сброса сессии — новый персонаж, новый тред).
    val thread = appViewModel(key = "thread:${identity.publicKeyB64}:$peerPubKeyB64") { directThreadViewModel(identity.publicKeyB64, peerPubKeyB64) }
    val state by thread.state.collectAsStateWithLifecycle()
    val messages = state.feed.messages
    val contact = state.contacts.contact(peerPubKeyB64)
    val peer = state.contacts.peer(peerPubKeyB64)
    var draft by remember { mutableStateOf("") }
    var attachMenuOpen by remember { mutableStateOf(false) }

    Column(Modifier.fillMaxSize().padding(horizontal = MbDimens.screenPadding)) {
        MbBreadcrumb(parts = listOf("Сообщения", contact?.callsign ?: "Неизвестный контакт"), icon = MbIcons.Mail) {
            MbIconButton(MbIcons.Close, "Назад", onBack)
            if (peer != null) MbIconButton(MbIcons.Phone, "Позвонить", { onCallContact(peer) })
            MbIconButton(MbIcons.Wallet, "Перевод", { onQuickTransfer(peerPubKeyB64) })
        }
        MbMetaLine(
            (if (peer != null) "● в сети" else "не в сети") + " · ${contact?.faction ?: "—"} · ключ ${shortKey(peerPubKeyB64)}",
            tone = if (peer != null) MbMetaTone.Ok else MbMetaTone.Neutral
        )
        Spacer(Modifier.height(MbDimens.rowGap))
        MessageList(
            messages = messages,
            myPubKey = identity.publicKeyB64,
            showSender = false,
            emptyText = "Пока нет сообщений с ${contact?.callsign ?: "этим контактом"}.",
            transactions = state.feed.transactions,
            itemTransfers = state.feed.itemTransfers,
            onAcceptItem = thread::accept,
            onAcceptTransaction = thread::accept
        )
        Row(Modifier.fillMaxWidth().padding(vertical = MbDimens.blockGap), horizontalArrangement = Arrangement.spacedBy(MbDimens.rowGap), verticalAlignment = Alignment.CenterVertically) {
            Box {
                MbIconButton(MbIcons.Shard, "Передать предмет", { attachMenuOpen = true })
                DropdownMenu(expanded = attachMenuOpen, onDismissRequest = { attachMenuOpen = false }) {
                    DropdownMenuItem(text = { Text("Передать шард") }, onClick = { attachMenuOpen = false; onQuickItem(ItemKind.SHARD, peerPubKeyB64) })
                    DropdownMenuItem(text = { Text("Передать демона") }, onClick = { attachMenuOpen = false; onQuickItem(ItemKind.DAEMON, peerPubKeyB64) })
                }
            }
            Box(Modifier.weight(1f)) {
                MbComposer(
                    value = draft,
                    onValueChange = { draft = it },
                    onSend = { if (draft.isNotBlank()) { thread.send(draft); draft = "" } },
                    placeholder = if (peer != null) "Личное сообщение" else "Личное сообщение (получатель не в сети)"
                )
            }
        }
    }
}

private fun shortKey(key: String): String = if (key.length <= 8) key else "${key.take(4)}…${key.takeLast(3)}"

/** Список контактов для старта НОВОГО диалога (кнопка «+» в инбоксе) — не путать с самим инбоксом уже идущих переписок. */
@Composable
private fun NewChatPicker(directory: ContactsView, onPick: (String) -> Unit, onBack: () -> Unit) {
    val contacts = directory.contacts
    var query by remember { mutableStateOf("") }
    val filtered = remember(contacts, query) {
        if (query.isBlank()) contacts
        else contacts.filter { it.callsign.contains(query, ignoreCase = true) || it.faction.contains(query, ignoreCase = true) }
    }

    Column(Modifier.fillMaxSize().padding(horizontal = MbDimens.screenPadding)) {
        MbBreadcrumb(parts = listOf("Новый чат")) { MbIconButton(MbIcons.Close, "Назад", onBack) }
        Spacer(Modifier.height(MbDimens.blockGap))

        if (contacts.isEmpty()) {
            Box(Modifier.weight(1f)) {
                MbEmptyState(MbIcons.User, "Контактов пока нет", "Отсканируйте QR-код другого игрока в Профиле, чтобы начать с ним переписку.")
            }
            return@Column
        }
        if (filtered.isEmpty()) {
            Box(Modifier.weight(1f)) { MbEmptyState(MbIcons.User, "Ничего не нашлось", "Попробуйте другой позывной или фракцию.") }
            return@Column
        }
        LazyColumn(Modifier.weight(1f)) {
            items(filtered, key = { it.publicKeyB64 }) { c ->
                MbListItem(
                    title = c.callsign,
                    sub = c.faction,
                    lead = { Icon(painterResource(MbIcons.User), contentDescription = null) },
                    onClick = { onPick(c.publicKeyB64) }
                )
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
    is Mb10Qr.Transaction -> "Перевод ${formatMoney(decoded.amount)}" + if (decoded.memo.isNotBlank()) " · ${decoded.memo}" else ""
    is Mb10Qr.ItemTransfer -> "Передача: «" + (ItemPayload.decodeShard(decoded.payload)?.title ?: ItemPayload.decodeDaemon(decoded.payload)?.name ?: "предмет") + "»"
    is Mb10Qr.Receipt -> "Платёж подтверждён"
    is Mb10Qr.SecurityAlert -> "Тревога! · «${decoded.containerName}»"
    else -> body
}

@Composable
private fun ColumnScope.MessageList(
    messages: List<ChatMessageEntity>,
    myPubKey: String,
    showSender: Boolean,
    emptyText: String,
    transactions: List<TransactionEntity> = emptyList(),
    itemTransfers: List<ItemTransferEntity> = emptyList(),
    onAcceptItem: ((Mb10Qr.ItemTransfer) -> Unit)? = null,
    onAcceptTransaction: ((Mb10Qr.Transaction) -> Unit)? = null
) {
    if (messages.isEmpty()) {
        Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
            MbEmptyState(MbIcons.Chat, "Пока тихо", emptyText)
        }
        return
    }
    val entries = remember(messages) { buildChatEntries(messages) }
    // Экран должен показывать конец переписки: при открытии — сразу низ, при новых сообщениях — плавно вниз, если читатель и так был у низа
    // (иначе он листает историю, и мы его не дёргаем). Раньше список всегда стартовал сверху, и свежая карточка перевода оказывалась за краем экрана.
    val listState = rememberLazyListState()
    var firstScrollDone by remember { mutableStateOf(false) }
    LaunchedEffect(entries.size) {
        if (entries.isEmpty()) return@LaunchedEffect
        val info = listState.layoutInfo
        val lastVisible = info.visibleItemsInfo.lastOrNull()?.index ?: -1
        val atBottom = lastVisible >= info.totalItemsCount - 2
        if (!firstScrollDone) listState.scrollToItem(entries.lastIndex)
        else if (atBottom) listState.animateScrollToItem(entries.lastIndex)
        firstScrollDone = true
    }
    LazyColumn(state = listState, modifier = Modifier.weight(1f)) {
        items(entries) { entry ->
            when (entry) {
                is ChatEntry.DaySeparator -> Box(Modifier.fillMaxWidth().padding(vertical = MbDimens.blockGap)) { MbDaySep(entry.label) }
                is ChatEntry.Msg -> MessageBubble(
                    msg = entry.message,
                    self = entry.message.fromPubKeyB64 == myPubKey,
                    showSender = showSender,
                    transactions = transactions,
                    itemTransfers = itemTransfers,
                    onAcceptItem = onAcceptItem,
                    onAcceptTransaction = onAcceptTransaction
                )
            }
        }
    }
}

/**
 * Своё сообщение — справа (зелёное), чужое — слева (тёмное с бирюзовой рамкой) — MbBubble уже несёт этот смысл формой
 * и цветом (раздел 5 гайдлайна). Тело сообщения может оказаться сериализованным переводом/чеком (тот же формат, что
 * раньше шёл в QR) — тогда вместо текстового пузыря рисуется платёжный, с кнопкой «Принять» прямо в ленте.
 */
@Composable
internal fun MessageBubble(
    msg: ChatMessageEntity,
    self: Boolean,
    showSender: Boolean,
    transactions: List<TransactionEntity> = emptyList(),
    itemTransfers: List<ItemTransferEntity> = emptyList(),
    onAcceptItem: ((Mb10Qr.ItemTransfer) -> Unit)? = null,
    onAcceptTransaction: ((Mb10Qr.Transaction) -> Unit)? = null
) {
    val decoded = remember(msg.body) { Mb10QrCodec.decode(msg.body) }
    val c = LocalMbColors.current
    Row(Modifier.fillMaxWidth().padding(bottom = MbDimens.rowGap), horizontalArrangement = if (self) Arrangement.End else Arrangement.Start) {
        when (decoded) {
            is Mb10Qr.Transaction -> MbPayBubble(
                head = if (self) "Перевод отправлен" else "Перевод от ${msg.fromCallsign}",
                value = formatMoney(decoded.amount),
                fromMe = self,
                modifier = Modifier.widthIn(max = 260.dp)
            ) {
                val status = transactions.find { it.id == decoded.id }?.status
                if (decoded.memo.isNotBlank()) Text(decoded.memo, style = MbTypography.rowSub, color = c.ink2)
                PaymentOrItemStatus(self, status, onAccept = if (self) null else { { onAcceptTransaction?.invoke(decoded) } })
            }
            is Mb10Qr.ItemTransfer -> {
                val shard = remember(decoded.payload) { if (decoded.kind == ItemKind.SHARD) ItemPayload.decodeShard(decoded.payload) else null }
                val daemon = remember(decoded.payload) { if (decoded.kind == ItemKind.DAEMON) ItemPayload.decodeDaemon(decoded.payload) else null }
                val title = shard?.title ?: daemon?.name ?: "предмет"
                val details = when {
                    shard != null -> "Шард · тир ${shard.tier}" + if (shard.decryptAction && !shard.decrypted) " · зашифрован" else ""
                    daemon != null -> "Демон · тир ${daemon.tier.level} · ${daemon.effect.label()}"
                    else -> ""
                }
                val record = itemTransfers.find { it.id == decoded.id }
                MbPayBubble(
                    head = if (self) "Передача отправлена" else "Передача от ${msg.fromCallsign}",
                    value = "«$title»",
                    fromMe = self,
                    modifier = Modifier.widthIn(max = 280.dp)
                ) {
                    Text(details, style = MbTypography.rowSub, color = c.ink2)
                    PaymentOrItemStatus(self, record?.status, onAccept = if (self || record != null) null else { { onAcceptItem?.invoke(decoded) } }, cancelledWhenNull = true)
                }
            }
            is Mb10Qr.Receipt -> MbTag("получение подтверждено", tone = MbTagTone.Ok)
            is Mb10Qr.SecurityAlert -> SecurityAlertTag(decoded)
            else -> PlainMessageBubble(msg, self, showSender)
        }
    }
}

@Composable
private fun PaymentOrItemStatus(self: Boolean, status: String?, onAccept: (() -> Unit)?, cancelledWhenNull: Boolean = false) {
    when {
        self -> {
            val (text, tone) = when (status) {
                TransactionStatus.CONFIRMED -> "подтверждено" to MbStatusTone.Ok
                TransactionStatus.DELIVERED -> "доставлено, ждёт принятия" to MbStatusTone.Warn
                null -> (if (cancelledWhenNull) "отменено" else "не доставлено") to MbStatusTone.Dim
                else -> "не доставлено" to MbStatusTone.Bad
            }
            MbStatusText(text, tone)
        }
        onAccept != null -> MbButton("Принять", onClick = onAccept, inline = true)
        else -> MbStatusText("принято", MbStatusTone.Ok)
    }
}

/** Сигнал СБ (SecAlertStore) приходит телом обычного фракционного сообщения — тег вместо пузыря, тир контейнера не показываем: это служебное деление сложности взлома для мастера. */
@Composable
private fun SecurityAlertTag(alert: Mb10Qr.SecurityAlert) {
    val parts = buildList {
        add("Тревога!")
        add("«${alert.containerName}»")
        alert.intruderCallsign?.let(::add)
        alert.preciseAt?.let { add(SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(it)) }
    }
    MbTag(parts.joinToString(" · "), tone = MbTagTone.Bad)
}

@Composable
private fun PlainMessageBubble(msg: ChatMessageEntity, self: Boolean, showSender: Boolean) {
    val timeFormat = remember { SimpleDateFormat("HH:mm", Locale.getDefault()) }
    val mark = if (self) statusMark(msg.status) else null
    val meta = timeFormat.format(msg.timestamp) + (mark?.let { " ${it.first}" } ?: "")
    Column(Modifier.widthIn(max = 280.dp), horizontalAlignment = if (self) Alignment.End else Alignment.Start) {
        if (showSender && !self) {
            Text(msg.fromCallsign, style = MbTypography.meta, color = LocalMbColors.current.ink2)
            Spacer(Modifier.height(2.dp))
        }
        MbBubble(fromMe = self, text = msg.body, meta = meta)
    }
}

/**
 * Отметка у своего личного сообщения (MessageStatus, docs/refactor-plan.md D3): «…» — не ушло (ждёт адресата в очереди),
 * «✓» — ушло без подтверждения, «✓✓» — адресат сохранил, «✓✓» цветом — прочитал. null — без отметки (фракционное, старое).
 */
internal fun statusMark(status: Int): Pair<String, Boolean>? = when (status) {
    MessageStatus.PENDING -> "…" to false
    MessageStatus.SENT -> "✓" to false
    MessageStatus.DELIVERED -> "✓✓" to false
    MessageStatus.READ -> "✓✓" to true
    else -> null
}
