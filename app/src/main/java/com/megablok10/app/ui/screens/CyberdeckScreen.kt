package com.megablok10.app.ui.screens

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import com.megablok10.app.breach.BreachAccess
import com.megablok10.app.breach.BreachBlock
import com.megablok10.app.breach.BreachContainerFlow
import com.megablok10.app.breach.cellsLabel
import com.megablok10.app.breach.DecryptRules
import com.megablok10.app.items.ItemTransferStore
import com.megablok10.app.items.OutgoingItem
import com.megablok10.app.breach.Daemon
import com.megablok10.app.breach.ShardDecryptFlow
import com.megablok10.app.breach.label
import com.megablok10.app.identity.Identity
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.qr.rememberMb10QrScanner
import com.megablok10.app.di.breachViewModel
import com.megablok10.app.di.cyberdeckViewModel
import com.megablok10.app.ui.appViewModel
import com.megablok10.app.ui.theme.LocalMbColors
import com.megablok10.app.ui.theme.MbBanner
import com.megablok10.app.ui.theme.MbBannerTone
import com.megablok10.app.ui.theme.MbButton
import com.megablok10.app.ui.theme.MbButtonKind
import com.megablok10.app.ui.theme.MbDimens
import com.megablok10.app.ui.theme.MbEmptyState
import com.megablok10.app.ui.theme.MbIconButton
import com.megablok10.app.ui.theme.MbIcons
import com.megablok10.app.ui.theme.MbListItem
import com.megablok10.app.ui.theme.MbTabItem
import com.megablok10.app.ui.theme.MbTabs
import com.megablok10.app.ui.theme.MbTag
import com.megablok10.app.ui.theme.MbTagTone
import com.megablok10.app.ui.theme.MbTypography

