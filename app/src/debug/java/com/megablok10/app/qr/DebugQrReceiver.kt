package com.megablok10.app.qr

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.megablok10.app.DebugConfig
import com.megablok10.app.breach.DaemonEffect
import com.megablok10.app.breach.LootCodec
import com.megablok10.app.breach.Tier
import com.megablok10.app.chat.ChatMessageType
import com.megablok10.app.chat.ChatProtocol
import com.megablok10.app.chat.ChatWireMessage
import com.megablok10.app.di.AppGraph
import com.megablok10.app.di.appGraph
import com.megablok10.app.items.OutgoingItem
import com.megablok10.kit.mesh.PeerInfo
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

/**
 * Отладочные broadcast-ы для эмуляторов (только debug-сборка; вызывает scripts/e2e/):
 *  - DEBUG_QR     --es qr <строка>                      подать QR-строку как скан
 *  - DEBUG_PEER   --es pk --es cs --es fac --es host --ei port   добавить пира без NSD
 *  - DEBUG_CONFIG --es clock <N> --es timer <N> --es autosolve true|false / port ? (напечатать порт приложения: "port=N")   см. DebugConfig
 *  - DEBUG_SET    … / readreceipts on|off / readthread <pubKeyB64> (как открыть тред: отчёт о прочтении)
 *  - DEBUG_SET    --es create "Позывной:Фракция" / collector <url> / cs / fac / ram / balance / daemon "имя:1C,55:тир:ЭФФЕКТ" / pay "получатель:сумма:online|offline" [--ei burst N — N одновременных переводов] / contact "pk:позывной:фракция" / say "получатель|текст" / sayas "получатель|pk|позывной|фракция|текст" / give "daemon|shard:id:получатель[:offline]" / cancelitem <id> / cancel <txId> / cooldowns reset
 * Итог DEBUG_CONFIG / DEBUG_SET пишется в logcat с тегом MB10DBG (строки разбирает scripts/e2e/lib.sh — формат не менять).
 * Все действия идут через корень композиции (context.appGraph) — тем же путём, что и интерфейс.
 */
class DebugQrReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            "com.megablok10.app.DEBUG_QR" -> intent.getStringExtra("qr")?.let { DebugQrBus.events.tryEmit(it) }
            "com.megablok10.app.DEBUG_PEER" -> {
                val pk = intent.getStringExtra("pk") ?: return
                context.appGraph.presence.addStaticPeer(
                    PeerInfo(pk, intent.getStringExtra("cs") ?: "", intent.getStringExtra("fac") ?: "", intent.getStringExtra("host") ?: return, intent.getIntExtra("port", 0))
                )
            }
            "com.megablok10.app.DEBUG_CONFIG" -> {
                intent.getStringExtra("clock")?.toDoubleOrNull()?.let { DebugConfig.clockSpeed = it.coerceAtLeast(0.01) }
                intent.getStringExtra("timer")?.toDoubleOrNull()?.let { DebugConfig.breachTimerFactor = it.coerceAtLeast(0.01) }
                intent.getStringExtra("autosolve")?.let { DebugConfig.autoSolve = it.toBoolean() }
                intent.getStringExtra("step")?.toLongOrNull()?.let { DebugConfig.autoSolveStepMs = it }
                if (intent.hasExtra("port")) Log.i(TAG, "port=${context.appGraph.mesh.listeningPort}")
                Log.i(TAG, "config clock=${DebugConfig.clockSpeed} timer=${DebugConfig.breachTimerFactor} autosolve=${DebugConfig.autoSolve}")
            }
            "com.megablok10.app.DEBUG_SET" -> {
                val graph = context.appGraph
                val pending = goAsync()
                CoroutineScope(Dispatchers.IO).launch {
                    try { applySet(graph, intent) } catch (e: Exception) { Log.e(TAG, "set failed", e) } finally { pending.finish() }
                }
            }
        }
    }

    private suspend fun applySet(graph: AppGraph, intent: Intent) {
        fun peerOf(key: String) = graph.chat.onlinePeer(key)
        intent.getStringExtra("collector")?.let { graph.collectorSettings.setBaseUrl(it) }
        // Сброс сессии тем же путём, что кнопка в Настройках («Опасная зона», identity/SessionReset). Корень приложения видит сброс
        // сразу (личность реактивна), но стенд после сброса всё равно перезапускает приложение (restart_app).
        if (intent.getStringExtra("sessionreset") == "1") {
            graph.sessionReset.perform(graph.identity.current)
        }
        // Код игры (заголовок X-Game-Secret): пустая строка — сбросить.
        intent.getStringExtra("secret")?.let { graph.collectorSettings.setGameSecret(it.ifBlank { null }) }
        // Создание персонажа без экрана регистрации: "Позывной:Фракция" — тот же сценарий, что ручное создание в SetupScreen.
        intent.getStringExtra("create")?.let { spec ->
            val (callsign, faction) = spec.split(":", limit = 2).let { it[0] to it.getOrElse(1) { "" } }
            graph.createCharacter(callsign, faction)
        }
        intent.getStringExtra("cs")?.let { graph.identity.applyCallsignOverride(it) }
        intent.getStringExtra("fac")?.let { graph.identity.applyFactionOverride(it) }
        intent.getStringExtra("ram")?.toIntOrNull()?.let { graph.identity.applyRamOverride(it) }
        intent.getStringExtra("balance")?.toLongOrNull()?.let {
            graph.wallet.applyBalanceOverride("debug-${System.nanoTime()}", it, "debug")
        }
        intent.getStringExtra("daemon")?.let { spec ->
            // имя:1C,55:тир:ЭФФЕКТ
            val p = spec.split(":")
            if (p.size == 4) {
                val tier = Tier.values().first { it.level == p[2].toInt() }
                val loot = LootCodec.Loot.DaemonLoot(p[0], p[1].split(","), tier, DaemonEffect.valueOf(p[3]))
                graph.daemons.grant("debug-${p[0]}", loot, "debug")
            }
        }
        // Перевод как из WalletScreen: "получатель:сумма:online|offline" (offline — как если бы получатель не в сети, карточка не уходит).
        // burst — сколько одинаковых переводов запустить ОДНОВРЕМЕННО (для проверки гонки «двойной тап»: баланс не должен уйти в минус).
        intent.getStringExtra("pay")?.let { spec ->
            val (to, amountStr, mode) = spec.split(":").let { Triple(it[0], it[1], it.getOrElse(2) { "online" }) }
            val me = graph.identity.current ?: return@let
            val amount = amountStr.toLong()
            suspend fun payOnce() {
                val tx = graph.sendPayment(me, to, amount, "debug", id = "dbg-${System.nanoTime()}", offline = mode == "offline")
                if (tx != null) {
                    Log.i(TAG, "pay id=${tx.id}")
                    Log.i(TAG, "paycard=" + Mb10QrCodec.encodeTransaction(tx))   // для recv на устройстве получателя (scripts/e2e/seed.sh)
                } else Log.i(TAG, "pay rejected")
            }
            val burst = intent.getIntExtra("burst", 1)
            if (burst <= 1) payOnce()
            else kotlinx.coroutines.coroutineScope { List(burst) { async(Dispatchers.IO) { payOnce() } }.awaitAll() }
        }
        // Подложная карточка платежа: подписана ЭТИМ устройством, адресована ключу "toKey" (не тому, кто её примет). В лог — `card=<строка>`.
        intent.getStringExtra("forgecard")?.let { spec ->
            val (to, amountStr) = spec.split(":").let { it[0] to it[1] }
            val me = graph.identity.current ?: return@let
            val tx = graph.wallet.signedTransaction(me, to, amountStr.toLong(), "forged", id = "forged-${System.nanoTime()}")
            Log.i(TAG, "card=" + Mb10QrCodec.encodeTransaction(tx))
        }
        // Принять карточку платежа, как по нажатию «Принять» в чате: результат в лог — `recv -> true|false`.
        intent.getStringExtra("recv")?.let { raw ->
            val me = graph.identity.current ?: return@let
            val tx = Mb10QrCodec.decode(raw) as? Mb10Qr.Transaction
            // тот же сценарий, что «Принять» в чате: зачислить и ответить чеком, иначе платёж отправителя останется «доставлен»
            val credited = tx != null && graph.acceptPayment(me, tx)
            Log.i(TAG, "recv -> $credited")
        }
        // Сообщение от этого устройства: "получатель|текст" (DM) или "faction|текст" (фракционный чат). Для демо-записей.
        intent.getStringExtra("say")?.let { spec ->
            val me = graph.identity.current ?: return@let
            val (to, text) = spec.split("|", limit = 2).let { it[0] to it.getOrElse(1) { "" } }
            if (to == "faction") graph.chat.sendFaction(me, text)
            else graph.chat.sendDirect(me, to, peerOf(to), text)
        }
        // Добавить контакт как после скана QR: "pubKeyB64:позывной:фракция" (ключ base64 без ':').
        intent.getStringExtra("contact")?.let { spec ->
            val p = spec.split(":")
            if (p.size == 3) graph.contacts.add(Mb10Qr.Contact(p[0], p[1], p[2]))
        }
        // Сообщение от чужого имени (демо «неизвестный контакт»): "получатель|pk-отправителя|позывной|фракция|текст". Чат не проверяет отправителя.
        intent.getStringExtra("sayas")?.let { spec ->
            val p = spec.split("|", limit = 5)
            if (peerOf(p[0]) == null) return@let
            graph.peerDirectory.send(p[0], ChatProtocol.encode(ChatWireMessage(ChatMessageType.DM, p[1], p[2], p[3], p[0], System.currentTimeMillis(), p[4])))
        }
        // Передача предмета как из интерфейса: "daemon|shard:идентификатор:получатель[:offline]". Пишет "give id=<id>" в logcat.
        intent.getStringExtra("give")?.let { spec ->
            val p = spec.split(":", limit = 3)
            val me = graph.identity.current ?: return@let
            val rest = p[2].split(":")
            val to = rest[0]
            val offline = rest.getOrNull(1) == "offline"
            val item = when (p[0]) {
                "shard" -> OutgoingItem.Shard(p[1])
                else -> graph.daemons.get(p[1])?.let { OutgoingItem.Daemon(it) }
            }
            val card = item?.let { graph.sendItem(me, it, to, offline) }
            if (card == null) Log.i(TAG, "give rejected") else Log.i(TAG, "give id=${card.id}")
        }
        intent.getStringExtra("cancelitem")?.let { Log.i(TAG, "cancelitem $it -> ${graph.items.cancelOutgoing(it)}") }
        intent.getStringExtra("cancel")?.let { Log.i(TAG, "cancel ${it} -> ${graph.wallet.cancelOutgoing(it)}") }
        if (intent.getStringExtra("cooldowns") == "reset") graph.cooldowns.resetAll()
        // «Отчёты о прочтении» on|off — переключатель из Настроек (D4).
        intent.getStringExtra("readreceipts")?.let { graph.readReceiptSetting.set(it == "on") }
        // Игрок открыл тред с «pubKeyB64» — то же, что DirectThreadViewModel: отчёт о прочтении. Пишет «readthread -> SENT|QUEUED|OFF|NOTHING_NEW».
        intent.getStringExtra("readthread")?.let { peer ->
            val me = graph.identity.current ?: return@let
            val messages = graph.chat.observeDirect(me.publicKeyB64, peer).first()
            Log.i(TAG, "readthread -> ${graph.readReceipts.onThreadShown(me.publicKeyB64, peer, messages)}")
        }
        Log.i(TAG, "set applied: ${graph.identity.current}")
    }

    private companion object { const val TAG = "MB10DBG" }
}
