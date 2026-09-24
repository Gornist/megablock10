package com.megablok10.kit.crypto

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertThrows
import org.junit.Test

/** Официальные векторы RFC 5869, приложение A (SHA-256). */
class HkdfTest {
    private val ikm = hex("0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b")

    @Test
    fun `тест 1 — соль и info, 42 байта (два блока Expand)`() {
        val okm = Hkdf.sha256(ikm, hex("000102030405060708090a0b0c"), hex("f0f1f2f3f4f5f6f7f8f9"), 42)
        assertArrayEquals(hex("3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865"), okm)
    }

    @Test
    fun `тест 3 — пустые соль и info, соль по RFC это HashLen нулей`() {
        val expected = hex("8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d9d201395faa4b61a96c8")
        assertArrayEquals(expected, Hkdf.sha256(ikm, ByteArray(0), ByteArray(0), 42))
        assertArrayEquals(expected, Hkdf.sha256(ikm, ByteArray(32), ByteArray(0), 42))
    }

    @Test
    fun `короткий вывод — префикс длинного`() {
        val salt = hex("000102030405060708090a0b0c")
        val info = hex("f0f1f2f3f4f5f6f7f8f9")
        assertArrayEquals(Hkdf.sha256(ikm, salt, info, 42).copyOf(32), Hkdf.sha256(ikm, salt, info, 32))
    }

    @Test
    fun `недопустимая длина — ошибка, а не молча обрезанный ключ`() {
        assertThrows(IllegalArgumentException::class.java) { Hkdf.sha256(ikm, ByteArray(0), ByteArray(0), 0) }
        assertThrows(IllegalArgumentException::class.java) { Hkdf.sha256(ikm, ByteArray(0), ByteArray(0), 255 * 32 + 1) }
    }

    private fun hex(s: String): ByteArray = ByteArray(s.length / 2) { i -> s.substring(i * 2, i * 2 + 2).toInt(16).toByte() }
}
