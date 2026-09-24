package com.megablok10.kit.text

import java.util.Base64

/**
 * Свободный текст внутри построчных форматов (`МАГИЯ:ТИП:v1:поле:поле…`, поля через `|` и т. п.): кодируется в base64, чтобы
 * двоеточия, разделители и переводы строк в тексте автора не ломали разбор строки. Стандартный алфавит RFC 4648 с `=` —
 * тот же, что у java.util.Base64 и у сервера на Node (`Buffer.toString("base64")`).
 *
 * Декодирование строгое: мусор в поле — исключение IllegalArgumentException, которое разборщик формата ловит и возвращает null
 * («это не наш код»), а не молча показывает игроку искажённый текст.
 */
object Base64Text {
    fun encode(text: String): String = Base64.getEncoder().encodeToString(text.toByteArray(Charsets.UTF_8))

    fun decode(b64: String): String = String(Base64.getDecoder().decode(b64), Charsets.UTF_8)
}
