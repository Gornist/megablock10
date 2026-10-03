package com.megablok10.app.ui.screens

import androidx.activity.compose.BackHandler
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.megablok10.app.breach.BreachContainerFlow
import com.megablok10.app.breach.DecryptRules
import com.megablok10.app.breach.Daemon
import com.megablok10.app.breach.ShardDecryptFlow
import com.megablok10.app.breach.label
import com.megablok10.app.identity.Identity
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.qr.rememberMb10QrScanner
import com.megablok10.app.di.breachViewModel
import com.megablok10.app.di.cyberdeckViewModel
import com.megablok10.app.di.netrunViewModel
import com.megablok10.app.netrun.NetrunEntryState
import com.megablok10.app.ui.appViewModel
import com.megablok10.app.ui.theme.AppSnack

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
    // Вход в «Сеть»: выбор деки после скана QR стойки и ход входа — у персонажа свои.
    val netrun = appViewModel(key = "netrun:${identity.publicKeyB64}") { netrunViewModel() }
    val rack by netrun.rack.collectAsStateWithLifecycle()
    val netrunState by netrun.entryState.collectAsStateWithLifecycle()
    val state by deck.state.collectAsStateWithLifecycle()
    val daemons = state.daemons
    val shards = state.shards
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
    // Выбор деки для входа в Сеть: отмеченные демоны и защищённый слот (сбрасываются, когда стойка закрыта).
    var netrunChosen by remember { mutableStateOf<Set<String>>(emptySet()) }
    var netrunProtected by remember { mutableStateOf<String?>(null) }
    // Кнопка «Войти в Сеть» ждёт именно QR стойки; общий «Сканер» принимает и стойку, и всё остальное.
    var wantRack by remember { mutableStateOf(false) }

    // Системная «Назад» ведёт на уровень выше, а не выкидывает из приложения. Во время таймера взлома она заблокирована:
    // случайный жест не должен сжигать попытку — выйти можно только кнопками экрана.
    val inNetrun = rack != null || netrunState != NetrunEntryState.Idle
    BackHandler(enabled = decryptingShard != null || container != null || inNetrun) {
        when {
            rack != null -> netrun.closePicker()
            netrunState != NetrunEntryState.Idle -> netrun.dismiss()
            breachRunning -> Unit
            decryptingShard != null -> decryptingShard = null
            else -> breach.close()
        }
    }

    // Мини-взлом дешифровки — полноэкранный, со своим back-заголовком; шапка оболочки над ним была бы дублем.
    LaunchedEffect(decryptingShard, breachRunning, inNetrun) { onNestedChange(decryptingShard != null || breachRunning || inNetrun) }

    // Одна кнопка скана на всё: контейнер проверяется перед взломом (BreachViewModel → CheckBreachAccess — связь, остывание узла,
    // остаток слотов), остальное — шард, RAM-токен, фрагмент лута — применяет Кибердека.
    val scanObject = rememberMb10QrScanner { qr ->
        breach.dismissIssue()
        val rackOnly = wantRack
        wantRack = false
        when {
            qr is Mb10Qr.Rack -> { netrunChosen = emptySet(); netrunProtected = null; netrun.openRack(qr) }
            rackOnly -> AppSnack.show("Это не QR стойки")
            qr is Mb10Qr.ContainerQr -> breach.open(qr.container)
            else -> deck.onScan(qr)
        }
    }

    // Вход в Сеть: сначала выбор деки, потом ход входа — оба на весь экран, как взлом.
    val activeRack = rack
    if (activeRack != null) {
        NetrunDeckPicker(
            rack = activeRack, daemons = daemons, ramCapacity = identity.ramCapacity,
            chosen = netrunChosen, protectedId = netrunProtected,
            onToggle = { id ->
                netrunChosen = if (id in netrunChosen) netrunChosen - id else netrunChosen + id
                // Первый выбранный демон становится защищённым сам; снятый с деки теряет защиту.
                if (netrunProtected == id && id !in netrunChosen) netrunProtected = null
                if (netrunProtected == null) netrunProtected = netrunChosen.firstOrNull()
            },
            onProtect = { netrunProtected = it },
            onEnter = { netrun.enter(daemons.filter { it.id in netrunChosen }, netrunProtected.orEmpty()) },
            onCancel = netrun::closePicker
        )
        return
    }
    if (netrunState != NetrunEntryState.Idle) {
        NetrunStatus(netrunState, onRetry = netrun::retry, onClose = netrun::dismiss)
        return
    }

    val decrypting = decryptingShard
    if (decrypting != null) {
        ShardDecryptFlow(
            shard = decrypting,
            isHintSeen = breach::isHintSeen, onHintSeen = breach::markHintSeen,
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
        val shard = transferShard
        val daemon = transferDaemon
        transferShard = null
        transferDaemon = null
        // Карточка ушла — деталь шарда закрываем (его у игрока больше нет); не ушла — Кибердека скажет «Не удалось передать».
        deck.transferChosen(shard, daemon, toKeyB64, label, onSent = { openedShard = null })
    }
    fun sendTo(contact: Mb10Qr.Contact) = performTransfer(contact.publicKeyB64, contact.callsign)

    /** Начать передачу: если пришли из чата с уже известным получателем (см. presetPeerKey), отправляем сразу, без диалога выбора. */
    fun startTransfer(shard: Mb10Qr.Shard?, daemon: Daemon?) {
        transferShard = shard
        transferDaemon = daemon
        itemRecipientPreset?.let { performTransfer(it, deck.recipientLabel(it)) }
    }

    // Выбранный контейнер — взлом на весь экран, без вкладок и кнопки сканирования (отмена и выход — внутри потока).
    val activeContainer = container
    if (activeContainer != null) {
        BreachContainerFlow(
            container = activeContainer, daemons = daemons, identity = identity,
            onRescan = breach::close, onImmersive = { breachRunning = it },
            isHintSeen = breach::isHintSeen, onHintSeen = breach::markHintSeen,
            finish = { result, seed, onDone -> breach.finish(activeContainer, result, seed, onDone) }
        )
        return
    }

    CyberdeckMain(
        scanIssue = scanIssue, onDismissIssue = breach::dismissIssue,
        segment = segment, onSelectSegment = deck::selectSegment,
        daemons = daemons, shards = shards,
        onTransferDaemon = { startTransfer(shard = null, daemon = it) },
        onOpenShard = { openedShard = it },
        onEnterNetrun = { wantRack = true; scanObject() },
        onScan = { wantRack = false; scanObject() }
    )

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
