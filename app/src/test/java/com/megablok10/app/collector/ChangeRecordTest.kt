package com.megablok10.app.collector

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

/**
 * signaturePayload() обязан побайтово совпадать с serverside
 * signaturePayload() в admin-web/server/src/lib/changeRecord.ts — сервер
 * проверяет подпись Android-клиента именно по этой строке. Разъедутся
 * форматы (порядок полей, разделитель, представление null) — все подписи
 * начнут молча отклоняться как невалидные, без единой ошибки компиляции
 * с обеих сторон, поэтому это закреплено тестом с фиксированной эталонной
 * строкой, а не только round-trip-проверкой внутри одного языка.
 */
class ChangeRecordTest {

    private fun sample(oldValue: String? = "5", newValue: String? = "6", sourceRef: String? = "ref-1") = ChangeRecord(
        id = "rec-1",
        subjectKeyB64 = "pubKeyB64==",
        seq = 42L,
        happenedAt = 1_700_000_000_000L,
        field = ChangeField.RAM_CAPACITY,
        oldValue = oldValue,
        newValue = newValue,
        reason = ChangeReason.RAM_UPGRADE,
        sourceRef = sourceRef,
        actor = "actorKeyB64==",
        signature = "",
    )

    @Test
    fun `payload matches the exact pipe-delimited format the TS server expects`() {
        val expected = "rec-1|pubKeyB64==|42|1700000000000|ramCapacity|5|6|RAM_UPGRADE|ref-1|actorKeyB64=="
        assertEquals(expected, String(sample().signaturePayload(), Charsets.UTF_8))
    }

    @Test
    fun `null oldValue, newValue and sourceRef become empty fields, not the literal null`() {
        val expected = "rec-1|pubKeyB64==|42|1700000000000|ramCapacity||6|RAM_UPGRADE||actorKeyB64=="
        val payload = sample(oldValue = null, sourceRef = null).signaturePayload()
        assertEquals(expected, String(payload, Charsets.UTF_8))
    }

    @Test
    fun `same record always produces the same payload`() {
        val a = sample().signaturePayload()
        val b = sample().signaturePayload()
        assertEquals(String(a, Charsets.UTF_8), String(b, Charsets.UTF_8))
    }

    @Test
    fun `changing any single field changes the payload`() {
        val base = sample()
        val variants = listOf(
            base.copy(id = "rec-2"),
            base.copy(subjectKeyB64 = "otherPub=="),
            base.copy(seq = 43L),
            base.copy(happenedAt = 1_700_000_000_001L),
            base.copy(field = ChangeField.BALANCE),
            base.copy(oldValue = "4"),
            base.copy(newValue = "7"),
            base.copy(reason = ChangeReason.MASTER_OVERRIDE),
            base.copy(sourceRef = "ref-2"),
            base.copy(actor = "otherActor=="),
        )
        val basePayload = String(base.signaturePayload(), Charsets.UTF_8)
        variants.forEach { variant ->
            assertNotEquals(basePayload, String(variant.signaturePayload(), Charsets.UTF_8))
        }
    }

    @Test
    fun `a value containing the pipe separator does not collide with adjacent empty fields`() {
        // Не идеальная защита (это не экранирование), но фиксирует текущее
        // поведение — значение с "|" внутри валидно и не путается с null,
        // пока сервер разбирает ровно так же (join, не JSON).
        val withPipe = sample(oldValue = "a|b").signaturePayload()
        val withoutPipe = sample(oldValue = "a").signaturePayload()
        assertNotEquals(String(withPipe, Charsets.UTF_8), String(withoutPipe, Charsets.UTF_8))
    }
}
