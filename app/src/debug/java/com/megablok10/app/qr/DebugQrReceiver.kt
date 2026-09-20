package com.megablok10.app.qr

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.megablok10.app.DebugConfig
import com.megablok10.app.breach.DaemonEffect
import com.megablok10.app.breach.DaemonStore
import com.megablok10.app.breach.LootCodec
import com.megablok10.app.breach.Tier
import com.megablok10.app.collector.ChangeField
import com.megablok10.app.collector.ChangeReason
import com.megablok10.app.collector.ChangeRecordStore
import com.megablok10.app.collector.CollectorSettings
import com.megablok10.app.data.Mb10Database
import com.megablok10.app.identity.ContactStore
import com.megablok10.app.identity.IdentityManager
import com.megablok10.app.items.ItemTransferStore
import com.megablok10.app.presence.PeerInfo
import com.megablok10.app.presence.PresenceService
import com.megablok10.app.chat.ChatClient
import com.megablok10.app.chat.ChatMessageType
import com.megablok10.app.chat.ChatStore
import com.megablok10.app.chat.ChatWireMessage
import com.megablok10.app.wallet.TransactionStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.launch

/**
 * Отладочные broadcast-ы для эмуляторов (только debug-сборка; вызывает scripts/e2e/):
 *  - DEBUG_QR     --es qr <строка>                      подать QR-строку как скан
 *  - DEBUG_PEER   --es pk --es cs --es fac --es host --ei port   добавить пира без NSD
 *  - DEBUG_CONFIG --es clock <N> --es timer <N> --es autosolve true|false / port ? (напечатать порт приложения: "port=N")   см. DebugConfig
 *  - DEBUG_SET    --es create "Позывной:Фракция" / collector <url> / cs / fac / ram / balance / daemon "имя:1C,55:тир:ЭФФЕКТ" / pay "получатель:сумма:online|offline" [--ei burst N — N одновременных переводов] / contact "pk:позывной:фракция" / say "получатель|текст" / sayas "получатель|pk|позывной|фракция|текст" / give "daemon|shard:id:получатель[:offline]" / cancelitem <id> / cancel <txId> / cooldowns reset
 * Итог DEBUG_CONFIG / DEBUG_SET пишется в logcat с тегом MB10DBG; после смены
 * позывного/фракции/RAM экраны подхватят значения только после перезапуска приложения.
 */
class DebugQrReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            "com.megablok10.app.DEBUG_QR" -> intent.getStringExtra("qr")?.let { DebugQrBus.events.tryEmit(it) }
            "com.megablok10.app.DEBUG_PEER" -> {
                val pk = intent.getStringExtra("pk") ?: return
                PresenceService.addStaticPeer(
                    PeerInfo(pk, intent.getStringExtra("cs") ?: "", intent.getStringExtra("fac") ?: "", intent.getStringExtra("host") ?: return, intent.getIntExtra("port", 0))
                )
            }
            "com.megablok10.app.DEBUG_CONFIG" -> {
                intent.getStringExtra("clock")?.toDoubleOrNull()?.let { DebugConfig.clockSpeed = it.coerceAtLeast(0.01) }
                intent.getStringExtra("timer")?.toDoubleOrNull()?.let { DebugConfig.breachTimerFactor = it.coerceAtLeast(0.01) }
                intent.getStringExtra("autosolve")?.let { DebugConfig.autoSolve = it.toBoolean() }
                intent.getStringExtra("step")?.toLongOrNull()?.let { DebugConfig.autoSolveStepMs = it }
                if (intent.hasExtra("port")) Log.i(TAG, "port=${com.megablok10.app.chat.ChatStore.listeningPort}")
                Log.i(TAG, "config clock=${DebugConfig.clockSpeed} timer=${DebugConfig.breachTimerFactor} autosolve=${DebugConfig.autoSolve}")
            }
            "com.megablok10.app.DEBUG_SET" -> {
                val app = context.applicationContext
                val pending = goAsync()
                CoroutineScope(Dispatchers.IO).launch {
                    try { applySet(app, intent) } catch (e: Exception) { Log.e(TAG, "set failed", e) } finally { pending.finish() }
                }
            }
        }
    }

    private suspend fun applySet(context: Context, intent: Intent) {
        intent.getStringExtra("collector")?.let { CollectorSettings.setBaseUrl(context, it) }
        // Создание персонажа без экрана регистрации: "Позывной:Фракция" — как SetupScreen (см. MainActivity).
        intent.getStringExtra("create")?.let { spec ->
            val (callsign, faction) = spec.split(":", limit = 2).let { it[0] to it.getOrElse(1) { "" } }
            val isNew = !IdentityManager.hasIdentity(context)
            val created = IdentityManager.getOrCreate(context, callsign, faction)
            if (isNew) {
                ChangeRecordStore.enqueue(context, ChangeField.CALLSIGN, null, created.callsign, ChangeReason.CHARACTER_CREATED)
                ChangeRecordStore.enqueue(context, ChangeField.FACTION, null, created.faction, ChangeReason.CHARACTER_CREATED)
            }
        }
        intent.getStringExtra("cs")?.let { IdentityManager.applyCallsignOverride(context, it) }
        intent.getStringExtra("fac")?.let { IdentityManager.applyFactionOverride(context, it) }
        intent.getStringExtra("ram")?.toIntOrNull()?.let { IdentityManager.applyRamOverride(context, it) }
        intent.getStringExtra("balance")?.toLongOrNull()?.let {
            TransactionStore.applyBalanceOverride(context, "debug-${System.nanoTime()}", it, "debug")
        }
        intent.getStringExtra("daemon")?.let { spec ->
            // имя:1C,55:тир:ЭФФЕКТ
            val p = spec.split(":")
            if (p.size == 4) {
                val tier = Tier.values().first { it.level == p[2].toInt() }
                val loot = LootCodec.Loot.DaemonLoot(p[0], p[1].split(","), tier, DaemonEffect.valueOf(p[3]))
                DaemonStore.grant(context, "debug-${p[0]}", loot, "debug")
            }
        }
        // Перевод как из WalletScreen: "получатель:сумма:online|offline" (offline — как если бы получатель не в сети, карточка не уходит).
        // burst — сколько одинаковых переводов запустить ОДНОВРЕМЕННО (для проверки гонки «двойной тап»: баланс не должен уйти в минус).
        intent.getStringExtra("pay")?.let { spec ->
            val (to, amountStr, mode) = spec.split(":").let { Triple(it[0], it[1], it.getOrElse(2) { "online" }) }
            val me = IdentityManager.current(context) ?: return@let
            val amount = amountStr.toLong()
            suspend fun payOnce() {
                val id = "dbg-${System.nanoTime()}"
                val payload = Mb10QrCodec.transactionSignaturePayload(id, me.publicKeyB64, amount, "debug")
                val tx = Mb10Qr.Transaction(id, me.publicKeyB64, amount, "debug", IdentityManager.sign(context, payload))
                val peer = if (mode == "offline") null else PresenceService.peers.value.find { it.pubKeyB64 == to }
                if (TransactionStore.recordOutgoingPending(context, tx, to)) {
                    TransactionStore.deliverOutgoing(context, id, willSend = peer != null) {
                        ChatStore.sendDirect(context, me, to, peer, Mb10QrCodec.encodeTransaction(tx))
                    }
                    Log.i(TAG, "pay id=$id")
                } else Log.i(TAG, "pay rejected")
            }
            val burst = intent.getIntExtra("burst", 1)
            if (burst <= 1) payOnce()
            else kotlinx.coroutines.coroutineScope { List(burst) { async(Dispatchers.IO) { payOnce() } }.awaitAll() }
        }
        // Сообщение от этого устройства: "получатель|текст" (DM) или "faction|текст" (фракционный чат). Для демо-записей.
        intent.getStringExtra("say")?.let { spec ->
            val me = IdentityManager.current(context) ?: return@let
            val (to, text) = spec.split("|", limit = 2).let { it[0] to it.getOrElse(1) { "" } }
            if (to == "faction") ChatStore.sendFaction(context, me, text)
            else ChatStore.sendDirect(context, me, to, PresenceService.peers.value.find { it.pubKeyB64 == to }, text)
        }
        // Добавить контакт как после скана QR: "pubKeyB64:позывной:фракция" (ключ base64 без ':').
        intent.getStringExtra("contact")?.let { spec ->
            val p = spec.split(":")
            if (p.size == 3) ContactStore.add(context, Mb10Qr.Contact(p[0], p[1], p[2]))
        }
        // Сообщение от чужого имени (демо «неизвестный контакт»): "получатель|pk-отправителя|позывной|фракция|текст". Чат не проверяет отправителя.
        intent.getStringExtra("sayas")?.let { spec ->
            val p = spec.split("|", limit = 5)
            val peer = PresenceService.peers.value.find { it.pubKeyB64 == p[0] } ?: return@let
            ChatClient.send(peer.host, peer.port, ChatWireMessage(ChatMessageType.DM, p[1], p[2], p[3], p[0], System.currentTimeMillis(), p[4]))
        }
        // Передача предмета как из интерфейса: "daemon|shard:идентификатор:получатель[:offline]". Пишет "give id=<id>" в logcat.
        intent.getStringExtra("give")?.let { spec ->
            val p = spec.split(":", limit = 3)
            val me = IdentityManager.current(context) ?: return@let
            val rest = p[2].split(":")
            val to = rest[0]
            val offline = rest.getOrNull(1) == "offline"
            val card = when (p[0]) {
                "shard" -> ItemTransferStore.sendShard(context, me, p[1], to)
                else -> Mb10Database.get(context).daemonDao().get(p[1])?.let {
                    ItemTransferStore.sendDaemon(context, me, com.megablok10.app.breach.Daemon(it.id, it.name, it.sequence.split(","), Tier.fromLevel(it.tier), DaemonEffect.valueOf(it.effect)), to)
                }
            }
            if (card == null) Log.i(TAG, "give rejected") else {
                if (offline) ItemTransferStore.deliverOutgoing(context, card.id, willSend = false) { false }
                else ItemTransferStore.deliver(context, me, card, to)
                Log.i(TAG, "give id=${card.id}")
            }
        }
        intent.getStringExtra("cancelitem")?.let { Log.i(TAG, "cancelitem $it -> ${ItemTransferStore.cancelOutgoing(context, it)}") }
        intent.getStringExtra("cancel")?.let { Log.i(TAG, "cancel ${it} -> ${TransactionStore.cancelOutgoing(context, it)}") }
        if (intent.getStringExtra("cooldowns") == "reset") Mb10Database.get(context).containerBreachDao().deleteAll()
        Log.i(TAG, "set applied: ${IdentityManager.current(context)}")
    }

    private companion object { const val TAG = "MB10DBG" }
}
