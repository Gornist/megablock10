package com.megablok10.app.di

import com.megablok10.app.breach.BreachViewModel
import com.megablok10.app.ui.SessionViewModel
import com.megablok10.app.ui.screens.AnnouncementsViewModel
import com.megablok10.app.ui.screens.CallsViewModel
import com.megablok10.app.ui.screens.ChatViewModel
import com.megablok10.app.ui.screens.ContactsViewModel
import com.megablok10.app.ui.screens.CyberdeckViewModel
import com.megablok10.app.ui.screens.DirectThreadViewModel
import com.megablok10.app.ui.screens.SettingsViewModel
import com.megablok10.app.ui.screens.ThreadFeed
import com.megablok10.app.ui.screens.WalletViewModel
import kotlinx.coroutines.flow.combine

/*
 * Сборка ViewModel экранов из графа — здесь, а не в экранах: экран просит `appViewModel { walletViewModel() }` и не знает, из чего
 * она сделана. Долгие действия (деньги, награда, сброс) ViewModel запускают в processScope — их нельзя бросить на полпути.
 */

fun AppGraph.sessionViewModel() = SessionViewModel(
    identityStore = identity,
    peers = peerDirectory.online,
    provisioning = provisioning::apply,
    create = createCharacter,
    reset = { sessionReset.perform(it) },
    onUiStarted = { announcements.load(); session.onUiStarted() },
    notices = notices,
    work = processScope,
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
    markRead = readReceipts::onThreadShown,
    showRead = readReceiptSetting.enabled,
)

fun AppGraph.cyberdeckViewModel() =
    CyberdeckViewModel(identity.state, daemons, shards, directory, ramUpgrades::apply, rewards::applyGrant, sendItem, notices, processScope)

fun AppGraph.breachViewModel() = BreachViewModel(identity.state, checkBreachAccess, finishBreach, processScope)

fun AppGraph.settingsViewModel() =
    SettingsViewModel(collectorSettings, observePendingChanges(), peerDirectory.online, { collectorSync.wake() }, ::deviceReport, readReceiptSetting)
