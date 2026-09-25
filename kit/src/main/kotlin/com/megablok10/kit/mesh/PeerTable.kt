package com.megablok10.kit.mesh

import com.megablok10.kit.log.KitLog
import com.megablok10.kit.log.NoopLog
import com.megablok10.kit.log.shortKey
import com.megablok10.kit.net.SendOutcome
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

private const val TAG = "PeerTable"
private const val STATIC = "static:"
private const val SRV = "srv:"

/** Известный баг платформы на части устройств: NSD может мигнуть onServiceLost сразу за onServiceFound для одного и того же пира без реального разрыва — отсюда дебаунс перед фактическим удалением. 12 с (а не 4): при роуминге между точками Wi-Fi бывают паузы до нескольких секунд, и короткий разрыв не должен выглядеть как «ушёл офлайн» (docs/network-spec.md, §7). */
const val LOST_DEBOUNCE_MS = 12_000L

/** После переподключения к сети старые записи NSD недействительны: пиры, не нашедшиеся заново за это время, убираются. */
const val REFRESH_GRACE_MS = 15_000L

/** Сколько последних адресов помнит одна запись NSD: после перезапуска игрока кэш mDNS может снова отдать порт прошлого процесса. */
const val NSD_ADDRESS_HISTORY = 3

/**
 * Таблица видимых пиров без единой Android-зависимости (поэтому проверяется JVM-тестами со временем корутин): источник
 * обнаружения (на Android — NSD/mDNS) сообщает found/lost, таблица сглаживает мигания и публикует список в [peers].
 *
 * Записи — по источникам: ключ — имя сервиса обнаружения (его, а не publicKey, возвращает onServiceLost); служебные префиксы:
 * `static:` — пиры, добавленные вручную (стенд на эмуляторах), `srv:` — пиры, подсказанные сервером. У одного игрока бывает
 * несколько адресов (разные источники, история адресов записи NSD), и ни один не выбрасывается из-за другого: имя сервиса NSD
 * у игрока одно во всех процессах, и после его перезапуска кэш mDNS отдаёт то новый порт, то порт прошлого процесса (e2e A4,
 * run 36179242929: подсказка сервера с верным портом выбрасывалась, потому что NSD «уже знал» игрока по старому).
 *
 * [peers] — все адреса, у каждого игрока лучший первым (на это опираются [addressesOf] и `find { ключ }`): сначала те, что
 * не отказывали после последней удачи, среди них — по последнему событию (адрес впервые пришёл из источника или по нему
 * дошла отправка, [reportSend]); отказавшие ([SendOutcome.NOT_REACHED]) — в конце, пока по ним снова не дойдёт. Время —
 * порядковый номер события, не часы. Повторное сообщение источника о том же адресе адрес не поднимает: иначе устаревший
 * ответ кэша mDNS каждый раз вставал бы первым. Отложенные удаления живут в скоупе из [scopeProvider]; нет скоупа
 * (обнаружение остановлено) — удаления не планируются.
 */
class PeerTable(private val log: KitLog = NoopLog, private val scopeProvider: () -> CoroutineScope?) {
    private class Candidate(val peer: PeerInfo, val source: String, val rank: Long, val down: Boolean)

    /** Снимок для [restore] после перезапуска обнаружения; внутреннее устройство снаружи не нужно. */
    class Snapshot internal constructor(internal val entries: Map<String, List<Seen>>, internal val health: Map<String, Health>)

    private val lock = Any()
    private var seq = 0L
    private val entries = HashMap<String, List<Seen>>()
    private val health = HashMap<String, Health>()
    private val pendingRemovals = HashMap<String, Job>()
    private var published: List<Candidate> = emptyList()
    private val _peers = MutableStateFlow<List<PeerInfo>>(emptyList())
    val peers: StateFlow<List<PeerInfo>> = _peers.asStateFlow()
    private val _players = MutableStateFlow<List<OnlinePlayer>>(emptyList())
    /** Видимые игроки без адресов, по одному на ключ (подпись и фракция — с лучшего адреса): для экранов через [PeerDirectory]. */
    val players: StateFlow<List<OnlinePlayer>> = _players.asStateFlow()

    private fun addrKey(p: PeerInfo) = "${p.pubKeyB64}@${p.host}:${p.port}"

