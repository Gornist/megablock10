package com.megablok10.kit.mesh

import com.megablok10.kit.net.SendOutcome
import kotlinx.coroutines.flow.StateFlow

/** Игрок, которого сейчас видно в сети, — без адреса: адреса знает только [PeerDirectory]. Для экранов, контактов, фракций. */
data class OnlinePlayer(val pubKeyB64: String, val callsign: String, val faction: String)

/**
 * Одно место адресации пиров (docs/refactor-plan.md, B1). Снаружи — только игроки ([online]) и «отправь игроку строку» ([send]);
 * какой из адресов игрока живой (NSD, статический, подсказка сервера, порт прошлого процесса), решают [PeerTable] и перебор
 * [sendToFirstReachable] здесь, а не каждый вызывающий сам. Исход каждой попытки таблица узнаёт от kit LineSocketClient.
 */
class PeerDirectory(
    private val addresses: () -> List<PeerInfo>,
    /** Видимые игроки, по одному на ключ, в порядке таблицы. */
    val online: StateFlow<List<OnlinePlayer>>,
    private val sendLine: (host: String, port: Int, line: String) -> SendOutcome,
) {
    fun player(pubKeyB64: String): OnlinePlayer? = online.value.find { it.pubKeyB64 == pubKeyB64 }

    fun isOnline(pubKeyB64: String): Boolean = addresses().any { it.pubKeyB64 == pubKeyB64 }

    /** Адреса игрока в порядке попыток одной строкой (`10.10.0.5:4000,10.10.0.5:4100`, нет — `-`) — только для журнала. */
    fun describe(pubKeyB64: String): String =
        addresses().addressesOf(pubKeyB64).joinToString(",") { "${it.host}:${it.port}" }.ifEmpty { "-" }

    /**
     * Строку — игроку [pubKeyB64]: по его адресам, пока не дойдёт; к следующему — только после [SendOutcome.NOT_REACHED].
     * [SendOutcome.UNKNOWN] — стоп (могло дойти: деньги и предметы по второму адресу не повторяем). Не видно — NOT_REACHED.
     * Блокирует поток (сокет) — звать с IO-диспетчера.
     */
    fun send(pubKeyB64: String, line: String): SendOutcome =
        sendToFirstReachable(addresses().addressesOf(pubKeyB64)) { sendLine(it.host, it.port, line) }

    /** Всем видимым игрокам — по разу каждому, не на каждый адрес. Возвращает исход по ключу. */
    fun sendToAll(line: String, filter: (OnlinePlayer) -> Boolean = { true }): Map<String, SendOutcome> =
        online.value.filter(filter).associate { it.pubKeyB64 to send(it.pubKeyB64, line) }
}
