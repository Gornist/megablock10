package com.megablok10.kit.sync

/**
 * Единица обмена с мастерским сервером: «что изменилось у игрока» — поле, старое и новое значение, причина, откуда взялось.
 * Устройство подписывает каждую запись ключом игрока; сервер хранит историю и отдаёт обратно правки мастера тем же форматом.
 * Зеркало серверного admin-web/server/src/lib/changeRecord.ts: те же поля, тот же формат подписи ([signaturePayload]).
 *
 * oldValue/newValue — уже готовая строка (число или JSON сложного значения), не структура: сервер сверяет подпись побайтово
 * по тому, что реально легло в HTTP-тело, не пересобирая её заново. Если положить структуру и сериализовать её отдельно на
 * каждом конце, подписи разойдутся из-за разницы JSON-сериализаторов Kotlin/JS.
 *
 * Какие бывают [field] и [reason] — решает приложение (у Мегаблока — ChangeField/ChangeReason), kit их не интерпретирует.
 */
data class ChangeRecord(
    val id: String,
    val subjectKeyB64: String,
    val seq: Long,
    val happenedAt: Long,
    val field: String,
    val oldValue: String?,
    val newValue: String?,
    val reason: String,
    val sourceRef: String?,
    val actor: String,
    val signature: String,
)

/** Байты, которые подписываются — плоский pipe-формат, как signaturePayload на сервере; null — пустое поле, не слово «null». */
fun ChangeRecord.signaturePayload(): ByteArray {
    val parts = listOf(
        id, subjectKeyB64, seq.toString(), happenedAt.toString(), field,
        oldValue ?: "", newValue ?: "", reason, sourceRef ?: "", actor,
    )
    return parts.joinToString("|").toByteArray(Charsets.UTF_8)
}
