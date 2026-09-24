package com.megablok10.app.net

import com.megablok10.kit.net.WireProtocols

/**
 * Версии построчных протоколов Мегаблока (чат, звонки, заявки на слот). Первая строка каждого сообщения — `МАГИЯ:vN:…`. Раньше
 * номер версии писался, но никогда не проверялся: телефон со старым или новым приложением молча отбрасывал непонятные строки, и
 * игрок не понимал, почему «не приходят сообщения». Теперь декодер принимает ТОЛЬКО свою версию, а несовпадение при известной
 * магии сообщается игроку (kit IncompatibleVersionReporter с текстом [INCOMPATIBLE_MESSAGE]). Механика — kit [WireProtocols].
 *
 * Меняете формат сообщения — поднимайте версию в соответствующем протоколе и в [SUPPORTED].
 */
object WireVersion {
    const val CHAT = 1
    const val CALL = 2
    const val CLAIM = 1

    /** Версии для дашборда (поле `wireVersions` в presence): короткие имена протоколов, порядок стабилен. */
    val REPORTED: Map<String, Int> = linkedMapOf("chat" to CHAT, "call" to CALL, "claim" to CLAIM)

    /** Магия протокола → версия, которую понимает это приложение. */
    val SUPPORTED: Map<String, Int> = mapOf("MB10CHAT" to CHAT, "MB10CALL" to CALL, "MB10CLAIM" to CLAIM)

    val protocols = WireProtocols(SUPPORTED)

    const val INCOMPATIBLE_MESSAGE = "Игрок с другой версией приложения — сообщения не читаются. Обновите приложение до одной версии у всех."

    /** Строка `МАГИЯ:vN:…` этой магии и понимаемой приложением версии. */
    fun matches(parts: List<String>, magic: String): Boolean = protocols.matches(parts, magic)

    /** Если строка принадлежит известному протоколу, но другой версии — (магия, версия); иначе null. */
    fun mismatch(line: String): Pair<String, Int?>? = protocols.mismatch(line)
}
