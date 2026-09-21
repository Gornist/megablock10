package com.megablok10.app.qr

/**
 * Проверка QR персонажа до применения (чистая функция, без Android — покрыта JVM-тестами). Возвращает текст ошибки для игрока или null, если код годится.
 * Границы намеренно жёсткие: код печатает мастер, но напечатать можно и ошибку, а на первом запуске исправить уже нечем.
 */
object ProvisionRules {
    const val MAX_TEXT = 40
    const val MAX_BALANCE = 1_000_000L

    fun validate(p: Mb10Qr.Provision): String? = when {
        p.id.isBlank() || p.id.length > 64 || !p.id.all { it.isLetterOrDigit() || it == '-' || it == '_' } -> "В коде нет номера выдачи — попросите мастера выдать заново"
        p.callsign.isBlank() -> "В коде нет позывного"
        p.callsign.length > MAX_TEXT || p.faction.length > MAX_TEXT -> "Слишком длинный позывной или фракция в коде"
        p.collectorUrl.isNotEmpty() && !(p.collectorUrl.startsWith("http://") || p.collectorUrl.startsWith("https://")) -> "Адрес сервера в коде записан неверно"
        p.gameSecret.length > 200 -> "Код игры в QR слишком длинный"
        p.startBalance !in 0..MAX_BALANCE -> "Стартовый баланс в коде вне допустимого"
        p.ramCapacity != 0 && p.ramCapacity !in 6..13 -> "Ёмкость буфера в коде вне допустимого"
        else -> null
    }
}
