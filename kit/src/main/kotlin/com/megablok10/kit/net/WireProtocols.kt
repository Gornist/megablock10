package com.megablok10.kit.net

import com.megablok10.kit.time.Clock

/**
 * Версии построчных протоколов: первая часть каждой строки — `МАГИЯ:vN:…`. Декодер протокола принимает ТОЛЬКО свою версию
 * ([matches]), а строка известного протокола, но другой версии ([mismatch]) — повод сказать игроку, что рядом телефон со старым
 * или новым приложением (иначе сообщения от него молча не доходят и никто не понимает почему, см. [IncompatibleVersionReporter]).
 *
 * [supported] — магия протокола → версия, которую понимает это приложение. Меняете формат строки — поднимайте версию здесь.
 */
class WireProtocols(val supported: Map<String, Int>) {
    /** Версия строки `МАГИЯ:vN:…` совпадает с той, что понимает приложение для этой магии. */
    fun matches(parts: List<String>, magic: String): Boolean =
        parts.size >= 2 && parts[0] == magic && parseVersion(parts[1]) == supported[magic]

    /** Если строка принадлежит известному протоколу, но другой версии — (магия, версия; null — версия не читается); иначе null. */
    fun mismatch(line: String): Pair<String, Int?>? {
        val parts = line.split(":", limit = 3)
        val magic = parts.getOrNull(0) ?: return null
        val expected = supported[magic] ?: return null
        val version = parts.getOrNull(1)?.let(::parseVersion)
        return if (version == expected) null else magic to version
    }

    companion object {
        /** «v2» → 2; всё остальное (нет буквы v, не число) → null. */
        fun parseVersion(token: String): Int? =
            if (token.length >= 2 && token[0] == 'v') token.substring(1).toIntOrNull() else null
    }
}

/**
 * Сообщает игроку ([notify] с текстом [message]), что рядом есть телефон с другой версией протокола, — но не чаще раза в
 * [COOLDOWN_MS] на пару (магия, версия), чтобы поток сообщений от одного такого телефона не заваливал экран. Строки чужих
 * протоколов (не из [WireProtocols.supported]) и совместимые строки молча игнорируются.
 */
class IncompatibleVersionReporter(
    private val protocols: WireProtocols,
    private val message: String,
    private val clock: Clock = Clock.System,
    private val notify: (String) -> Unit,
) {
    private val lastShown = HashMap<Pair<String, Int?>, Long>()

    @Synchronized
    fun report(line: String) {
        val key = protocols.mismatch(line) ?: return
        val t = clock.nowMs()
        val last = lastShown[key]
        if (last != null && t - last < COOLDOWN_MS) return
        lastShown[key] = t
        notify(message)
    }

    companion object { const val COOLDOWN_MS = 60_000L }
}
