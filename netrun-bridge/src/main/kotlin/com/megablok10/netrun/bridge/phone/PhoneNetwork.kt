package com.megablok10.netrun.bridge.phone

import com.megablok10.kit.log.KitLog
import com.megablok10.kit.log.NoopLog
import com.megablok10.kit.mesh.PeerDirectory
import com.megablok10.kit.mesh.PeerInfo
import com.megablok10.kit.mesh.PeerTable
import com.megablok10.kit.net.LineRoute
import com.megablok10.kit.net.LineServer
import com.megablok10.kit.net.LineSocketClient
import com.megablok10.kit.net.SendOutcome
import kotlinx.coroutines.CoroutineScope

/**
 * Куда Мост отправляет строки телефонам: порт транспорта, чтобы выдачу и приём можно было проверять без сети.
 * [send] блокирует поток (сокет) и возвращает исход как kit: [SendOutcome.UNKNOWN] — «могло дойти», его не повторяют по другому адресу.
 */
interface PhoneSender {
    /** Игрока сейчас видно (есть хотя бы один адрес). */
    fun isOnline(pubKeyB64: String): Boolean

    /** Строка (уже в виде тела личного сообщения) игроку; адреса перебирает транспорт, к следующему — только после NOT_REACHED. */
    fun send(pubKeyB64: String, line: String): SendOutcome
}

/**
 * Настоящий транспорт Моста — тот же, что у телефонов: сервер строк ([LineServer], конверт с проверкой «мне ли» и квитанцией
 * `MB10ACK`), таблица пиров ([PeerTable]) и перебор адресов ([PeerDirectory]) из kit. Адрес телефона Мост узнаёт из его
 * собственных строк (конверт несёт порт сервера отправителя — `onHeard`) либо из статической записи ([addStatic], стенд e2e).
 * Сервер открывается в [start] до чего-либо ещё, чтобы адрес Моста был стабильным ([linePort], 0 — любой свободный).
 */
class PhoneNetwork(
    private val key: WorldKey,
    private val scope: CoroutineScope,
    routes: () -> List<LineRoute<*>>,
    private val linePort: Int = 0,
    private val log: KitLog = NoopLog,
) : PhoneSender, AutoCloseable {
    private val peers = PeerTable(log) { scope }
    private val client = LineSocketClient(log, onOutcome = { host, port, outcome, by -> peers.reportSend(host, port, outcome, by) })
    // Лениво: маршруты ([PhoneInbox.routes]) зависят от самого транспорта (чеки и ответы уходят через него же).
    private val server by lazy {
        LineServer(
        routes = routes(),
        log = log,
        tag = "PhoneServer",
        preferredPort = linePort,
        identityKey = { key.publicB64 },
        onHeard = { from, host, port -> peers.heard(from, host, port) },
        )
    }
    private val directory = PeerDirectory(
        addresses = { peers.peers.value },
        online = peers.players,
        me = { key.publicB64 to server.port },
        sendLine = { host, port, line, from -> client.sendLineOutcome(host, port, line, expectAckFrom = from) },
    )

    /** Порт, на котором Мост слушает телефоны; -1 — не запущен. */
    val port: Int get() = server.port

    fun start() = server.start(scope)

    /** Известный заранее адрес телефона (QR стойки, стенд e2e). */
    fun addStatic(pubKeyB64: String, host: String, port: Int) = peers.addStatic(PeerInfo(pubKeyB64, "", "", host, port))

    override fun isOnline(pubKeyB64: String): Boolean = directory.isOnline(pubKeyB64)

    override fun send(pubKeyB64: String, line: String): SendOutcome = directory.send(pubKeyB64, line)

    override fun close() = server.stop()
}
