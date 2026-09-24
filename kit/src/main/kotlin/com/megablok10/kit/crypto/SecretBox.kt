package com.megablok10.kit.crypto

import java.security.SecureRandom
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Симметричное шифрование строк AES-GCM (ключ 16/24/32 байта) для содержимого, которое печатают в QR и читают все телефоны
 * одной игры: формат — base64(IV 12 байт ‖ шифртекст ‖ тег 16 байт), тот же, что собирает сервер на Node
 * (`createCipheriv("aes-256-gcm", …)`, IV + данные + authTag).
 *
 * GCM ещё и подтверждает целостность: изменённый или чужим ключом зашифрованный блок не расшифруется вовсе ([open] вернёт null),
 * а не превратится в мусор.
 */
object SecretBox {
    private const val TRANSFORMATION = "AES/GCM/NoPadding"
    const val IV_BYTES = 12
    const val TAG_BITS = 128
    private val random = SecureRandom()

    fun seal(plain: String, key: ByteArray): String {
        val iv = ByteArray(IV_BYTES).also { random.nextBytes(it) }
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(TAG_BITS, iv))
        return Base64.getEncoder().encodeToString(iv + cipher.doFinal(plain.toByteArray(Charsets.UTF_8)))
    }

    /** null — блок битый, обрезан или зашифрован другим ключом. */
    fun open(sealedB64: String, key: ByteArray): String? = try {
        val bytes = Base64.getDecoder().decode(sealedB64)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(TAG_BITS, bytes.copyOfRange(0, IV_BYTES)))
        String(cipher.doFinal(bytes.copyOfRange(IV_BYTES, bytes.size)), Charsets.UTF_8)
    } catch (e: Exception) {
        null
    }
}