/**
 * Демоны и Шарды — два составных одной Кибердеки, не отдельные экраны:
 * оба населяются через один и тот же объект-сканер на площадке (QR
 * контейнера или QR шарда — визуально не отличить издалека, игрок не
 * должен заранее знать, что перед ним, чтобы выбрать "правильную" кнопку
 * скана). Единая кнопка "Сканировать объект" внизу разруливает по
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
    val deck = appViewModel { cyberdeckViewModel() }
    // Открытый контейнер и отказ при скане — у персонажа свои (ключ ViewModel — ключ личности), см. BreachViewModel.
    val breach = appViewModel(key = "breach:${identity.publicKeyB64}") { breachViewModel() }
    val state by deck.state.collectAsStateWithLifecycle()
    val daemons = state.daemons
    val shards = state.shards
    val contacts = state.contacts.contacts
    // 0 = Демоны, 1 = Шарды; живёт в ViewModel — переживает смену вкладки приложения.
    val segment by deck.segment.collectAsStateWithLifecycle()
    val container by breach.container.collectAsStateWithLifecycle()
    val scanIssue by breach.issue.collectAsStateWithLifecycle()

    // Пришли из треда чата (кнопка со скрепкой у "Отправить") — получатель уже выбран, картинка контактов не нужна:
    // остаётся выбрать конкретный шард/демон, и он уйдёт сразу этому игроку.
    var itemRecipientPreset by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(presetPeerKey, initialSegment) {
        if (initialSegment != null) deck.selectSegment(initialSegment)
        if (presetPeerKey != null) { itemRecipientPreset = presetPeerKey; onPresetConsumed() }
    }
    // Открылся взлом контейнера — после него игрок вернётся к демонам.
    LaunchedEffect(container) { if (container != null) deck.selectSegment(CyberdeckViewModel.SEGMENT_DAEMONS) }
    var openedShard by remember { mutableStateOf<Mb10Qr.Shard?>(null) }
    var decryptingShard by remember { mutableStateOf<Mb10Qr.Shard?>(null) }
    // Что сейчас передаём другому игроку (шард или демон) — до выбора получателя в диалоге.
    var transferShard by remember { mutableStateOf<Mb10Qr.Shard?>(null) }
    var transferDaemon by remember { mutableStateOf<Daemon?>(null) }
    // Идёт таймер взлома: шапка и навигация приложения прячутся, взлом получает весь экран.
    var breachRunning by remember { mutableStateOf(false) }

    // Системная «Назад» ведёт на уровень выше, а не выкидывает из приложения. Во время таймера взлома она заблокирована:
    // случайный жест не должен сжигать попытку — выйти можно только кнопками экрана.
    BackHandler(enabled = decryptingShard != null || container != null) {
        when {
            breachRunning -> Unit
            decryptingShard != null -> decryptingShard = null
            else -> breach.close()
        }
    }

    // Мини-взлом дешифровки — полноэкранный, со своим back-заголовком; шапка оболочки над ним была бы дублем.
    LaunchedEffect(decryptingShard, breachRunning) { onNestedChange(decryptingShard != null || breachRunning) }

    // Одна кнопка скана на всё: контейнер проверяется перед взломом (BreachViewModel → CheckBreachAccess — связь, остывание узла,
    // остаток слотов), остальное — шард, RAM-токен, фрагмент лута — применяет Кибердека.
    val scanObject = rememberMb10QrScanner { qr ->
        breach.dismissIssue()
        if (qr is Mb10Qr.ContainerQr) breach.open(qr.container) else deck.onScan(qr)
    }

    val decrypting = decryptingShard
    if (decrypting != null) {
        ShardDecryptFlow(
            shard = decrypting,
            onDecrypted = {
                deck.markDecrypted(decrypting.id)
                decryptingShard = null
                openedShard = decrypting.copy(decrypted = true)
            },
            onCancel = { decryptingShard = null; openedShard = decrypting }
        )
        return
    }

    fun performTransfer(toKeyB64: String, label: String) {
        val item = transferShard?.let { OutgoingItem.Shard(it.id) } ?: transferDaemon?.let { OutgoingItem.Daemon(it) }
        transferShard = null
        transferDaemon = null
        // Карточка ушла — деталь шарда закрываем (его у игрока больше нет); не ушла — Кибердека скажет «Не удалось передать».
        if (item != null) deck.transfer(item, toKeyB64, label, onSent = { openedShard = null })
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

    // Выбранный контейнер — взлом на весь экран, без вкладок и кнопки сканирования (отмена и выход — внутри потока).
    val activeContainer = container
    if (activeContainer != null) {
        BreachContainerFlow(
            container = activeContainer, daemons = daemons, identity = identity,
            onRescan = breach::close, onImmersive = { breachRunning = it },
            finish = { result, seed, onDone -> breach.finish(activeContainer, result, seed, onDone) }
        )
        return
    }

    Column(Modifier.fillMaxSize().padding(horizontal = MbDimens.screenPadding)) {
        scanIssue?.let { blocked ->
            val issue = scanIssueOf(blocked)
            MbBanner(
                lead = { Icon(painterResource(MbIcons.Alert), contentDescription = null, tint = LocalMbColors.current.bad) },
                title = issue.title,
                sub = issue.message,
                tone = MbBannerTone.Danger,
                action = { MbIconButton(MbIcons.Close, "Закрыть", breach::dismissIssue) }
            )
            Spacer(Modifier.height(MbDimens.blockGap))
        }
        MbTabs(
            items = listOf(MbTabItem(MbIcons.Hack, "Демоны"), MbTabItem(MbIcons.Shard, "Шарды")),
            selected = segment,
            onSelect = deck::selectSegment
        )
        Box(Modifier.weight(1f)) {
            if (segment == CyberdeckViewModel.SEGMENT_DAEMONS) {
                DemonsSegment(daemons = daemons, onTransfer = { startTransfer(shard = null, daemon = it) })
            } else {
                ShardsSegment(shards = shards, onOpen = { openedShard = it })
            }
        }
        MbButton("Сканер", onClick = scanObject, keyIcon = MbIcons.Scan, modifier = Modifier.padding(vertical = MbDimens.blockGap))
    }

    val opened = openedShard
    if (opened != null) {
        ShardDetailDialog(
            shard = opened,
            decrypter = DecryptRules.bestDecrypter(daemons, opened.tier),
            onTransfer = { startTransfer(shard = opened, daemon = null) },
            onClose = { openedShard = null },
            // «Расшифровать» — открывает мини-взлом этого конкретного шарда (ShardDecryptFlow), а не общий сегмент «Демоны».
            onOpenHack = { openedShard = null; decryptingShard = opened }
        )
    }
    if (transferShard != null || transferDaemon != null) {
        ContactPickerDialog(
            title = "Кому передать «${transferShard?.title ?: transferDaemon?.name}»?",
            directory = state.contacts,
            onPick = ::sendTo,
            onDismiss = { transferShard = null; transferDaemon = null }
        )
    }
}

@Composable
private fun DemonsSegment(daemons: List<Daemon>, onTransfer: (Daemon) -> Unit) {
    if (daemons.isEmpty()) {
        MbEmptyState(MbIcons.Hack, "Демонов пока нет", "Отсканируйте контейнер кнопкой «Сканер» — так начнётся коллекция.")
        return
    }
    // Раскрыта одна строка за раз: тап — детали и действие «Передать»; в свёрнутом виде строка ≈ 48 dp.
    var expandedId by remember { mutableStateOf<String?>(null) }
    LazyColumn(Modifier.fillMaxSize()) {
        items(daemons, key = { it.id }) { daemon ->
            DaemonRow(
                daemon = daemon,
                expanded = expandedId == daemon.id,
                onToggle = { expandedId = if (expandedId == daemon.id) null else daemon.id },
                onTransfer = if (ItemTransferStore.isTransferable(daemon)) { { onTransfer(daemon) } } else null
            )
        }
    }
}

/** Почему взлом отсканированного контейнера не начался — карточка над списком (запись мастеру делает сценарий CheckBreachAccess). */
private fun scanIssueOf(blocked: BreachAccess.Blocked): ScanIssue = when (blocked.reason) {
    BreachBlock.NO_LINK -> ScanIssue("Нет связи", "Дека вне зоны сети Мегаблока. Взлом недоступен без подключения к узлу связи.")
    BreachBlock.COOLDOWN -> ScanIssue("Узел остывает", "Повторное подключение к этому узлу возможно через ${blocked.cooldownMinutes} мин.")
    BreachBlock.EXHAUSTED -> ScanIssue("Кэш очищен", "Все слоты узла исчерпаны — здесь больше нечего извлекать.")
}

