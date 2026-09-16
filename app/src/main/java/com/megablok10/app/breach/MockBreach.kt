package com.megablok10.app.breach

/**
 * Общие параметры баланса взлома и стартовый набор демонов, который сеется
 * в кибердеку персонажа один раз при первом запуске (см. DaemonStore.
 * ensureSeeded) — дальше коллекция растёт через QR мастера, а не отсюда.
 * Числа для gridSize/timerSec/ramCapacity подобраны так, чтобы 4 стартовых
 * демона суммарно ПРЕВЫШАЛИ ёмкость буфера (2+3+3+2=10 > 8) — это даёт
 * реально проверить на экране выбора демонов сценарий "придётся снять один",
 * а не только happy path. У стартовых демонов reward — чистый текст без
 * цифрового эффекта (rewardMoney/rewardShard* не заданы) — реальная награда
 * есть только у демонов, которых выдаёт мастер (см. Daemon в BreachEngine.kt).
 */
object MockBreach {
    const val gridSize = 5
    const val timerSec = 45
    const val ramCapacity = 8

    /** Анти-фарм: одна и та же точка доступа не платит демонов-наградами чаще этого интервала (см. AccessPointCooldownStore). */
    const val accessPointCooldownMinutes = 60

    val daemons = listOf(
        Daemon("datamine_v1", "Datamine V1", listOf("1C", "55"), "открывает текстовый шард"),
        Daemon("datamine_v2", "Datamine V2", listOf("BD", "E9", "1C"), "открывает второй шард на точке"),
        Daemon("icepick", "Icepick", listOf("55", "7A", "BD"), "снимает физическую блокировку двери"),
        Daemon("camera_shutdown", "Camera Shutdown", listOf("E9", "FF"), "скрывает попытку взлома от лога СБ")
    )
}
