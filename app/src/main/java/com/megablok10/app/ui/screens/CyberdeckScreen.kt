package com.megablok10.app.ui.screens

import com.megablok10.app.ui.theme.AppSnack
import androidx.activity.compose.BackHandler
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.megablok10.app.breach.BreachAccess
import com.megablok10.app.breach.BreachBlock
import com.megablok10.app.breach.BreachContainerFlow
import com.megablok10.app.breach.CodePill
import com.megablok10.app.breach.Container
import com.megablok10.app.breach.cellsLabel
import com.megablok10.app.breach.DecryptRules
import com.megablok10.app.items.ItemTransferStore
import com.megablok10.app.items.OutgoingItem
import com.megablok10.app.breach.Daemon
import com.megablok10.app.breach.LootType
import com.megablok10.app.breach.ShardDecryptFlow
import com.megablok10.app.breach.label
import com.megablok10.app.identity.Identity
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.qr.rememberMb10QrScanner
import com.megablok10.app.ui.LocalAppGraph
import com.megablok10.app.ui.theme.ChamferedSurface
import com.megablok10.app.ui.theme.DottedDivider
import com.megablok10.app.ui.theme.ScanFab
import com.megablok10.app.ui.theme.CompactActionButton
import com.megablok10.app.ui.theme.EmptyState
import com.megablok10.app.ui.theme.HexBullet
import com.megablok10.app.ui.theme.IBMPlexSans
import com.megablok10.app.ui.theme.JetBrainsMono
import com.megablok10.app.ui.theme.MB10Colors
import com.megablok10.app.ui.theme.SegmentedTabs
import kotlinx.coroutines.launch

/**
 * Демоны и Шарды — два составных одной Кибердеки, не отдельные экраны:
 * оба населяются через один и тот же объект-сканер на площадке (QR
 * контейнера или QR шарда — визуально не отличить издалека, игрок не
 * должен заранее знать, что перед ним, чтобы выбрать "правильную" кнопку
 * скана). Единая кнопка "Сканировать объект" наверху разруливает по
 * фактическому типу декодированного QR, а не по вкладке, которая открыта
 * в моменте.
 */
