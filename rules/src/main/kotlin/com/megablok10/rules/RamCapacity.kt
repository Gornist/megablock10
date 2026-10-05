package com.megablok10.rules

/**
 * RAM деки нетраннера: буфер взлома хранилища и предел ПРОГРАММ (сумма длин цепочек рабочих демонов). Нужна и телефону (`Identity`,
 * `NetrunEntry.validate`), и Мосту (`ram_exceeded` при входе, протокол Моста, раздел 8), поэтому живёт здесь, а не в `:app`.
 */
object RamCapacity {
    /** Стартовая ёмкость и нижняя граница. */
    const val DEFAULT = 6

    /** Максимум после всех апгрейдов. */
    const val MAX = 13

    /** [ram] допустима для запроса входа v2: от [DEFAULT] до [MAX]. */
    fun isValid(ram: Int): Boolean = ram in DEFAULT..MAX
}