    /** Кладёт адрес в запись источника: новый — с новой отметкой времени и первым; уже известный — с прежней. */
    private fun put(source: String, peer: PeerInfo, keep: Int): Boolean {
        val old = entries[source].orEmpty()
        val same = old.firstOrNull { it.peer.host == peer.host && it.peer.port == peer.port }
        val seen = Seen(peer, same?.at ?: ++seq)
        entries[source] = (listOf(seen) + old.filter { it !== same }).take(keep)
        return same == null
    }

    private fun publish() {
        val found = HashMap<String, Candidate>()
        fun add(peer: PeerInfo, source: String, at: Long) {
            val h = health[addrKey(peer)]
            val c = Candidate(peer, source, maxOf(at, h?.ok ?: 0), h?.down == true)
            val prev = found[addrKey(peer)]
            if (prev == null || c.rank > prev.rank) found[addrKey(peer)] = c
        }
        entries.forEach { (source, list) ->
            list.forEach { seen ->
                if (source.startsWith(SRV) && isLoopback(seen.peer.host)) {
                    // Сервер видит игрока за NAT (стенд на эмуляторах: 127.0.0.1) — такой host другому устройству бесполезен, а порт
                    // верный и свежий: берём его с host-ами, под которыми игрока видно напрямую. Не видно — подсказка ждёт.
                    lanHostsOf(seen.peer.pubKeyB64).forEach { host -> add(seen.peer.copy(host = host), source, seen.at) }
                } else {
                    add(seen.peer, source, seen.at)
                }
            }
        }
        published = found.values.sortedWith(
            compareBy<Candidate> { it.peer.pubKeyB64 }.thenBy { it.down }.thenByDescending { it.rank }
        )
        health.keys.retainAll(found.keys)
        _peers.value = published.map { it.peer }
        _players.value = _peers.value.bestPerPlayer().values.map { OnlinePlayer(it.pubKeyB64, it.callsign, it.faction) }
    }

    private fun lanHostsOf(pubKeyB64: String): List<String> =
        entries.filterKeys { !it.startsWith(SRV) }.values.flatten()
            .filter { it.peer.pubKeyB64 == pubKeyB64 && !isLoopback(it.peer.host) }
            .sortedByDescending { it.at }.map { it.peer.host }.distinct()

    fun addStatic(peer: PeerInfo): Unit = synchronized(lock) {
        put("$STATIC${peer.pubKeyB64}", peer, keep = 1)
        log.event(TAG, "peer.static", "peer" to shortKey(peer.pubKeyB64), "addr" to "${peer.host}:${peer.port}")
        publish()
    }

    /** Короткое описание для журнала в порядке [peers]: `ab12cd34(Ник@10.10.0.5:4000,nsd)`; `!` после источника — адрес отказал. */
    fun describe(): String = synchronized(lock) {
        published.joinToString(",", "[", "]") { c ->
            val src = when { c.source.startsWith(STATIC) -> "static"; c.source.startsWith(SRV) -> "srv"; else -> "nsd" }
            "${shortKey(c.peer.pubKeyB64)}(${c.peer.callsign}@${c.peer.host}:${c.peer.port},$src${if (c.down) "!" else ""})"
        }
    }

    /** Пир найден и разрешён: отменяет отложенное удаление, если оно было запланировано. */
    fun found(serviceName: String, peer: PeerInfo): Unit = synchronized(lock) {
        val cancelled = pendingRemovals.remove(serviceName)?.also { it.cancel() } != null
        val isNew = serviceName !in entries
        put(serviceName, peer, keep = NSD_ADDRESS_HISTORY)
        log.event(TAG, "peer.found", "service" to serviceName, "peer" to shortKey(peer.pubKeyB64), "callsign" to peer.callsign, "addr" to "${peer.host}:${peer.port}", "new" to isNew, "cancelledRemoval" to cancelled)
        publish()
    }

    /** Обнаружение сообщило о пропаже: удаляем не сразу, а через [LOST_DEBOUNCE_MS]. */
    fun lost(serviceName: String) {
        log.event(TAG, "peer.lost_reported", "service" to serviceName, "removeInMs" to LOST_DEBOUNCE_MS)
        synchronized(lock) { scheduleRemoval(serviceName, LOST_DEBOUNCE_MS) }
    }

