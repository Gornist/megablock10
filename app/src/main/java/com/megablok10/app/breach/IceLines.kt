package com.megablok10.app.breach

import kotlin.random.Random

/** События взлома, на которые защита (ICE) отвечает репликой. */
enum class IceEvent { INTRO, TRAP, MATCH, HALF_TIME, LOW_TIME }

/**
 * Реплики защиты узла — чистый выбор фразы без Android, чтобы его можно было тестировать.
 * Пул зависит от тира: BASE — казённо-равнодушный, HARD — настороженный, NIGHTMARE — враждебный.
 * Фразу выбирает Random от seed попытки, поэтому в одном взломе она стабильна, а между взломами разная.
 */
object IceLines {
    private val pool: Map<Pair<Tier, IceEvent>, List<String>> = mapOf(
        (Tier.BASE to IceEvent.INTRO) to listOf("ICE: плановая проверка канала…", "ICE: неавторизованный запрос, уровень допуска не подтверждён."),
        (Tier.HARD to IceEvent.INTRO) to listOf("ICE: контур активен. Идентифицируем источник.", "ICE: фиксирую попытку доступа. Не отключайтесь."),
        (Tier.NIGHTMARE to IceEvent.INTRO) to listOf("ICE: тебя ждали.", "ICE: контур боевой. Отступи, пока можешь."),

        (Tier.BASE to IceEvent.TRAP) to listOf("ICE: блок сектора.", "ICE: ошибка последовательности."),
        (Tier.HARD to IceEvent.TRAP) to listOf("ICE: ловушка сработала. Шум в канале растёт.", "ICE: несанкционированный сектор. Трассировка усилена."),
        (Tier.NIGHTMARE to IceEvent.TRAP) to listOf("ICE: попался. Прожигаю канал.", "ICE: ещё шаг — и я вижу твой адрес."),

        (Tier.BASE to IceEvent.MATCH) to listOf("ICE: часть данных принята.", "ICE: доступ к сегменту открыт."),
        (Tier.HARD to IceEvent.MATCH) to listOf("ICE: обход сегмента. Продолжаю следить.", "ICE: брешь в контуре. Латаю."),
        (Tier.NIGHTMARE to IceEvent.MATCH) to listOf("ICE: ты слишком близко.", "ICE: как ты прошёл этот сектор?.."),

        (Tier.BASE to IceEvent.HALF_TIME) to listOf("ICE: сессия истекает через половину окна."),
        (Tier.HARD to IceEvent.HALF_TIME) to listOf("ICE: половина окна вышла. Замыкаю контур."),
        (Tier.NIGHTMARE to IceEvent.HALF_TIME) to listOf("ICE: время идёт. Не в твою пользу."),

        (Tier.BASE to IceEvent.LOW_TIME) to listOf("ICE: закрытие сессии."),
        (Tier.HARD to IceEvent.LOW_TIME) to listOf("ICE: закрываю канал. Последние секунды."),
        (Tier.NIGHTMARE to IceEvent.LOW_TIME) to listOf("ICE: отключаю. Навсегда."),
    )

    fun line(tier: Tier, event: IceEvent, random: Random): String =
        pool.getValue(tier to event).let { it[random.nextInt(it.size)] }

    /** Для теста полноты: для каждой пары тир×событие есть хотя бы одна фраза. */
    internal fun isComplete(): Boolean = Tier.values().all { t -> IceEvent.values().all { e -> pool[t to e].orEmpty().isNotEmpty() } }
}
