package com.megablok10.rules

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.io.File

/**
 * Файлы, общие с Godot-частью (netrun/): числа взлома и golden-наборы. Тесты :rules сверяют файлы с кодом; при
 * `UPDATE_NETRUN_JSON=1` вместо сверки переписывают файл (так он и появился), diff идёт в коммит вместе с правкой кода.
 */
internal object NetrunJsonFiles {
    private val updating get() = System.getenv("UPDATE_NETRUN_JSON") == "1"

    /** Корень репозитория: тесты запускаются из каталога модуля, но поднимаемся по дереву, чтобы не зависеть от рабочего каталога. */
    private fun repoRoot(): File {
        var dir: File? = File("").absoluteFile
        while (dir != null && !File(dir, "netrun/data").isDirectory) dir = dir.parentFile
        return requireNotNull(dir) { "не нашёл корень репозитория (netrun/data) выше ${File("").absoluteFile}" }
    }

    fun file(path: String) = File(repoRoot(), path)

    /** Читает файл репозитория; если идёт выгрузка — сначала записывает [expected] (если он задан). */
    fun load(path: String, expected: JsonElement?): JsonElement {
        val f = file(path)
        if (updating && expected != null) {
            f.parentFile.mkdirs()
            f.writeText(render(expected) + "\n")
        }
        require(f.isFile) { "нет файла $path: запустите тест с UPDATE_NETRUN_JSON=1" }
        return Json.parseToJsonElement(f.readText())
    }

    /** Читаемый вывод: объекты по строке на ключ, массивы чисел/строк/координат — в одну строку. */
    fun render(e: JsonElement, indent: Int = 0): String = when (e) {
        is JsonPrimitive -> e.toString()
        is JsonArray ->
            if (e.all { it is JsonPrimitive || (it is JsonArray && it.all { x -> x is JsonPrimitive }) }) {
                e.joinToString(", ", "[", "]") { render(it) }
            } else {
                val pad = " ".repeat(indent + 2)
                e.joinToString(",\n", "[\n", "\n" + " ".repeat(indent) + "]") { pad + render(it, indent + 2) }
            }
        is JsonObject -> {
            val pad = " ".repeat(indent + 2)
            e.entries.joinToString(",\n", "{\n", "\n" + " ".repeat(indent) + "}") { (k, v) -> pad + "\"$k\": " + render(v, indent + 2) }
        }
    }
}
