package com.megablok10.kit.mesh

import com.megablok10.kit.net.SendOutcome

/**
 * Все известные адреса игрока [pubKeyB64]: сначала [preferred] (тот, что выбрал вызывающий), затем остальные записи того же
 * ключа в списке пиров — [PeerTable] держит их по источникам (NSD, статические, подсказки сервера), и после перезапуска
 * приложения у игрока одна из записей может ещё хранить порт прошлого процесса. Одинаковые host:port — один раз.
 */
fun List<PeerInfo>.addressesOf(pubKeyB64: String, preferred: PeerInfo? = null): List<PeerInfo> =
    (listOfNotNull(preferred) + filter { it.pubKeyB64 == pubKeyB64 }).distinctBy { it.host to it.port }

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
