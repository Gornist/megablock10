package com.megablok10.app.data

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Демон, известный этому персонажу. Стартовый набор сеется из MockBreach при
 * первом запуске (см. DaemonStore.ensureSeeded) — дальше список пополняется
 * по мере игры: демон — предмет, который выдаёт мастер через свой QR
 * (Мастерская → форма "Демон"), сканируется в кибердеку игрока тем же путём,
 * что и шард. sequence хранится как коды через запятую — своей таблицы под
 * них не нужно. rewardMoney/rewardShard* — см. Daemon в BreachEngine.kt.
 */
@Entity(tableName = "daemons")
data class DaemonEntity(
    @PrimaryKey val id: String,
    val name: String,
    val sequence: String,
    val reward: String,
    val rewardMoney: Long = 0,
    val rewardShardTitle: String? = null,
    val rewardShardMeta: String? = null,
    val rewardShardBody: String? = null
)
