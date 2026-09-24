package com.megablok10.app.wallet

/**
 * Правило списания при отправке денег (см. TransactionStore.recordOutgoingPending) —
 * вынесено в чистую функцию без Context/DAO/Room, чтобы саму проверку можно
 * было накрыть юнит-тестом на JVM. Сумма должна быть положительной и не
 * превышать текущий баланс на момент вызова; сам вызов делается внутри
 * db.withTransaction вместе с currentBalance() и insertIfAbsent, чтобы два
 * быстрых перевода подряд не увидели один и тот же баланс дважды — эту
 * атомарность чистая функция не проверяет и не может, для неё нужна
 * настоящая транзакция Room.
 */
fun canDebit(amount: Long, currentBalance: Long): Boolean = amount in 1..currentBalance
