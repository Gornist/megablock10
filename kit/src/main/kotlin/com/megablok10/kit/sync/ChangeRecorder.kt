package com.megablok10.kit.sync

import com.megablok10.kit.log.KitLog
import com.megablok10.kit.log.NoopLog
import com.megablok10.kit.time.Clock
import java.util.UUID

/** Локальная очередь записей, ещё не подтверждённых сервером — порт (у Мегаблока — таблица Room `pending_change_records`). */
interface ChangeQueue {
    /** Повторная запись с тем же id игнорируется. */
    suspend fun insert(record: ChangeRecord)

    /** Самые старые записи по seq. */
    suspend fun nextBatch(limit: Int): List<ChangeRecord>
    suspend fun deleteByIds(ids: List<String>)
    suspend fun count(): Int

    /** Время самой старой записи в очереди; null — очередь пуста. */
    suspend fun oldestHappenedAt(): Long?
}

/** Кто подписывает записи: ключ игрока, сквозной номер записи и подпись. null из провайдера — личности на устройстве ещё нет. */
interface RecordSigner {
    val publicKeyB64: String

    /** Следующий seq: растёт монотонно на устройстве, не зависит от очереди (очередь может опустеть, нумерация — нет). */
    fun nextSeq(): Long
    fun sign(data: ByteArray): String
}

/**
 * Точка входа «вот что изменилось, отправь мастерскому серверу, когда сможешь»: подписывает запись и кладёт её в локальную
 * очередь тем же вызовом, что меняет игровые данные, — вызывающий никогда не ждёт сеть. Отправляет [SyncEngine];
 * [onRecorded] будит его, чтобы запись ушла без ожидания следующего опроса.
 *
 * [sensitiveFields] — поля, значения которых не пишутся в журнал (например, тексты объявлений мастера).
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
        val seq = me.nextSeq()
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
        val signed = unsigned.copy(signature = me.sign(unsigned.signaturePayload()))
        queue.insert(signed)
        val hidden = field in sensitiveFields
        log.event(tag, "record.enqueued", "field" to field, "reason" to reason, "old" to oldValue.takeUnless { hidden }, "new" to newValue.takeUnless { hidden }, "seq" to seq, "ref" to sourceRef)
        onRecorded()
        return signed
    }
}
