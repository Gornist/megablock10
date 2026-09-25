package com.megablok10.kit.net

/**
 * Конверт строки (docs/refactor-plan.md, D2): кому она — ключ получателя [to], от кого — ключ [from] и порт сервера строк
 * отправителя [fromPort]. Получатель ([LineServer]) проверяет «мне ли» до обработки и отвечает [LineAck]; по [from] и адресу
 * соединения он же узнаёт, где искать отправителя. Внутренняя строка [line] — любой протокол (чат, звонки, заявки) как есть.
 *
 * `MB10TO:v1:<to>:<from>:<fromPort>:<line>`. Ключи — base64 без `:`; [from] пуст, если у отправителя ещё нет личности.
 */
data class LineEnvelope(val to: String, val from: String, val fromPort: Int, val line: String) {
    fun encode(): String = "$MAGIC:v$VERSION:$to:$from:$fromPort:$line"

    companion object {
        const val MAGIC = "MB10TO"
        const val VERSION = 1

        /** Строка в конверте (любой версии) — иначе строка старого отправителя без конверта. */
        fun isEnvelope(line: String): Boolean = line.startsWith("$MAGIC:")

        /** null — не конверт, другая версия или битый. */
        fun decode(line: String): LineEnvelope? {
            val parts = line.split(":", limit = 6)
            val header = parts.size == 6 && parts[0] == MAGIC && parts[1] == "v$VERSION"
            if (!header || parts[2].isEmpty()) return null
            val port = parts[4].toIntOrNull() ?: return null
            return LineEnvelope(parts[2], parts[3], port, parts[5])
        }
    }
}

/**
 * Ответ получателя на строку в конверте: [status] и его собственный ключ [key].
 * [Status.OK] — строка для него, обработана (у Мегаблока — сохранена) до ответа; [Status.WRONG] — по этому адресу другой
 * игрок, строку он НЕ обработал; [Status.REJECT] — адресат тот, но строку не принял (нет личности, непонятная строка).
 */
data class LineAck(val status: Status, val key: String) {
    enum class Status(val wire: String) { OK("ok"), WRONG("wrong"), REJECT("reject") }

    fun encode(): String = "$MAGIC:v$VERSION:${status.wire}:$key"

    companion object {
        const val MAGIC = "MB10ACK"
        const val VERSION = 1

        fun decode(line: String): LineAck? {
            val parts = line.split(":", limit = 4)
            if (parts.size < 4 || parts[0] != MAGIC || parts[1] != "v$VERSION") return null
            val status = Status.values().firstOrNull { it.wire == parts[2] } ?: return null
            return LineAck(status, parts[3])
        }
    }
}