/** Строка демона (плашка): имя+тир, коды моношрифтом справа, эффект+цена во второй строке; «Передать» появляется по тапу. */
@Composable
private fun DaemonRow(daemon: Daemon, expanded: Boolean, onToggle: () -> Unit, onTransfer: (() -> Unit)?) {
    Column(Modifier.fillMaxWidth().padding(bottom = MbDimens.rowGap)) {
        MbListItem(
            title = "${daemon.name} · ${daemon.tier.label}",
            sub = "${daemon.effect.label()} · ${cellsLabel(daemon.sequence.size)}",
            subWrap = true,
            trail = listOf({ Text(daemon.sequence.joinToString(" "), style = MbTypography.demonCode, color = LocalMbColors.current.acc) }),
            plate = true,
            onClick = onTransfer?.let { onToggle }
        )
        if (expanded && onTransfer != null) {
            MbButton("Передать другому игроку", onClick = onTransfer, inline = true, kind = MbButtonKind.Ghost, modifier = Modifier.padding(top = MbDimens.rowGap))
        }
    }
}

@Composable
private fun ShardsSegment(shards: List<Mb10Qr.Shard>, onOpen: (Mb10Qr.Shard) -> Unit) {
    if (shards.isEmpty()) {
        MbEmptyState(MbIcons.Shard, "Шардов пока нет", "Отсканируйте QR-метку контейнера — найденные шарды появятся здесь.")
        return
    }
    val (locked, open) = shards.partition { resolveBadge(it) == ShardBadge.Locked }
    LazyColumn(Modifier.fillMaxSize()) {
        if (open.isNotEmpty()) {
            items(open, key = { it.id }) { shard -> ShardRow(shard, onClick = { onOpen(shard) }) }
        }
        if (locked.isNotEmpty()) {
            items(locked, key = { it.id }) { shard -> ShardRow(shard, onClick = { onOpen(shard) }) }
        }
    }
}

/** Строка шарда: плашка с «язычком», длинное название — до двух строк; тег справа только для не-обычных состояний. */
@Composable
private fun ShardRow(shard: Mb10Qr.Shard, onClick: () -> Unit) {
    val badge = remember(shard) { resolveBadge(shard) }
    MbListItem(
        title = shard.title,
        sub = shard.meta,
        titleWrap = true,
        trail = when (badge) {
            ShardBadge.Locked -> listOf({ MbTag("нужен дешифратор", tone = MbTagTone.Warn) })
            ShardBadge.Compromised -> listOf({ MbTag(badge.text, tone = MbTagTone.Bad) })
            ShardBadge.Fragment -> listOf({ MbTag(badge.text) })
            ShardBadge.Public -> emptyList()
        },
        plate = true,
        mark = true,
        onClick = onClick
    )
}

private data class ScanIssue(val title: String, val message: String)
