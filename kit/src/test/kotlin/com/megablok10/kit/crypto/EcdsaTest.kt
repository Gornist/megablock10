package com.megablok10.kit.crypto

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class EcdsaTest {
    private val pair = Ecdsa.generateKeyPair()
    private val pub = Ecdsa.encodeKey(pair.public)
    private val data = "TX2|id|from|to|100|memo".toByteArray()

    @Test
    fun `подпись проверяется тем же публичным ключом`() {
        assertTrue(Ecdsa.verify(pub, data, Ecdsa.sign(pair.private, data)))
    }

    @Test
    fun `ключи переживают кодирование в base64 и обратно`() {
        val privB64 = Ecdsa.encodeKey(pair.private)
        val sig = Ecdsa.sign(Ecdsa.decodePrivateKey(privB64), data)
        assertTrue(Ecdsa.verify(Ecdsa.encodeKey(Ecdsa.decodePublicKey(pub)), data, sig))
        assertEquals(pub, Ecdsa.encodeKey(Ecdsa.decodePublicKey(pub)))
    }

    @Test
    fun `другие данные или другой ключ — false`() {
        val sig = Ecdsa.sign(pair.private, data)
        assertFalse(Ecdsa.verify(pub, "TX2|id|from|to|101|memo".toByteArray(), sig))
        assertFalse(Ecdsa.verify(Ecdsa.encodeKey(Ecdsa.generateKeyPair().public), data, sig))
    }

    @Test
    fun `битые ключ и подпись — false, а не исключение`() {
        val sig = Ecdsa.sign(pair.private, data)
        assertFalse(Ecdsa.verify("не ключ", data, sig))
        assertFalse(Ecdsa.verify("", data, sig))
        assertFalse(Ecdsa.verify(pub, data, ""))
        assertFalse(Ecdsa.verify(pub, data, "AAAA"))
    }

    @Test
    fun `кодирование — одна строка без переносов, как android Base64 NO_WRAP`() {
        val sig = Ecdsa.sign(pair.private, data)
        assertFalse(pub.contains('\n') || sig.contains('\n'))
        assertTrue(Regex("[A-Za-z0-9+/]+=*").matches(pub))
    }

    @Test
    fun `проверка снисходительна к переносам и пробелам внутри base64, как android Base64`() {
        val sig = Ecdsa.sign(pair.private, data)
        val wrapped = sig.chunked(16).joinToString("\n")
        assertTrue(Ecdsa.verify(pub, data, wrapped))
        assertTrue(Ecdsa.verify(pub.chunked(20).joinToString("\r\n"), data, sig))
    }

    /**
     * Фиксированный вектор: одноразовый тестовый ключ (нигде больше не используется) и его подпись сгенерированы один раз и лежат здесь как есть. Если кодирование ключей или алгоритм
     * подписи поменяются (а с ними — совместимость с уже выданными персонажами и с сервером), покраснеет этот тест.
     */
    @Test
    fun `фиксированный вектор — формат ключа и подписи не поменялся`() {
        assertTrue(Ecdsa.verify(VECTOR_PUB, VECTOR_DATA.toByteArray(), VECTOR_SIG))
        assertFalse(Ecdsa.verify(VECTOR_PUB, (VECTOR_DATA + "x").toByteArray(), VECTOR_SIG))
        assertTrue(Ecdsa.verify(VECTOR_PUB, VECTOR_DATA.toByteArray(), Ecdsa.sign(Ecdsa.decodePrivateKey(VECTOR_PRIV), VECTOR_DATA.toByteArray())))
    }

    private companion object {
        const val VECTOR_DATA = "kit-ecdsa-vector|1"
        const val VECTOR_PUB = "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE4LdPji+vE9q0CgF0j356ChCiZbe563uy+3maqONIju8mo6mw5sevmX8DqVFV/SAt5ic/6i+IxSVL3ybivUNYbQ=="
        const val VECTOR_PRIV = "MEECAQAwEwYHKoZIzj0CAQYIKoZIzj0DAQcEJzAlAgEBBCCPJjQlIVxk0VXteulJk14Ss1yYD8/+juVpo+MWLrR+Zg=="
        const val VECTOR_SIG = "MEQCIDe8lInuv9XhxSFdCfN7DDjUbfbyr+grimiuDquRmq0LAiAFgQ4ehFW+4npdBiwbxqwmlFzE7RH1EkJlf5dtNPwv4w=="
    }
}
