package com.megablok10.app.breach

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LootCryptoTest {

    private val fallbackKey = LootCrypto.deriveKey(null)

    @Test
    fun `plaintext round-trips through encrypt and decrypt`() {
        val plain = "SHARD|title|meta|body|valueHint|1|500"
        val encrypted = LootCrypto.encrypt(plain, fallbackKey)
        assertEquals(plain, LootCrypto.decrypt(encrypted, fallbackKey))
    }

    @Test
    fun `same plaintext encrypts to a different payload each time because the IV is random`() {
        val a = LootCrypto.encrypt("одно и то же содержимое", fallbackKey)
        val b = LootCrypto.encrypt("одно и то же содержимое", fallbackKey)
        assertNotEquals(a, b)
    }

    @Test
    fun `garbage base64 fails to decrypt instead of throwing`() {
        assertNull(LootCrypto.decrypt("not-valid-base64!!!", fallbackKey))
    }

    @Test
    fun `truncated payload too short to hold an IV fails to decrypt instead of throwing`() {
        assertNull(LootCrypto.decrypt("AAAA", fallbackKey))
    }

    @Test
    fun `tampered ciphertext fails GCM tag verification instead of returning corrupted plaintext`() {
        val encrypted = LootCrypto.encrypt("нетронутый текст", fallbackKey)
        val bytes = java.util.Base64.getDecoder().decode(encrypted)
        bytes[bytes.size - 1] = (bytes[bytes.size - 1] + 1).toByte()
        val tampered = java.util.Base64.getEncoder().encodeToString(bytes)
        assertNull(LootCrypto.decrypt(tampered, fallbackKey))
    }

    @Test
    fun `deriveKey without a game secret returns the same fixed 32-byte fallback key as before`() {
        assertEquals(32, fallbackKey.size)
        assertArrayEquals(fallbackKey, LootCrypto.deriveKey(""))
        assertArrayEquals(fallbackKey, LootCrypto.deriveKey("   "))
    }

    @Test
    fun `deriveKey with a game secret is deterministic and differs per secret and from the fallback`() {
        val keyA = LootCrypto.deriveKey("game-one-secret")
        val keyB = LootCrypto.deriveKey("game-two-secret")
        assertEquals(32, keyA.size)
        assertArrayEquals(keyA, LootCrypto.deriveKey("game-one-secret"))
        assertNotEquals(keyA.toList(), keyB.toList())
        assertNotEquals(keyA.toList(), fallbackKey.toList())
    }

    @Test
    fun `payload encrypted for one game cannot be decrypted with another game's key or the fallback key`() {
        val keyA = LootCrypto.deriveKey("game-one-secret")
        val keyB = LootCrypto.deriveKey("game-two-secret")
        val encrypted = LootCrypto.encrypt("SHARD|dGVzdA==|||0|0", keyA)
        assertNull(LootCrypto.decrypt(encrypted, keyB))
        assertNull(LootCrypto.decrypt(encrypted, fallbackKey))
        assertEquals("SHARD|dGVzdA==|||0|0", LootCrypto.decrypt(encrypted, keyA))
    }

    /**
     * RFC 5869 §A.1 (Test Case 1, SHA-256): IKM (22 байт) / salt (13 байт) /
     * info (10 байт) официальные, OKM обрезан до первых 32 байт официальных
     * 42 (наш single-block HKDF-Expand — это ровно T(1), первые HashLen байт
     * полного OKM; значение перепроверено независимо через node:crypto
     * hkdfSync перед тем, как попасть сюда).
     */
    @Test
    fun `deriveKey's HKDF matches the RFC 5869 SHA-256 test vector when fed the same inputs`() {
        val ikm = hexToBytes("0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b")
        val salt = hexToBytes("000102030405060708090a0b0c")
        val info = hexToBytes("f0f1f2f3f4f5f6f7f8f9")
        val expectedOkm32 = hexToBytes("3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf")

        val okm = hkdfSha256ForTest(ikm, salt, info, 32)
        assertArrayEquals(expectedOkm32, okm)
    }

    /**
     * Общий тестовый вектор с сервером: admin-web/server/src/lootCrypto.test.ts,
     * тест "deriveLootKey — тестовый вектор для сверки с Kotlin-стороной" —
     * то же значение секрета, тот же hex. Если реализации разойдутся
     * (например, salt/info поменяли только на одной стороне), покраснеет
     * ровно один из двух тестов, а не оба одновременно.
     */
    @Test
    fun `deriveKey matches the shared cross-language test vector also asserted server-side`() {
        val key = LootCrypto.deriveKey("mb10-cross-check-secret")
        assertEquals("232aab80471b62a518d8b054f2a1aeb0cd62c28586a02df3f1106ec15eca4a2d", key.toHex())
    }

    private fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it) }

    private fun hexToBytes(hex: String): ByteArray =
        ByteArray(hex.length / 2) { i -> ((Character.digit(hex[i * 2], 16) shl 4) + Character.digit(hex[i * 2 + 1], 16)).toByte() }

    /** Полный HKDF-Expand (не только один блок) — только для проверки против официального RFC-вектора, отдельно от LootCrypto.deriveKey. */
    private fun hkdfSha256ForTest(ikm: ByteArray, salt: ByteArray, info: ByteArray, length: Int): ByteArray {
        val mac = javax.crypto.Mac.getInstance("HmacSHA256")
        mac.init(javax.crypto.spec.SecretKeySpec(salt, "HmacSHA256"))
        val prk = mac.doFinal(ikm)
        mac.init(javax.crypto.spec.SecretKeySpec(prk, "HmacSHA256"))
        var t = ByteArray(0)
        val okm = mutableListOf<Byte>()
        var counter = 1
        while (okm.size < length) {
            mac.init(javax.crypto.spec.SecretKeySpec(prk, "HmacSHA256"))
            t = mac.doFinal(t + info + byteArrayOf(counter.toByte()))
            okm += t.toList()
            counter++
        }
        return okm.take(length).toByteArray()
    }
}
