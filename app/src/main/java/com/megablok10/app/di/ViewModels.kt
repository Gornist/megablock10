package com.megablok10.app.di

import com.megablok10.app.breach.BreachViewModel
import com.megablok10.app.call.CallPhase
import com.megablok10.app.ui.SessionViewModel
import com.megablok10.app.ui.ShellViewModel
import com.megablok10.app.ui.screens.AnnouncementsViewModel
import com.megablok10.app.ui.screens.CallsViewModel
import com.megablok10.app.ui.screens.ChatViewModel
import com.megablok10.app.ui.screens.ContactsViewModel
import com.megablok10.app.ui.screens.NetrunViewModel
import com.megablok10.app.ui.screens.CyberdeckViewModel
import com.megablok10.app.ui.screens.DirectThreadViewModel
import com.megablok10.app.ui.screens.SettingsViewModel
import com.megablok10.app.ui.screens.ThreadFeed
import com.megablok10.app.ui.screens.WalletViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn

/*
 * Сборка ViewModel экранов из графа — здесь, а не в экранах: экран просит `appViewModel { walletViewModel() }` и не знает, из чего
 * она сделана. Долгие действия (деньги, награда, сброс) ViewModel запускают в processScope — их нельзя бросить на полпути.
 */

fun AppGraph.sessionViewModel() = SessionViewModel(
    identityStore = identity,
    peers = visiblePlayers,
    provisioning = provisioning::apply,
    create = createCharacter,
    reset = { sessionReset.perform(it) },
    onUiStarted = { announcements.load(); session.onUiStarted() },
    notices = notices,
    work = processScope,
)

fun AppGraph.shellViewModel() = ShellViewModel(
    identity = identity.state,
    balance = wallet.observeBalance(),
    unreadChatThreads = shellBadges::unreadChatThreads,
    missedCalls = shellBadges.missedCalls(),
    markChatSeen = shellBadges::markChatSeen,
    markCallsSeen = shellBadges::markCallsSeen,
)

fun AppGraph.announcementsViewModel() = AnnouncementsViewModel(announcements)

fun AppGraph.callsViewModel() = CallsViewModel(calls, identity.state, directory)

fun AppGraph.contactsViewModel() = ContactsViewModel(directory, processScope)

fun AppGraph.walletViewModel() = WalletViewModel(identity.state, wallet, directory, sendPayment, notices, processScope)

fun AppGraph.chatViewModel() = ChatViewModel(identity.state, chat, directory, processScope)

/** Тред с [peerKey] для персонажа [myKey]: лента из базы привязана к паре ключей (ключ ViewModel — та же пара). */
fun AppGraph.directThreadViewModel(myKey: String, peerKey: String) = DirectThreadViewModel(
    peerKey = peerKey,
    identity = identity.state,
    feed = combine(chat.observeDirect(myKey, peerKey), wallet.observeAll(), items.observeAll(), ::ThreadFeed),
    directory = directory,
    messenger = chat,
    acceptPayment = acceptPayment,
    acceptItem = acceptItem,
    receipts = receipts,
    work = processScope,
    markRead = { me, peer, messages -> readReceipts.onThreadShown(me, peer, messages) },
    showRead = readReceiptSetting.enabled,
    voiceSender = { me, peer, online, clip ->
        // Файл рекордера → хранилище и строка в Room → отправка; промежуточный файл рекордера после этого не нужен.
        val bytes = clip.file.readBytes()
        voice.send(me, peer, online, clip.id, clip.durationMs, clip.waveform, bytes)
        clip.file.delete()
    },
    micAllowed = calls.state.map { it.phase == CallPhase.IDLE }.stateIn(processScope, SharingStarted.Eagerly, true),
    voicePlayer = voicePlayer,
)

fun AppGraph.cyberdeckViewModel() =
    CyberdeckViewModel(identity.state, daemons, shards, directory, ramUpgrades::apply, rewards::applyGrant, sendItem, notices, processScope)

fun AppGraph.netrunViewModel() = NetrunViewModel(identity.state, netrun, processScope)

fun AppGraph.breachViewModel() = BreachViewModel(identity.state, checkBreachAccess, finishBreach, breachHint, processScope)

fun AppGraph.settingsViewModel() =
    SettingsViewModel(collectorSettings, observePendingChanges(), visiblePlayers, { collectorSync.wake() }, ::deviceReport, logStore, readReceiptSetting, collectorClient.reachable, voiceAutoplay)
