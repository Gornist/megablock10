package com.megablok10.app.breach

/**
 * Три уровня сложности — общие для контейнера, демона и лут-слота. Один enum,
 * а не отдельные Int/String на каждой сущности: "демон тира HARD извлекает
 * слот тира HARD и ниже" сравнивается напрямую через compareTo по level, без
 * ручной синхронизации трёх разных представлений одного и того же понятия.
 */
enum class Tier(val level: Int, val label: String) {
    BASE(1, "База"),
    HARD(2, "Сложно"),
    NIGHTMARE(3, "Кошмар");

    /** Тир a "покрывает" тир b, если a не ниже b — демон высокого тира извлекает и более простые слоты. */
    fun covers(other: Tier): Boolean = level >= other.level

    companion object {
        fun fromLevel(level: Int): Tier = entries.firstOrNull { it.level == level } ?: BASE
    }
}