@Composable
fun CyberdeckScreen(
    identity: Identity,
    onNestedChange: (Boolean) -> Unit = {},
    presetPeerKey: String? = null,
    initialSegment: Int? = null,
    onPresetConsumed: () -> Unit = {}
) {
    val graph = LocalAppGraph.current
    val scope = rememberCoroutineScope()
    LaunchedEffect(Unit) { graph.daemons.ensureSeeded() }
    val daemons by remember { graph.daemons.observeAll() }.collectAsState(initial = emptyList())
    val shards by remember { graph.shards.observeAll() }.collectAsState(initial = emptyList())
    val contacts by remember { graph.contacts.observeAll() }.collectAsState(initial = emptyList())

    var segment by rememberSaveable { mutableStateOf(0) } // 0 = Демоны, 1 = Шарды; переживает смену вкладки приложения
    // Пришли из треда чата (кнопка со скрепкой у "Отправить") — получатель уже выбран, картинка контактов не нужна:
    // остаётся выбрать конкретный шард/демон, и он уйдёт сразу этому игроку.
    var itemRecipientPreset by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(presetPeerKey, initialSegment) {
        if (initialSegment != null) segment = initialSegment
        if (presetPeerKey != null) { itemRecipientPreset = presetPeerKey; onPresetConsumed() }
    }
    var container by remember { mutableStateOf<Container?>(null) }
    var openedShard by remember { mutableStateOf<Mb10Qr.Shard?>(null) }
    var decryptingShard by remember { mutableStateOf<Mb10Qr.Shard?>(null) }
    var scanIssue by remember { mutableStateOf<ScanIssue?>(null) }
    // Что сейчас передаём другому игроку (шард или демон) — до выбора получателя в диалоге.
    var transferShard by remember { mutableStateOf<Mb10Qr.Shard?>(null) }
    var transferDaemon by remember { mutableStateOf<Daemon?>(null) }
    // Идёт таймер взлома: шапка и навигация приложения прячутся, взлом получает весь экран.
    var breachRunning by remember { mutableStateOf(false) }

    // Системная «Назад» ведёт на уровень выше, а не выкидывает из приложения. Во время таймера взлома она заблокирована:
    // случайный жест не должен сжигать попытку — выйти можно только кнопками экрана.
    BackHandler(enabled = openedShard != null || decryptingShard != null || container != null) {
        when {
            breachRunning -> Unit
            decryptingShard != null -> { openedShard = decryptingShard; decryptingShard = null }
            openedShard != null -> openedShard = null
            else -> container = null
        }
    }

    // Деталь шарда и мини-взлом — полноэкранные, со своим back-заголовком; шапка приложения над ними была бы дублем.
    LaunchedEffect(openedShard, decryptingShard, breachRunning) { onNestedChange(openedShard != null || decryptingShard != null || breachRunning) }

    val scanObject = rememberMb10QrScanner { qr ->
        scanIssue = null
        when (qr) {
            // Связь, остывание узла и остаток слотов проверяются ДО выбора демонов (сценарий CheckBreachAccess).
            is Mb10Qr.ContainerQr -> scope.launch {
                when (val access = graph.checkBreachAccess(identity, qr.container)) {
                    BreachAccess.Open -> { container = qr.container; segment = 0 }
                    is BreachAccess.Blocked -> scanIssue = scanIssueOf(access)
                }
            }
            is Mb10Qr.Shard -> { scope.launch { graph.shards.add(qr) }; segment = 1 }
            is Mb10Qr.RamUpgrade -> {
                scope.launch {
                    val newCapacity = graph.ramUpgrades.apply(qr)
                    val message = if (newCapacity != null) "RAM деки увеличена до $newCapacity" else "Этот RAM-токен уже был применён"
                    AppSnack.show(message)
                }
            }
            is Mb10Qr.LootGrant -> {
                scope.launch {
                    val granted = graph.rewards.applyGrant(qr)
                    val message = granted ?: "Фрагмент повреждён — обратитесь к мастеру"
                    AppSnack.show(message)
                    segment = if (qr.type == LootType.DAEMON) 0 else 1
                }
            }
            else -> AppSnack.show("Этот QR не распознан Кибердекой")
        }
    }

    val decrypting = decryptingShard
    if (decrypting != null) {
        ShardDecryptFlow(
            shard = decrypting,
            onDecrypted = {
                scope.launch { graph.shards.markDecrypted(decrypting.id) }
                decryptingShard = null
                openedShard = decrypting.copy(decrypted = true)
            },
            onCancel = { decryptingShard = null; openedShard = decrypting }
        )
        return
    }

    fun performTransfer(toKeyB64: String, label: String) {
        val shard = transferShard
        val daemon = transferDaemon
        transferShard = null
        transferDaemon = null
        scope.launch {
            val card = when {
                shard != null -> graph.sendItem(identity, OutgoingItem.Shard(shard.id), toKeyB64)
                daemon != null -> graph.sendItem(identity, OutgoingItem.Daemon(daemon), toKeyB64)
                else -> null
            }
            if (card == null) {
                AppSnack.show("Не удалось передать")
                return@launch
            }
            openedShard = null
            AppSnack.show("Передача отправлена: $label")
        }
    }
    fun sendTo(contact: Mb10Qr.Contact) = performTransfer(contact.publicKeyB64, contact.callsign)

    /** Начать передачу: если пришли из чата с уже известным получателем (см. presetPeerKey), отправляем сразу, без диалога выбора. */
    fun startTransfer(shard: Mb10Qr.Shard?, daemon: Daemon?) {
        val preset = itemRecipientPreset
        if (preset != null) {
            transferShard = shard
            transferDaemon = daemon
            val label = contacts.find { it.publicKeyB64 == preset }?.callsign ?: "получателю"
            performTransfer(preset, label)
        } else {
            transferShard = shard
            transferDaemon = daemon
        }
    }
    if (transferShard != null || transferDaemon != null) {
        ContactPickerDialog(
            title = "Кому передать «${transferShard?.title ?: transferDaemon?.name}»?",
            onPick = ::sendTo,
            onDismiss = { transferShard = null; transferDaemon = null }
        )
    }

    val opened = openedShard
    if (opened != null) {
        ShardDetailOverlay(
            shard = opened,
            decrypter = DecryptRules.bestDecrypter(daemons, opened.tier),
            onTransfer = { startTransfer(shard = opened, daemon = null) },
            onClose = { openedShard = null },
            // "Расшифровать" — открывает мини-взлом этого конкретного шарда
            // (ShardDecryptFlow), а не общий сегмент "Демоны".
            onOpenHack = { openedShard = null; decryptingShard = opened }
        )
        return
    }

    // Выбранный контейнер — взлом на весь экран, без вкладок и кнопки сканирования (отмена и выход — внутри потока).
    val activeContainer = container
    if (activeContainer != null) {
        BreachContainerFlow(
            container = activeContainer, daemons = daemons, identity = identity,
            onRescan = { container = null }, onImmersive = { breachRunning = it }
        )
        return
    }

    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().padding(horizontal = 12.dp).padding(top = 4.dp)) {
            scanIssue?.let { issue ->
                ScanIssueCard(issue, onDismiss = { scanIssue = null })
                Spacer(Modifier.height(8.dp))
            }
            SegmentedTabs(listOf("Демоны", "Шарды"), selected = segment, onSelect = { segment = it })
            Spacer(Modifier.height(6.dp))

            Box(Modifier.weight(1f)) {
                if (segment == 0) {
                    DemonsSegment(daemons = daemons, onTransfer = { startTransfer(shard = null, daemon = it) })
                } else {
                    ShardsSegment(shards = shards, onOpen = { openedShard = it })
                }
            }
        }
        // Главное действие экрана — в зоне большого пальца, не съедает высоту списка.
        ScanFab(onClick = scanObject, modifier = Modifier.align(Alignment.BottomEnd).padding(end = 16.dp, bottom = 16.dp))
    }
}

