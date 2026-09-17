package com.megablok10.app.data

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Демон, известный этому персонажу. Стартовый набор (сейчас — один Datamine
 * V1) сеется из MockBreach при первом запуске (см. DaemonStore.ensureSeeded),
 * дальше пополняется извлечением из контейнеров (см. DaemonRewards, effect =
 * EXTRACT_DAEMON) — отдельных QR-демонов больше нет (ревизия v9). sequence
 * хранится как коды через запятую — своей таблицы под них не нужно.
 * tier/effect — что за демон и что он делает при совпадении, см. Daemon в
 * BreachEngine.kt и DaemonEffect.kt. Полей награды на демоне больше нет —
 * лут теперь на контейнере, демон — многоразовый инструмент, не билет.
 */
@Entity(tableName = "daemons")
data class DaemonEntity(
    @PrimaryKey val id: String,
    val name: String,
    val sequence: String,
    val tier: Int,
    val effect: String
)
