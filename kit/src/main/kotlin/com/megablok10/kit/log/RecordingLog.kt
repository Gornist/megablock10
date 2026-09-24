package com.megablok10.kit.log

/**
 * Журнал в память — для тестов: проверить, что компонент записал нужное событие (или не записал лишнего). Строки — в том же
 * формате, что у настоящего журнала: `I/Тег имя поле=значение`.
 */
class RecordingLog : KitLog {
    private val lines = mutableListOf<String>()

    val all: List<String> @Synchronized get() = lines.toList()

    @Synchronized private fun add(level: Char, tag: String, msg: String) { lines += "$level/$tag $msg" }

    override fun d(tag: String, msg: String, t: Throwable?) = add('D', tag, msg)
    override fun i(tag: String, msg: String, t: Throwable?) = add('I', tag, msg)
    override fun w(tag: String, msg: String, t: Throwable?) = add('W', tag, msg)
    override fun e(tag: String, msg: String, t: Throwable?) = add('E', tag, msg)
    override fun event(tag: String, name: String, vararg fields: Pair<String, Any?>) = add('I', tag, LogFormat.event(name, fields))
    override fun warnEvent(tag: String, name: String, vararg fields: Pair<String, Any?>) = add('W', tag, LogFormat.event(name, fields))

    /** Есть ли строка, содержащая [fragment] (например, `"outbox.sent"` или `"W/OutboxStore outbox.retry"`). */
    fun has(fragment: String): Boolean = all.any { fragment in it }
}
