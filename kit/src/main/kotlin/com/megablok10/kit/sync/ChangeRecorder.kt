package com.megablok10.kit.sync

import com.megablok10.kit.log.KitLog
import com.megablok10.kit.log.NoopLog
import com.megablok10.kit.time.Clock
import java.util.UUID

/**
 * Локальная очередь записей, ещё не подтверждённых сервером, и счётчик их номеров — порт (у Мегаблока — таблицы Room
 * `pending_change_records` и `sequences`). [nextSeq] и [insert] [ChangeRecorder] зовёт внутри одной транзакции, поэтому номер
 * должен храниться в том же хранилище, что и очередь: номер, выданный записи, которая не сохранилась, откатывается вместе с ней,
 * а номер сохранённой записи после перезапуска уже не выдаётся повторно (сервер отбраковал бы вторую запись с тем же seq).
 */
interface ChangeQueue {
    /** Следующий seq: растёт монотонно на устройстве и не зависит от очереди (очередь может опустеть, нумерация — нет). */
    suspend fun nextSeq(): Long

    /** Последний выданный seq (0 — ни одного): точка в хронологии телефона, где применилась правка мастера (SyncRequest.appliedAtSeq). */
    suspend fun lastSeq(): Long

    /** Повторная запись с тем же id игнорируется. */
    suspend fun insert(record: ChangeRecord)

    /** Самые старые записи по seq. */
    suspend fun nextBatch(limit: Int): List<ChangeRecord>
    suspend fun deleteByIds(ids: List<String>)

    /**
     * Сервер принял записи [ids]: из очереди их убрать, но какое-то время хранить (журнал подтверждённых) — если сервер
     * восстановят из резервной копии, они вернутся в очередь через [requeueAcceptedAbove]. По умолчанию — просто удалить.
     */
    suspend fun markAccepted(ids: List<String>) = deleteByIds(ids)

    /**
     * Вернуть в очередь подтверждённые записи [subjectKeyB64] с seq больше [seq] — сервер их потерял (у него последний — [seq]).
     * Возвращает, сколько вернулось. По умолчанию журнала нет — 0.
     */
    suspend fun requeueAcceptedAbove(subjectKeyB64: String, seq: Long): Int = 0
    suspend fun count(): Int

    /** Время самой старой записи в очереди; null — очередь пуста. */
    suspend fun oldestHappenedAt(): Long?
}

/** Кто подписывает записи: ключ игрока и подпись. null из провайдера — личности на устройстве ещё нет. */
interface RecordSigner {
    val publicKeyB64: String
    fun sign(data: ByteArray): String
}

/**
 * Точка входа «вот что изменилось, отправь мастерскому серверу, когда сможешь»: подписывает запись и кладёт её в локальную
 * очередь тем же вызовом, что меняет игровые данные, — вызывающий никогда не ждёт сеть. Отправляет [SyncEngine];
 * [onRecorded] будит его, чтобы запись ушла без ожидания следующего опроса.
 *
 * [sensitiveFields] — поля, значения которых не пишутся в журнал (например, тексты объявлений мастера).
 *
 * [transactor] — транзакция хранилища очереди: номер и запись сохраняются вместе, а вызов изнутри транзакции вызывающего (изменение
 * игровых данных) присоединяется к ней — данные и запись о них фиксируются одним коммитом. [onRecorded] — после этого коммита.
 */
class ChangeRecorder(
    private val queue: ChangeQueue,
    private val signer: () -> RecordSigner?,
    private val clock: Clock = Clock.System,
    private val log: KitLog = NoopLog,
    private val tag: String = "ChangeRecorder",
    private val sensitiveFields: Set<String> = emptySet(),
    private val newId: () -> String = { UUID.randomUUID().toString() },
    private val onRecorded: () -> Unit = {},
    private val transactor: Transactor = Transactor.Direct,
) {
    /**
     * [subjectKeyB64] — чья это запись (по умолчанию — самого игрока), [actor] — кто её вызвал (по умолчанию тоже он; для
     * входящего перевода, например, — ключ отправителя). null — личности на устройстве нет, запись не создана.
     */
    suspend fun record(
        field: String,
        oldValue: String?,
        newValue: String,
        reason: String,
        sourceRef: String? = null,
        subjectKeyB64: String? = null,
        actor: String? = null,
    ): ChangeRecord? {
        val me = signer() ?: run {
            log.w(tag, "нет личности устройства — запись $field/$reason потеряна")
            return null
        }
        val signed = transactor.inTransaction {
            val seq = queue.nextSeq()
            val unsigned = ChangeRecord(
                id = newId(),
                subjectKeyB64 = subjectKeyB64 ?: me.publicKeyB64,
                seq = seq,
                happenedAt = clock.nowMs(),
                field = field,
                oldValue = oldValue,
                newValue = newValue,
                reason = reason,
                sourceRef = sourceRef,
                actor = actor ?: me.publicKeyB64,
                signature = "",
            )
            unsigned.copy(signature = me.sign(unsigned.signaturePayload())).also { queue.insert(it) }
        }
        val hidden = field in sensitiveFields
        log.event(tag, "record.enqueued", "field" to field, "reason" to reason, "old" to oldValue.takeUnless { hidden }, "new" to newValue.takeUnless { hidden }, "seq" to signed.seq, "ref" to sourceRef)
        transactor.afterCommit(onRecorded)
        return signed
    }
}