    /** Перезапуск обнаружения после смены сети: найденные им пиры получают отсрочку [REFRESH_GRACE_MS], статические и серверные остаются как есть. */
    fun graceAll(): Unit = synchronized(lock) {
        entries.keys.filter { !it.startsWith(STATIC) && !it.startsWith(SRV) }.forEach { scheduleRemoval(it, REFRESH_GRACE_MS) }
    }

    private fun scheduleRemoval(name: String, afterMs: Long) {
        val scope = scopeProvider() ?: return
        pendingRemovals[name]?.cancel()
        pendingRemovals[name] = scope.launch {
            delay(afterMs)
            synchronized(lock) {
                val gone = entries.remove(name)
                pendingRemovals.remove(name)
                log.event(TAG, "peer.removed", "service" to name, "peer" to shortKey(gone?.firstOrNull()?.peer?.pubKeyB64), "afterMs" to afterMs)
                publish()
            }
        }
    }

    /**
     * Исход отправки по адресу [host]:[port] (kit LineSocketClient сообщает о каждой): дошло — адрес первым у своего игрока,
     * [SendOutcome.NOT_REACHED] — в конец, пока по нему снова не дойдёт. [SendOutcome.UNKNOWN] ничего не говорит о том, жив ли
     * адрес, — не меняет ничего. Адреса не из таблицы (сервер мастера и т. п.) пропускаются.
     */
    fun reportSend(host: String, port: Int, outcome: SendOutcome): Unit = synchronized(lock) {
        if (outcome == SendOutcome.UNKNOWN) return
        val hit = published.filter { it.peer.host == host && it.peer.port == port }
        if (hit.isEmpty()) return
        val at = ++seq
        hit.forEach { c ->
            val h = health.getOrPut(addrKey(c.peer)) { Health() }
            if (outcome == SendOutcome.DELIVERED) h.ok = at else h.fail = at
        }
        publish()
    }

    fun clear(): Unit = synchronized(lock) {
        pendingRemovals.values.forEach { it.cancel() }
        pendingRemovals.clear()
        entries.clear()
        publish()
    }

    /** Снимок для [restore] после перезапуска обнаружения (с тем, какие адреса отказывали). */
    fun snapshot(): Snapshot = synchronized(lock) {
        Snapshot(entries.toMap(), health.mapValues { (_, h) -> Health(h.ok, h.fail) })
    }

    fun restore(saved: Snapshot): Unit = synchronized(lock) {
        entries.putAll(saved.entries)
        saved.health.forEach { (k, h) -> health[k] = Health(h.ok, h.fail) }
        publish()
    }

    /**
     * Запасное обнаружение через сервер: подсказка — ещё один адрес игрока, а не замена найденным NSD (вперёд её ставит только
     * свежесть, см. [PeerTable]); исчезнувшие из списка сервера убираются.
     */
    fun updateServerPeers(fromServer: List<PeerInfo>, myPubKeyB64: String): Unit = synchronized(lock) {
        val wanted = fromServer.filter { it.pubKeyB64 != myPubKeyB64 && it.port > 0 && it.host.isNotBlank() }.associateBy { "$SRV${it.pubKeyB64}" }
        var changed = false
        wanted.forEach { (key, peer) ->
            if (entries[key]?.single()?.peer != peer) { put(key, peer, keep = 1); changed = true }
        }
        entries.keys.filter { it.startsWith(SRV) && it !in wanted }.forEach { entries.remove(it); changed = true }
        if (changed) {
            publish()
            log.event(TAG, "peer.server_hints", "fromServer" to fromServer.size, "peers" to describe())
        }
    }
}

/** Адрес из источника и отметка времени, когда источник сообщил его впервые. */
internal class Seen(val peer: PeerInfo, val at: Long)

/** Последняя удачная и последняя неудачная отправка по адресу (порядковые номера событий таблицы). */
internal class Health(var ok: Long = 0, var fail: Long = 0) { val down get() = fail > ok }

/** Адрес петли: так сервер видит устройство за NAT (эмулятор); другому устройству по нему не достучаться. */
internal fun isLoopback(host: String): Boolean = host.startsWith("127.") || host == "::1" || host.equals("localhost", ignoreCase = true)
