package com.megablok10.app.data

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Именованный счётчик, последнее выданное значение — сейчас только seq записей для мастера ([CHANGE_SEQ]). Хранится в той же базе,
 * что и очередь записей: номер выдаётся в одной транзакции с сохранением записи (см. kit ChangeQueue.nextSeq), поэтому не
 * повторяется после перезапуска и не теряется при откате. Раньше счётчик жил в SharedPreferences с асинхронной записью (`apply()`):
 * процесс, упавший до сброса на диск, после перезапуска выдавал тот же seq второй раз, и сервер отбраковывал запись навсегда.
 */
@Entity(tableName = "sequences")
data class SequenceEntity(
    @PrimaryKey val name: String,
    val value: Long,
)

/** Счётчик seq записей для мастерского коллектора. */
const val CHANGE_SEQ = "change_seq"
