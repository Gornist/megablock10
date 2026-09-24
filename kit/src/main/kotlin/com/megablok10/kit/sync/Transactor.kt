package com.megablok10.kit.sync

import java.util.Collections
import kotlin.coroutines.AbstractCoroutineContextElement
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.coroutineContext
import kotlinx.coroutines.withContext

/**
 * Граница транзакции хранилища — порт. Изменение игровых данных и запись о нём для мастера ([ChangeRecorder]) должны попасть на
 * диск вместе или не попасть вовсе: иначе падение процесса между ними оставляет «деньги есть, а записи нет» (или наоборот).
 * Вызывающий открывает транзакцию, внутри меняет данные и зовёт [ChangeRecorder.record] — запись присоединяется к той же
 * транзакции. Вложенный [inTransaction] не открывает новую, а продолжает внешнюю.
 */
interface Transactor {
    suspend fun <R> inTransaction(block: suspend () -> R): R

    /**
     * [action] — после фиксации самой внешней транзакции (при откате не выполняется); вне транзакции — сразу. Для побочных
     * эффектов, которым нужна уже видимая другим запись: разбудить синхронизацию, пока транзакция не зафиксирована, бесполезно —
     * она не увидит новую строку и уснёт до следующего опроса.
     */
    suspend fun afterCommit(action: () -> Unit)

    companion object {
        /** Без транзакций (хранилище в памяти, тесты): блок выполняется как есть, afterCommit — после него. */
        val Direct: Transactor = NestingTransactor { block -> block() }
    }
}

/**
 * [Transactor] поверх транзакции конкретного хранилища ([runInTransaction], у приложения — `RoomDatabase.withTransaction`):
 * вложенные вызовы присоединяются к внешнему, действия [afterCommit] копятся и выполняются после его фиксации.
 */
class NestingTransactor(private val runInTransaction: suspend (block: suspend () -> Unit) -> Unit) : Transactor {
    private class Frame : AbstractCoroutineContextElement(Key) {
        val actions: MutableList<() -> Unit> = Collections.synchronizedList(mutableListOf())
        companion object Key : CoroutineContext.Key<Frame>
    }

    override suspend fun <R> inTransaction(block: suspend () -> R): R {
        if (coroutineContext[Frame] != null) return block()
        val frame = Frame()
        var result: Any? = null
        runInTransaction { result = withContext(frame) { block() } }
        frame.actions.toList().forEach { it() }
        @Suppress("UNCHECKED_CAST")
        return result as R
    }

    override suspend fun afterCommit(action: () -> Unit) {
        coroutineContext[Frame]?.actions?.add(action) ?: action()
    }
}
