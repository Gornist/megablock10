package com.megablok10.app.data

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Демон, известный этому персонажу. Стартовый набор сеется из MockBreach при
 * первом запуске (см. DaemonStore.ensureSeeded) — дальше список пополняется
 * по мере игры (награды за взлом, находки), а не строится целиком заранее.
 * sequence хранится как коды через запятую — своей таблицы под них не нужно.
 */
@Entity(tableName = "daemons")
data class DaemonEntity(
    @PrimaryKey val id: String,
    val name: String,
    val sequence: String,
    val reward: String
)
