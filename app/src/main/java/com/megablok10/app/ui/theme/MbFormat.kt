package com.megablok10.app.ui.theme

import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/** Только группировка разрядов тысяч узким неразрывным пробелом, без знака и без «€$» — для MbTile (число и юнит разными стилями). */
fun groupThousands(amount: Long): String = kotlin.math.abs(amount).toString().reversed().chunked(3).joinToString(" ").reversed()

/** Деньги в формате гайдлайна (раздел 7): `1 240 €$`, узкий неразрывный пробел между разрядами тысяч, минус — знаком «−». */
fun formatMoney(amount: Long): String = (if (amount < 0) "−" else "") + groupThousands(amount) + " €$"

/** Заголовок дня в ленте чата и журнале кошелька: «Сегодня», «Вчера» или `3 октября` (русская локаль независимо от настроек телефона). */
fun dayLabel(day: Calendar, today: Calendar): String {
    val sameYear = today.get(Calendar.YEAR) == day.get(Calendar.YEAR)
    val diff = today.get(Calendar.DAY_OF_YEAR) - day.get(Calendar.DAY_OF_YEAR)
    return when {
        sameYear && diff == 0 -> "Сегодня"
        sameYear && diff == 1 -> "Вчера"
        else -> SimpleDateFormat("d MMMM", Locale("ru")).format(day.time)
    }
}

/** «7F3A…C21» — первые 4 и последние 3 символа ключа, как в прототипе; ключ не длиннее [fullUpTo] показывается целиком. */
fun shortKey(key: String, fullUpTo: Int): String = if (key.length <= fullUpTo) key else "${key.take(4)}…${key.takeLast(3)}"
