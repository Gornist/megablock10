package com.megablok10.app.breach

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LootCryptoTest {

    @Test
    fun `plaintext round-trips through encrypt and decrypt`() {
        val plain = "SHARD|title|meta|body|valueHint|1|500"
        val encrypted = LootCrypto.encrypt(plain)
        assertEquals(plain, LootCrypto.decrypt(encrypted))
    }

    @Test
    fun `same plaintext encrypts to a different payload each time because the IV is random`() {
        val a = LootCrypto.encrypt("одно и то же содержимое")
        val b = LootCrypto.encrypt("одно и то же содержимое")
        assertNotEquals(a, b)
    }

    @Test
    fun `garbage base64 fails to decrypt instead of throwing`() {
        assertNull(LootCrypto.decrypt("not-valid-base64!!!"))
    }

    @Test
    fun `truncated payload too short to hold an IV fails to decrypt instead of throwing`() {
        assertNull(LootCrypto.decrypt("AAAA"))
    }

    @Test
    fun `tampered ciphertext fails GCM tag verification instead of returning corrupted plaintext`() {
        val encrypted = LootCrypto.encrypt("нетронутый текст")
        val bytes = java.util.Base64.getDecoder().decode(encrypted)
        bytes[bytes.size - 1] = (bytes[bytes.size - 1] + 1).toByte()
        val tampered = java.util.Base64.getEncoder().encodeToString(bytes)
        assertNull(LootCrypto.decrypt(tampered))
    }
}
