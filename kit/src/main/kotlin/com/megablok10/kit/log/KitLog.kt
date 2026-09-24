package com.megablok10.kit.log

/**
 * Журнал, в который пишут компоненты kit. Приложение подставляет свою реализацию (в Мегаблоке это Mb10Log: logcat + файл
 * на устройстве), в тестах — [NoopLog] или [RecordingLog]. Компоненты kit не знают, куда уходят записи.
 *
 * Правила записей те же, что у журнала приложения: теги и имена событий стабильны (по ним разбирают журналы живых проверок),
 * публичные ключи только в сокращении [shortKey], секреты и тексты сообщений не пишутся никогда — только длины, id и исходы.
 */
interface KitLog {
    fun d(tag: String, msg: String, t: Throwable? = null)
    fun i(tag: String, msg: String, t: Throwable? = null)
    fun w(tag: String, msg: String, t: Throwable? = null)
    fun e(tag: String, msg: String, t: Throwable? = null)

    /** Событие с полями: `send.outcome to=ab12cd34 outcome=DELIVERED ms=41`. Поля со значением null пропускаются. */
    fun event(tag: String, name: String, vararg fields: Pair<String, Any?>)

    /** То же на уровне предупреждения — для отказов и неожиданных исходов. */
    fun warnEvent(tag: String, name: String, vararg fields: Pair<String, Any?>)
}

/** Журнал, который ничего не пишет: значение по умолчанию для тестов и для компонентов, которым журнал не передали. */
object NoopLog : KitLog {
    override fun d(tag: String, msg: String, t: Throwable?) = Unit
    override fun i(tag: String, msg: String, t: Throwable?) = Unit
    override fun w(tag: String, msg: String, t: Throwable?) = Unit
    override fun e(tag: String, msg: String, t: Throwable?) = Unit
    override fun event(tag: String, name: String, vararg fields: Pair<String, Any?>) = Unit
    override fun warnEvent(tag: String, name: String, vararg fields: Pair<String, Any?>) = Unit
}

/**
 * Ключ в сокращении для журнала: последние 8 букв/цифр — хватает, чтобы различать игроков, и ключ целиком не раскрывается.
 * null и пустая строка — «-».
 */
fun shortKey(pubKeyB64: String?): String = when {
    pubKeyB64.isNullOrEmpty() -> "-"
    else -> pubKeyB64.filter { it.isLetterOrDigit() }.takeLast(8)
}

/** Формат строк журнала, общий для всех реализаций [KitLog]: так журналы разных приложений на kit читаются одинаково. */
object LogFormat {
    /** `имя ключ=значение ключ="значение с пробелами"`; поля со значением null пропускаются. */
    fun event(name: String, fields: Array<out Pair<String, Any?>>): String {
        val body = fields.filter { it.second != null }.joinToString(" ") { (k, v) -> "$k=${quote(v.toString())}" }
        return if (body.isEmpty()) name else "$name $body"
    }

    private fun quote(v: String): String =
        if (v.isEmpty() || v.any(::needsQuotes)) "\"" + v.replace("\"", "'").replace("\n", " ") + "\"" else v

    private fun needsQuotes(c: Char): Boolean = c == ' ' || c == '"' || c == '\n'
}
