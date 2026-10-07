package com.megablok10.app.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

/** Таблица сообщений: личные и фракционные, статусы, голосовые (маркер `MB10VM:`). Запросы — по одному на сценарий, поэтому функций больше порога detekt. */
@Suppress("TooManyFunctions")
@Dao
interface ChatMessageDao {
    /** Своё сообщение с карточкой перевода или предмета [transferId] адресату [to] — ровно как оно ушло (см. chat.CardResender). */
    @Query("SELECT * FROM chat_messages WHERE type = 'DM' AND fromPubKeyB64 = :me AND toPubKeyB64 = :to AND body LIKE '%:' || :transferId || ':%' ORDER BY timestamp ASC LIMIT 1")
    suspend fun outgoingCard(me: String, to: String, transferId: String): ChatMessageEntity?

    @Insert
    suspend fun insert(message: ChatMessageEntity): Long

    @Query("SELECT COUNT(*) FROM chat_messages WHERE fromPubKeyB64 = :from AND timestamp = :timestamp AND type = :type AND body = :body")
    suspend fun countSame(from: String, timestamp: Long, type: String, body: String): Int

    /** Статус своего сообщения — только вверх (см. MessageStatus). */
    @Query("UPDATE chat_messages SET status = :status WHERE id = :id AND status < :status")
    suspend fun raiseStatus(id: Long, status: Int)

    /** То же по содержимому — для очереди исходящих и переотправки, где известна строка, а не id. */
    @Query("UPDATE chat_messages SET status = :status WHERE fromPubKeyB64 = :from AND timestamp = :timestamp AND type = :type AND body = :body AND status < :status")
    suspend fun raiseStatusOf(from: String, timestamp: Long, type: String, body: String, status: Int)

    /** Следующее непрослушанное голосовое (маркер `MB10VM:`) от [peer] мне после [after] — для автопроигрывания. */
    @Query("SELECT * FROM chat_messages WHERE type = 'DM' AND fromPubKeyB64 = :peer AND toPubKeyB64 = :me AND body LIKE 'MB10VM:%' AND status < 5 AND timestamp > :after ORDER BY timestamp ASC LIMIT 1")
    suspend fun nextUnlistenedVoice(me: String, peer: String, after: Long): ChatMessageEntity?

    /**
     * Отчёт о прочтении (D4): все мои личные сообщения [reader], отправленные не позже [upTo], — прочитаны. Голосовые (маркер `MB10VM:`) не трогаем:
     * у них своя отметка — «прослушано» ([markVoiceListenedBy]), как в Telegram синие ✓✓ только после прослушивания.
     */
    @Query("UPDATE chat_messages SET status = 4 WHERE type = 'DM' AND fromPubKeyB64 = :me AND toPubKeyB64 = :reader AND timestamp <= :upTo AND status < 4 AND body NOT LIKE 'MB10VM:%'")
    suspend fun markReadUpTo(me: String, reader: String, upTo: Long): Int

    @Query("SELECT * FROM chat_messages WHERE id = :id")
    suspend fun byId(id: Long): ChatMessageEntity?

    /** Чужое голосовое [id] прослушано здесь (точка «не прослушано» гаснет); 1 — отметили впервые, 0 — уже было. */
    @Query("UPDATE chat_messages SET status = 5 WHERE id = :id AND status < 5")
    suspend fun markListened(id: Long): Int

    /** Отчёт «прослушал»: моё голосовое [clipId] у [listener] прослушано. Совпадает по id в маркере (`MB10VM:v1:<id>:…`). */
    @Query("UPDATE chat_messages SET status = 5 WHERE type = 'DM' AND fromPubKeyB64 = :me AND toPubKeyB64 = :listener AND body LIKE 'MB10VM:v1:' || :clipId || ':%' AND status < 5")
    suspend fun markVoiceListenedBy(me: String, listener: String, clipId: String): Int

    @Query("SELECT * FROM chat_messages WHERE type = 'FACTION' AND faction = :faction ORDER BY timestamp ASC")
    fun observeFaction(faction: String): Flow<List<ChatMessageEntity>>

    @Query(
        """
        SELECT * FROM chat_messages
        WHERE type = 'DM' AND (
            (fromPubKeyB64 = :myPubKey AND toPubKeyB64 = :peerPubKey) OR
            (fromPubKeyB64 = :peerPubKey AND toPubKeyB64 = :myPubKey)
        )
        ORDER BY timestamp ASC
        """
    )
    fun observeDirect(myPubKey: String, peerPubKey: String): Flow<List<ChatMessageEntity>>

    /**
     * Один — последний — ряд на каждого собеседника, для инбокса со списком
     * диалогов (как в обычных мессенджерах), не полная история. GROUP BY по
     * "второй стороне" (не важно, я отправитель или получатель), а бесхозные
     * (не агрегатные) колонки в SELECT рядом с MAX() — намеренно: это
     * задокументированное поведение SQLite (bare-column-takes-value-from-
     * max-row), а не случайность — иначе пришлось бы городить самосоединение.
     */
    @Query(
        """
        SELECT *, MAX(timestamp) FROM chat_messages
        WHERE type = 'DM' AND (fromPubKeyB64 = :myPubKey OR toPubKeyB64 = :myPubKey)
        GROUP BY CASE WHEN fromPubKeyB64 = :myPubKey THEN toPubKeyB64 ELSE fromPubKeyB64 END
        ORDER BY timestamp DESC
        """
    )
    fun observeRecentDirectThreads(myPubKey: String): Flow<List<ChatMessageEntity>>
}
