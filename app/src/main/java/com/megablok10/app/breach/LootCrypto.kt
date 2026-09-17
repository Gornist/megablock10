package com.megablok10.app.breach

import android.util.Base64
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Шифрует payload лут-слотов AES-GCM с ключом, зашитым в APK. Модель угрозы —
 * игрок с телефоном и обычным сканером QR на полигоне, не реверс-инженер:
 * цель не защититься от разбора APK, а не дать прочитать шард стандартным
 * QR-сканером мимо мини-игры взлома. Ключ намеренно не Android Keystore —
 * его не нужно привязывать к устройству, все копии приложения должны уметь
 * читать один и тот же контейнер.
 */
object LootCrypto {
    // 32 байта — AES-256. Смена этой константы делает нечитаемыми payload'ы
    // всех уже напечатанных мастерами QR текущей игры — не менять между актами.
    private val KEY = byteArrayOf(
        0x4d, 0x42, 0x31, 0x30, 0x2d, 0x4c, 0x4f, 0x4f,
        0x54, 0x2d, 0x76, 0x31, 0x2d, 0x6b, 0x65, 0x79,
        0x2d, 0x62, 0x72, 0x65, 0x61, 0x63, 0x68, 0x2d,
        0x70, 0x72, 0x6f, 0x74, 0x6f, 0x63, 0x6f, 0x6c
    )
    private const val IV_BYTES = 12
    private const val TAG_BITS = 128

    fun encrypt(plain: String): String {
        val iv = ByteArray(IV_BYTES).also { java.security.SecureRandom().nextBytes(it) }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(KEY, "AES"), GCMParameterSpec(TAG_BITS, iv))
        val encrypted = cipher.doFinal(plain.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(iv + encrypted, Base64.NO_WRAP)
    }

    /** null — payload битый или зашифрован другим ключом (например, QR прошлого акта после ротации KEY). */
    fun decrypt(payloadB64: String): String? = try {
        val bytes = Base64.decode(payloadB64, Base64.NO_WRAP)
        val iv = bytes.copyOfRange(0, IV_BYTES)
        val body = bytes.copyOfRange(IV_BYTES, bytes.size)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(KEY, "AES"), GCMParameterSpec(TAG_BITS, iv))
        String(cipher.doFinal(body), Charsets.UTF_8)
    } catch (e: Exception) {
        null
    }
}
