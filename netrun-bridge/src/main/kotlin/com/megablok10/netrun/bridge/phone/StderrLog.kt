package com.megablok10.netrun.bridge.phone

import com.megablok10.kit.log.KitLog
import com.megablok10.kit.log.LogFormat

/** Журнал Моста для kit: строки `уровень/тег имя поле=значение` в stderr (тот же вид, что у журнала приложения). */
object StderrLog : KitLog {
    private fun out(level: Char, tag: String, msg: String) = System.err.println("$level/$tag $msg")

    override fun d(tag: String, msg: String, t: Throwable?) = Unit
    override fun i(tag: String, msg: String, t: Throwable?) = out('I', tag, msg)
    override fun w(tag: String, msg: String, t: Throwable?) = out('W', tag, msg)
    override fun e(tag: String, msg: String, t: Throwable?) = out('E', tag, msg)
    override fun event(tag: String, name: String, vararg fields: Pair<String, Any?>) = out('I', tag, LogFormat.event(name, fields))
    override fun warnEvent(tag: String, name: String, vararg fields: Pair<String, Any?>) = out('W', tag, LogFormat.event(name, fields))
}
