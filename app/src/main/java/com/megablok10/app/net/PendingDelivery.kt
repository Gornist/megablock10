package com.megablok10.app.net

/**
 * Общая для денег (wallet/TransactionStore) и предметов (items/ItemTransferStore)
 * логика вокруг статусов PENDING/DELIVERED при отправке карточки по сети —
 * вынесена сюда в чистые функции без Context/DAO/Room, чтобы инварианты,
 * описанные в комментариях обоих стораджей (откат только при NOT_REACHED,
 * запрет принять карточку не себе адресованную), можно было проверить
 * юнит-тестом на JVM, а не только e2e-сценарием на эмуляторах — а заодно
 * чтобы деньги и предметы не могли разойтись в этом правиле, случайно
 * исправленном только в одном из двух стораджей.
 */

/** Отправлять карточку сейчас (и ставить DELIVERED до отправки) или просто оставить запись PENDING без сети (получатель офлайн). */
fun shouldMarkDeliveredBeforeSend(willSend: Boolean): Boolean = willSend

/**
 * Откатывать DELIVERED обратно в PENDING можно только когда соединиться с
 * получателем не удалось вовсе ([SendOutcome.NOT_REACHED]) — карточка точно
 * не ушла. При [SendOutcome.UNKNOWN] она могла дойти, поэтому платёж/передача
 * остаётся замороженной DELIVERED до чека — лучше так, чем деньги или предмет
 * окажутся сразу у обеих сторон.
 */
fun shouldRevertToPendingAfterSend(outcome: SendOutcome): Boolean = outcome == SendOutcome.NOT_REACHED

/**
 * Разрешение принять входящую карточку (перевод денег или передачу предмета)
 * от другого игрока — одна и та же проверка адресации что для
 * TransactionStore.recordIncoming, что для ItemTransferStore.acceptIncoming:
 * чужую копию карточки принять нельзя (иначе сообщник или перехват в сети
 * создали бы деньги или предмет из воздуха), свою же карточку — тоже нет.
 * Возвращает причину отказа для лога или null, если карточку разбирать можно
 * (подпись и повтор ещё не проверены — это забота вызывающего).
 */
fun incomingCardRejection(fromPubKeyB64: String, toPubKeyB64: String, myPublicKeyB64: String): String? = when {
    fromPubKeyB64 == myPublicKeyB64 -> "своя же карточка"
    toPubKeyB64 != myPublicKeyB64 -> "адресована не мне"
    else -> null
}
