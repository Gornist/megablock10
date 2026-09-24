package com.megablok10.app.net

import com.megablok10.app.log.Mb10Log
import com.megablok10.kit.net.LineSocketClient

/**
 * Отправка строк по сети (kit [LineSocketClient]) с журналом приложения — один экземпляр на процесс для ChatClient, CallClient,
 * ClaimClient и очереди исходящих. События в журнале — под тегом `Socket`, как и раньше.
 */
object LineTransport {
    val client = LineSocketClient(Mb10Log)
}
