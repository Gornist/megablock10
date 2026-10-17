package com.megablok10.app.contracts

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File
import java.lang.reflect.Modifier

/**
 * Общие векторы контрактов между зонами: JSON-файлы в `rules/src/test/resources/contracts/` (описание — README.md рядом). Файлы читают
 * тесты всех сторон контракта; здесь — сторона приложения. Корень репозитория ищется вверх от рабочего каталога модуля.
 */
internal object ContractVectors {
    private const val DIR = "rules/src/test/resources/contracts"

    private fun dir(): File {
        var d: File? = File("").absoluteFile
        while (d != null && !File(d, DIR).isDirectory) d = d.parentFile
        return File(requireNotNull(d) { "не нашёл $DIR выше ${File("").absoluteFile}" }, DIR)
    }

    fun load(name: String): JsonObject = Json.parseToJsonElement(File(dir(), name).readText()).jsonObject

    /** Строковые `const val` объекта (ChangeField, ChangeReason): значения, которые сверяются со списками из файла. */
    fun stringConstants(holder: Class<*>): Set<String> =
        holder.declaredFields.filter { Modifier.isStatic(it.modifiers) && it.type == String::class.java }.map { it.get(null) as String }.toSet()
}

internal fun JsonElement.objects(): List<JsonObject> = jsonArray.map { it.jsonObject }

internal fun JsonElement.strings(): List<String> = (this as JsonArray).map { it.jsonPrimitive.content }

internal fun JsonObject.str(key: String): String = getValue(key).jsonPrimitive.content

/** null и JSON-`null` — одно и то же: «поля нет». */
internal fun JsonObject.strOrNull(key: String): String? = this[key]?.takeIf { it !is JsonNull }?.jsonPrimitive?.content

internal fun JsonObject.long(key: String): Long = getValue(key).jsonPrimitive.content.toLong()

internal fun JsonObject.bool(key: String): Boolean = getValue(key).jsonPrimitive.content.toBooleanStrict()

internal fun JsonObject.obj(key: String): JsonObject = getValue(key).jsonObject

internal fun JsonObject.list(key: String): List<JsonObject> = getValue(key).objects()
