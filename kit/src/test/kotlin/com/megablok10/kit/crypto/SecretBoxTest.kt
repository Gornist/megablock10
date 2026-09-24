package com.megablok10.kit.crypto

import java.util.Base64
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SecretBoxTest {
    private val key = ByteArray(32) { it.toByte() }
    private val otherKey = ByteArray(32) { (it + 1).toByte() }

    @Test
    fun `текст проходит туда и обратно, включая кириллицу и разделители`() {
        val plain = "SHARD|заголовок|мета:с:двоеточиями|тело\nс переводом строки|0"
        assertEquals(plain, SecretBox.open(SecretBox.seal(plain, key), key))
    }

    @Test
    fun `один и тот же текст каждый раз шифруется по-разному — IV случайный`() {
        assertNotEquals(SecretBox.seal("одно и то же", key), SecretBox.seal("одно и то же", key))
    }

    @Test
    fun `формат — IV 12 байт, шифртекст, тег 16 байт`() {
        val plain = "12345"
        val bytes = Base64.getDecoder().decode(SecretBox.seal(plain, key))
        assertEquals(SecretBox.IV_BYTES + plain.length + SecretBox.TAG_BITS / 8, bytes.size)
    }

    @Test
    fun `чужой ключ, подмена байта, обрезка и мусор — null, а не исключение и не искажённый текст`() {
        val sealed = SecretBox.seal("нетронутый текст", key)
        assertNull(SecretBox.open(sealed, otherKey))
        val bytes = Base64.getDecoder().decode(sealed)
        bytes[bytes.size - 1] = (bytes[bytes.size - 1] + 1).toByte()
        assertNull(SecretBox.open(Base64.getEncoder().encodeToString(bytes), key))
        assertNull(SecretBox.open("AAAA", key))
        assertNull(SecretBox.open("not-valid-base64!!!", key))
        assertNull(SecretBox.open("", key))
    }
}
