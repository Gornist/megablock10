package com.megablok10.app.chat

import com.megablok10.app.breach.ClaimProtocol
import com.megablok10.app.call.CallProtocol
import com.megablok10.app.call.CallSignal
import com.megablok10.app.data.SlotClaimEntity
import com.megablok10.app.log.Mb10Log
import com.megablok10.kit.net.LineRoute
import com.megablok10.kit.net.LineServer
import kotlinx.coroutines.CoroutineScope

/**
 * Приём всех входящих строк Мегаблока на одном порту (порт выбирает ОС): сообщения чата (ChatProtocol), сигналы звонка
 * (CallProtocol) и заявки на слот лута (ClaimProtocol) различаются магическим префиксом первой строки. Механика приёма —
 * kit [LineServer]: одно соединение = одна строка, ограничение длины, таймаут молчащего клиента, сбой одного соединения не
 * роняет ни сервер, ни приложение. Строка известного протокола, но другой версии уходит в [onIncompatible].
 *
 * Журнал — под тегом `ChatServer` (server.listen, server.recv, server.incompatible_line…), как и раньше.
 */
/**
 * Постоянный порт сервера строк на всех телефонах (docs/refactor-plan.md, D1): адрес игрока — его IP, перезапуск приложения его не
 * меняет (раньше каждый процесс брал случайный порт, и NSD, подсказки сервера и статические пиры хранили порт прошлого процесса).
 */
const val CHAT_PORT = 47100

class ChatServer(
    onMessage: (ChatWireMessage) -> Unit,
    onCallSignal: (CallSignal) -> Unit = {},
    onSlotClaim: (SlotClaimEntity) -> Unit = {},
    /** Строка известного протокола, но другой версии (телефон со старым/новым приложением): сообщается игроку, см. WireVersion. */
    onIncompatible: (String) -> Unit = {}
) {
    private val server = LineServer(
        routes = listOf(
            LineRoute("chat", ChatProtocol::decode, onMessage),
            LineRoute("call", CallProtocol::decode, onCallSignal),
            LineRoute("claim", ClaimProtocol::decode, onSlotClaim),
        ),
        onUnrecognized = onIncompatible,
        log = Mb10Log,
        tag = "ChatServer",
        preferredPort = CHAT_PORT,
    )

    val port: Int get() = server.port

    fun start(scope: CoroutineScope) = server.start(scope)

    fun stop() = server.stop()
}
