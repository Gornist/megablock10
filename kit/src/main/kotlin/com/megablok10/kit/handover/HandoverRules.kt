package com.megablok10.kit.handover

import com.megablok10.kit.net.SendOutcome

/**
 * Статусы исходящей карточки передачи (денег, предмета — чего угодно, что должно ПЕРЕЙТИ от одного игрока к другому, а не
 * скопироваться). Строки хранятся в базе приложения как есть — не переименовывать.
 */
object HandoverStatus {
    /** Записана локально, но карточка получателю НЕ доставлена (он офлайн / отправка не удалась) — отменить ещё можно. */
    const val PENDING = "PENDING"
    /** Карточка ушла получателю — он уже мог нажать «Принять», поэтому отмена запрещена (иначе ценность окажется у обоих). */
    const val DELIVERED = "DELIVERED"
    /** Отправитель получил чек получателя — передача состоялась. */
    const val CONFIRMED = "CONFIRMED"
}

/**
 * Правила протокола передачи — чистые функции, общие для всего, что передаётся по этому протоколу (в Мегаблоке — деньги и
 * предметы): одно место, чтобы разные виды передач не могли разойтись в правиле, исправленном только у одного из них.
 *
 * Протокол: отправитель списывает у себя ценность сразу (PENDING), доставляет подписанную карточку (DELIVERED — с этого
 * момента отмена запрещена), получатель проверяет подпись и адресата, зачисляет себе и отвечает подписанным чеком, по чеку
 * отправитель фиксирует передачу (CONFIRMED). Отменить можно только недоставленную карточку — ценность возвращается.
 */
object HandoverRules {
    /** Отправлять карточку сейчас (и ставить DELIVERED до отправки) или просто оставить запись PENDING без сети (получатель офлайн). */
    fun shouldMarkDeliveredBeforeSend(willSend: Boolean): Boolean = willSend

    /**
     * Откатывать DELIVERED обратно в PENDING можно только когда соединиться с получателем не удалось вовсе
     * ([SendOutcome.NOT_REACHED]) — карточка точно не ушла. При [SendOutcome.UNKNOWN] она могла дойти, поэтому передача
     * остаётся замороженной DELIVERED до чека — лучше так, чем ценность окажется сразу у обеих сторон.
     */
    fun shouldRevertToPendingAfterSend(outcome: SendOutcome): Boolean = outcome == SendOutcome.NOT_REACHED

    /**
     * Можно ли разбирать входящую карточку: чужую копию карточки принять нельзя (иначе сообщник или перехват в сети
     * создали бы ценность из воздуха), свою же — тоже нет. Причина отказа для журнала или null (подпись и повтор ещё не
     * проверены — см. [rejectIncoming]).
     */
    fun incomingCardRejection(fromPubKeyB64: String, toPubKeyB64: String, myPublicKeyB64: String): String? = when {
        fromPubKeyB64 == myPublicKeyB64 -> "своя же карточка"
        toPubKeyB64 != myPublicKeyB64 -> "адресована не мне"
        else -> null
    }

    /**
     * Полная проверка входящей карточки перед зачислением: адресация ([incomingCardRejection]) и подпись отправителя над
     * [signedPayload]. Причина отказа для журнала или null — карточку можно принимать (повтор отсекает журнал получателя).
     */
    fun rejectIncoming(
        fromPubKeyB64: String,
        toPubKeyB64: String,
        myPublicKeyB64: String,
        signedPayload: ByteArray,
        signatureB64: String,
        verify: (publicKeyB64: String, data: ByteArray, signatureB64: String) -> Boolean,
    ): String? = incomingCardRejection(fromPubKeyB64, toPubKeyB64, myPublicKeyB64)
        ?: if (verify(fromPubKeyB64, signedPayload, signatureB64)) null else "подпись не сошлась"

    /** Байты, которые подписывает получатель на чеке: id передачи и его ключ (формат `id|ключ`, общий с сервером и старыми версиями). */
    fun receiptSignaturePayload(id: String, receiverPubKeyB64: String): ByteArray =
        "$id|$receiverPubKeyB64".toByteArray(Charsets.UTF_8)
}
