package com.megablok10.app.net

/**
 * Версии построчных протоколов (чат, звонки, заявки на слот). Первая строка каждого сообщения — `МАГИЯ:vN:…`. Раньше номер версии
 * писался, но никогда не проверялся: телефон со старым или новым приложением молча отбрасывал непонятные строки, и игрок
 * не понимал, почему «не приходят сообщения». Теперь декодер принимает ТОЛЬКО свою версию, а несовпадение при известной магии
 * сообщается игроку ([IncompatibleVersionReporter]).
 *
 * Меняете формат сообщения — поднимайте версию в соответствующем протоколе и в [SUPPORTED].
 */
object WireVersion {
    const val CHAT = 1
    const val CALL = 2
    const val CLAIM = 1

    /** Магия протокола → версия, которую понимает это приложение. */
    val SUPPORTED: Map<String, Int> = mapOf("MB10CHAT" to CHAT, "MB10CALL" to CALL, "MB10CLAIM" to CLAIM)

    /** «v2» → 2; всё остальное (нет буквы v, не число) → null. */
    fun parse(token: String): Int? =
        if (token.length >= 2 && token[0] == 'v') token.substring(1).toIntOrNull() else null

    /** Версия строки `МАГИЯ:vN:…` для магии [magic]; null — строка другого протокола, версия не читается или не совпадает со [SUPPORTED]. */
    fun matches(parts: List<String>, magic: String): Boolean =
        parts.size >= 2 && parts[0] == magic && parse(parts[1]) == SUPPORTED[magic]

    /** Если строка принадлежит известному протоколу, но другой версии — (магия, версия); иначе null. */
    fun mismatch(line: String): Pair<String, Int?>? {
        val parts = line.split(":", limit = 3)
        val magic = parts.getOrNull(0) ?: return null
        val supported = SUPPORTED[magic] ?: return null
        val version = parts.getOrNull(1)?.let(::parse)
        return if (version == supported) null else magic to version
    }
}

/**
 * Сообщает игроку, что рядом есть телефон с другой версией приложения — но не чаще раза в [COOLDOWN_MS] на пару (магия, версия),
 * чтобы поток сообщений от одного такого телефона не заваливал экран.
 */
class IncompatibleVersionReporter(private val now: () -> Long = System::currentTimeMillis, private val notify: (String) -> Unit) {
    private val lastShown = HashMap<Pair<String, Int?>, Long>()

    @Synchronized
    fun report(line: String) {
        val key = WireVersion.mismatch(line) ?: return
        val t = now()
        val last = lastShown[key]
        if (last != null && t - last < COOLDOWN_MS) return
        lastShown[key] = t
        notify("Игрок с другой версией приложения — сообщения не читаются. Обновите приложение до одной версии у всех.")
    }

    companion object { const val COOLDOWN_MS = 60_000L }
}
