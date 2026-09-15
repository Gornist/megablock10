package com.megablok10.app.data

import androidx.room.Entity
import androidx.room.PrimaryKey

/** Кто начал звонок — я или собеседник. */
object CallDirection {
    const val OUTGOING = "OUTGOING"
    const val INCOMING = "INCOMING"
}

/** Чем звонок закончился — только это и статус в UI, ничего похожего на аудио сюда не попадает. */
object CallOutcome {
    const val COMPLETED = "COMPLETED"
    const val DECLINED = "DECLINED"
    const val CANCELLED = "CANCELLED"
    const val MISSED = "MISSED"
    const val UNREACHABLE = "UNREACHABLE"
}

/**
 * Только метаданные звонка (кто, когда, направление, чем закончился,
 * длительность) — само аудио нигде не буферизуется и не пишется на диск,
 * это принципиально другая категория данных.
 */
@Entity(tableName = "call_log")
data class CallLogEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val peerPubKeyB64: String,
    val peerCallsign: String,
    val direction: String,
    val outcome: String,
    val startedAt: Long,
    val endedAt: Long
)
