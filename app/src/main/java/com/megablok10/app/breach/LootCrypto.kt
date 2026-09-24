package com.megablok10.app.breach

import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Шифрует payload лут-слотов AES-GCM ключом этой игры (см. [deriveKey]).
 * Модель угрозы — игрок с телефоном и обычным сканером QR на полигоне, не
 * реверс-инженер: цель не защититься от разбора APK, а не дать прочитать
 * шард стандартным QR-сканером мимо мини-игры взлома. Ключ намеренно не
 * Android Keystore — его не нужно привязывать к устройству, все телефоны
 * этой игры должны уметь читать один и тот же контейнер.
 */
object LootCrypto {
    // 32 байта — AES-256, ключ по умолчанию, если GAME_SECRET не настроен
    // (см. deriveKey) — тот самый ключ, что был единственным в v1. Смена
    // этой константы делает нечитаемыми payload'ы всех уже напечатанных
    // QR игр без GAME_SECRET.
    private val FALLBACK_KEY = byteArrayOf(
        0x4d, 0x42, 0x31, 0x30, 0x2d, 0x4c, 0x4f, 0x4f,
        0x54, 0x2d, 0x76, 0x31, 0x2d, 0x6b, 0x65, 0x79,
        0x2d, 0x62, 0x72, 0x65, 0x61, 0x63, 0x68, 0x2d,
        0x70, 0x72, 0x6f, 0x74, 0x6f, 0x63, 0x6f, 0x6c
    )
    // "Нет соли" по RFC 5869 — HashLen (32) нулевых байт, явно, а не по умолчанию.
    private val HKDF_SALT = ByteArray(32)
    private val HKDF_INFO = "mb10-loot-v1".toByteArray(Charsets.UTF_8)
    private const val IV_BYTES = 12
    private const val TAG_BITS = 128

    /**
     * Ключ AES-256 для лута этой игры: без GAME_SECRET — FALLBACK_KEY (как
     * было всегда), с GAME_SECRET — HKDF-SHA256(secret) с тем же salt/info,
     * что и зеркало admin-web/server/src/lib/lootCrypto.ts (deriveLootKey),
     * так что ключ совпадает у всех телефонов этой игры, но не совпадает с
     * ключом другой игры или со старым публичным ключом. secret приходит из
     * CollectorSettings.gameSecret — доставлен полем QR персонажа (см.
     * docs/provisioning-qr.md), отдельной инфраструктуры не требуется.
     */
    fun deriveKey(gameSecret: String?): ByteArray {
        val secret = gameSecret?.trim()?.takeIf { it.isNotEmpty() } ?: return FALLBACK_KEY
        return hkdfSha256(ikm = secret.toByteArray(Charsets.UTF_8), salt = HKDF_SALT, info = HKDF_INFO, length = 32)
    }

    fun encrypt(plain: String, key: ByteArray): String {
        val iv = ByteArray(IV_BYTES).also { java.security.SecureRandom().nextBytes(it) }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(TAG_BITS, iv))
        val encrypted = cipher.doFinal(plain.toByteArray(Charsets.UTF_8))
        return Base64.getEncoder().encodeToString(iv + encrypted)
    }

    /** null — payload битый или зашифрован другим ключом (например, QR другой игры или прошлого акта). */
    fun decrypt(payloadB64: String, key: ByteArray): String? = try {
        val bytes = Base64.getDecoder().decode(payloadB64)
        val iv = bytes.copyOfRange(0, IV_BYTES)
        val body = bytes.copyOfRange(IV_BYTES, bytes.size)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(TAG_BITS, iv))
        String(cipher.doFinal(body), Charsets.UTF_8)
    } catch (e: Exception) {
        null
    }

    /** HKDF-SHA256 (RFC 5869), только Extract + один блок Expand — этого хватает ровно на length <= 32. */
    private fun hkdfSha256(ikm: ByteArray, salt: ByteArray, info: ByteArray, length: Int): ByteArray {
        require(length in 1..32) { "single-block HKDF-Expand only covers up to 32 bytes" }
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(salt, "HmacSHA256"))
        val prk = mac.doFinal(ikm)
        mac.init(SecretKeySpec(prk, "HmacSHA256"))
        val t1 = mac.doFinal(info + byteArrayOf(0x01))
        return t1.copyOf(length)
    }
}
