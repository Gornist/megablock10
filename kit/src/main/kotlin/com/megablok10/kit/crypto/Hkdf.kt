package com.megablok10.kit.crypto

import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * HKDF-SHA256 (RFC 5869): ключ нужной длины из общего секрета (например, «кода игры», который мастер раздаёт всем телефонам
 * одной игры). Тот же вывод даёт `crypto.hkdfSync("sha256", …)` на Node — так сервер и телефоны получают один ключ, не
 * передавая его. Пустая соль по RFC — HashLen нулевых байт; передавайте её явно, чтобы обе стороны не расходились в умолчаниях.
 */
object Hkdf {
    private const val HASH_LEN = 32
    private const val MAC = "HmacSHA256"

    fun sha256(ikm: ByteArray, salt: ByteArray, info: ByteArray, length: Int): ByteArray {
        require(length in 1..255 * HASH_LEN) { "HKDF-SHA256 выдаёт от 1 до ${255 * HASH_LEN} байт, запрошено $length" }
        val mac = Mac.getInstance(MAC)
        mac.init(SecretKeySpec(if (salt.isEmpty()) ByteArray(HASH_LEN) else salt, MAC))
        val prk = mac.doFinal(ikm)
        mac.init(SecretKeySpec(prk, MAC))
        val out = ByteArray(length)
        var previous = ByteArray(0)
        var offset = 0
        var counter = 1
        while (offset < length) {
            mac.update(previous)
            mac.update(info)
            mac.update(counter.toByte())
            previous = mac.doFinal()
            val n = minOf(previous.size, length - offset)
            System.arraycopy(previous, 0, out, offset, n)
            offset += n
            counter++
        }
        return out
    }
}
