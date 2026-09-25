package com.megablok10.kit.mesh

import com.megablok10.kit.net.SendOutcome

/**
 * Все известные адреса игрока [pubKeyB64] в порядке списка пиров — [PeerTable] держит их по источникам (NSD, статические,
 * подсказки сервера) и ставит лучший первым, а отказавший — в конец (после перезапуска приложения у игрока одна из записей
 * может ещё хранить порт прошлого процесса). [preferred] — адрес, который вызывающий взял раньше (экран, очередь): его место
 * решает таблица, а если его в списке уже нет — последним. Одинаковые host:port — один раз.
 */
fun List<PeerInfo>.addressesOf(pubKeyB64: String, preferred: PeerInfo? = null): List<PeerInfo> =
    (filter { it.pubKeyB64 == pubKeyB64 } + listOfNotNull(preferred)).distinctBy { it.host to it.port }

/**
 * Отправка по адресам по очереди. К следующему адресу — только после [SendOutcome.NOT_REACHED]: строка точно не ушла.
 * [SendOutcome.UNKNOWN] — стоп: получатель мог её уже получить, повтор по другому адресу для денег и предметов недопустим
 * (см. handover). Адресов нет — NOT_REACHED.
 */
inline fun sendToFirstReachable(addresses: List<PeerInfo>, send: (PeerInfo) -> SendOutcome): SendOutcome {
    var outcome = SendOutcome.NOT_REACHED
    for (address in addresses) {
        outcome = send(address)
        if (outcome != SendOutcome.NOT_REACHED) return outcome
    }
    return outcome
}

/**
 * Один адрес на игрока — лучший ([PeerTable] ставит его первым среди адресов игрока): для «кто сейчас виден» и числа игроков в
 * сети. Не `associateBy`: тот оставляет последний адрес игрока, то есть худший.
 */
fun List<PeerInfo>.bestPerPlayer(): Map<String, PeerInfo> {
    val out = LinkedHashMap<String, PeerInfo>()
    forEach { out.putIfAbsent(it.pubKeyB64, it) }
    return out
}