@Composable
private fun DemonsSegment(daemons: List<Daemon>, onTransfer: (Daemon) -> Unit) {
    // Вступительный текст нужен только пока коллекция пуста — дальше это уже не подсказка, а шум над списком.
    if (daemons.isEmpty()) {
        EmptyState("Демонов пока нет. Отсканируйте контейнер кнопкой «Сканировать» — так начнётся коллекция.")
        return
    }

    // Раскрыта одна строка за раз: тап — детали и действие «Передать»; в свёрнутом виде строка ≈ 48 dp.
    var expandedId by remember { mutableStateOf<String?>(null) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(bottom = 88.dp)) {
        daemons.forEach { daemon ->
            DaemonRow(
                daemon = daemon,
                expanded = expandedId == daemon.id,
                onToggle = { expandedId = if (expandedId == daemon.id) null else daemon.id },
                onTransfer = if (ItemTransferStore.isTransferable(daemon)) { { onTransfer(daemon) } } else null
            )
            DottedDivider()
        }
    }
}

/** Почему взлом отсканированного контейнера не начался — карточка над списком (запись мастеру делает сценарий CheckBreachAccess). */
private fun scanIssueOf(blocked: BreachAccess.Blocked): ScanIssue = when (blocked.reason) {
    BreachBlock.NO_LINK -> ScanIssue("НЕТ СВЯЗИ", "Дека вне зоны сети Мегаблока. Взлом недоступен без подключения к узлу связи.")
    BreachBlock.COOLDOWN -> ScanIssue("УЗЕЛ ОСТЫВАЕТ", "Повторное подключение к этому узлу возможно через ${blocked.cooldownMinutes} мин.")
    BreachBlock.EXHAUSTED -> ScanIssue("КЭШ ОЧИЩЕН", "Все слоты узла исчерпаны — здесь больше нечего извлекать.")
}

