package com.megablok10.app.breach

import com.megablok10.kit.crypto.Hkdf
import com.megablok10.kit.crypto.SecretBox

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
        return Hkdf.sha256(ikm = secret.toByteArray(Charsets.UTF_8), salt = HKDF_SALT, info = HKDF_INFO, length = 32)
    }

    /** AES-GCM, формат base64(IV ‖ шифртекст ‖ тег) — см. kit [SecretBox], тот же формат собирает сервер. */
    fun encrypt(plain: String, key: ByteArray): String = SecretBox.seal(plain, key)

    /** null — payload битый или зашифрован другим ключом (например, QR другой игры или прошлого акта). */
    fun decrypt(payloadB64: String, key: ByteArray): String? = SecretBox.open(payloadB64, key)
}
