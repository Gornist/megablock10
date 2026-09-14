package com.megablok10.app.breach

/**
 * Заглушка для автономной проверки движка кибердеки, пока Container ещё не
 * подключён (этап 4 — контейнеры и лут). Реальные gridSize/timerSec/демоны
 * будут приходить из отсканированного Container.breachParams, а RAM — из
 * Character.ramCapacity; числа ниже подобраны только чтобы 4 демона суммарно
 * ПРЕВЫШАЛИ ёмкость буфера (2+3+3+2=10 > 8) — это даёт реально проверить на
 * экране выбора демонов сценарий "придётся снять один", а не только happy path.
 */
object MockBreach {
    const val gridSize = 5
    const val timerSec = 45
    const val ramCapacity = 8

    val daemons = listOf(
        Daemon("datamine_v1", "Datamine V1", listOf("1C", "55"), "открывает текстовый шард"),
        Daemon("datamine_v2", "Datamine V2", listOf("BD", "E9", "1C"), "открывает второй шард на точке"),
        Daemon("icepick", "Icepick", listOf("55", "7A", "BD"), "снимает физическую блокировку двери"),
        Daemon("camera_shutdown", "Camera Shutdown", listOf("E9", "FF"), "скрывает попытку взлома от лога СБ")
    )
}