/** Плотная строка демона: имя и коды в одной строке, эффект и цена — во второй; «Передать» появляется по тапу. */
@Composable
private fun DaemonRow(daemon: Daemon, expanded: Boolean, onToggle: () -> Unit, onTransfer: (() -> Unit)?) {
    Column(
        Modifier.fillMaxWidth()
            .then(if (onTransfer != null) Modifier.clickable(onClick = onToggle) else Modifier)
            .padding(vertical = 7.dp, horizontal = 2.dp)
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(
                "${daemon.name} · ${daemon.tier.label}",
                color = MB10Colors.inkPrimary, fontFamily = IBMPlexSans, fontSize = 13.5.sp,
                maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f)
            )
            Row { daemon.sequence.forEach { code -> CodePill(code) } }
            if (onTransfer != null) {
                Text(if (expanded) "▴" else "▾", color = MB10Colors.inkTertiary, fontFamily = JetBrainsMono, fontSize = 12.sp, modifier = Modifier.padding(start = 8.dp))
            }
        }
        // Стоимость видна и вне активного взлома — иначе бюджет буфера (RAM) узнаётся только внутри уже начатой попытки.
        Text(
            "${daemon.effect.label()} · ${cellsLabel(daemon.sequence.size)}",
            color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 11.sp
        )
        if (expanded && onTransfer != null) {
            Spacer(Modifier.height(8.dp))
            CompactActionButton("Передать другому игроку", onClick = onTransfer)
        }
    }
}

@Composable
private fun ShardsSegment(shards: List<Mb10Qr.Shard>, onOpen: (Mb10Qr.Shard) -> Unit) {
    if (shards.isEmpty()) {
        EmptyState("Пока нет отсканированных шардов. Отсканируйте QR-метку кнопкой выше.")
        return
    }
    LazyColumn(Modifier.fillMaxSize()) {
        items(shards, key = { it.id }) { shard -> ShardCard(shard, onClick = { onOpen(shard) }) }
    }
}

/** Почему скан контейнера не открыл выбор демонов — заголовок + объяснение. */
private data class ScanIssue(val title: String, val message: String)

/**
 * Постоянная карточка вместо Toast — Toast сам исчезает через пару секунд и
 * не даёт места ни для объяснения причины, ни для повторной попытки; эта
 * остаётся на экране, пока игрок сам её не закроет или не отсканирует снова.
 */
@Composable
private fun ScanIssueCard(issue: ScanIssue, onDismiss: () -> Unit) {
    ChamferedSurface(
        borderColor = MB10Colors.accentDanger, fillColor = MB10Colors.surfaceRaised, cut = 8.dp, contentPadding = 12.dp,
        modifier = Modifier.fillMaxWidth()
    ) {
        Column {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    HexBullet(MB10Colors.accentDanger, size = 7.dp)
                    Spacer(Modifier.width(6.dp))
                    Text(issue.title, color = MB10Colors.accentDanger, fontFamily = JetBrainsMono, fontSize = 11.sp, fontWeight = FontWeight.Medium)
                }
                Text(
                    "✕", color = MB10Colors.inkTertiary, fontFamily = JetBrainsMono, fontSize = 13.sp,
                    modifier = Modifier.clickable(onClick = onDismiss).padding(4.dp)
                )
            }
            Spacer(Modifier.height(6.dp))
            Text(issue.message, color = MB10Colors.inkSecondary, fontFamily = IBMPlexSans, fontSize = 12.sp, lineHeight = 16.sp)
        }
    }
}
