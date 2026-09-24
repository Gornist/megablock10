package com.megablok10.kit.crypto

import java.security.Key
import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.PrivateKey
import java.security.PublicKey
import java.security.Signature
import java.security.spec.ECGenParameterSpec
import java.security.spec.PKCS8EncodedKeySpec
import java.security.spec.X509EncodedKeySpec
import java.util.Base64

/**
 * Подписи ECDSA P-256 (secp256r1, SHA256withECDSA) — ключ персонажа и все подписи протоколов (переводы, чеки, заявки на слоты,
 * записи для мастерского сервера). Публичный ключ в base64 (X.509 SubjectPublicKeyInfo) — он же идентификатор игрока везде.
 *
 * Только стандартный java.security: работает одинаково на Android (minSdk 26) и на JVM, а тот же формат читает сервер на Node
 * (`crypto.verify("sha256", …)` с ключом SPKI/DER).
 *
 * Base64: кодирование — стандартный алфавит без переносов строк (то же, что android.util.Base64.NO_WRAP, которым подписывало
 * приложение до переезда в kit). Декодирование ключей и подписей — «снисходительное» (MIME-декодер пропускает символы вне
 * алфавита), как android.util.Base64: подпись, которую раньше проверка принимала, принимает и сейчас.
 */
object Ecdsa {
    const val CURVE = "secp256r1"
    const val SIGNATURE_ALGORITHM = "SHA256withECDSA"
    private const val KEY_ALGORITHM = "EC"

    fun generateKeyPair(): KeyPair =
        KeyPairGenerator.getInstance(KEY_ALGORITHM).apply { initialize(ECGenParameterSpec(CURVE)) }.generateKeyPair()

    /** Ключ (публичный — X.509, закрытый — PKCS#8) в base64 для хранения и передачи. */
    fun encodeKey(key: Key): String = Base64.getEncoder().encodeToString(key.encoded)

    fun decodePublicKey(b64: String): PublicKey =
        KeyFactory.getInstance(KEY_ALGORITHM).generatePublic(X509EncodedKeySpec(decodeLenient(b64)))

    fun decodePrivateKey(b64: String): PrivateKey =
        KeyFactory.getInstance(KEY_ALGORITHM).generatePrivate(PKCS8EncodedKeySpec(decodeLenient(b64)))

    /** Подпись [data] закрытым ключом, в base64. */
    fun sign(privateKey: PrivateKey, data: ByteArray): String {
        val signature = Signature.getInstance(SIGNATURE_ALGORITHM)
        signature.initSign(privateKey)
        signature.update(data)
        return Base64.getEncoder().encodeToString(signature.sign())
    }

    /** Проверка подписи чужим публичным ключом. Никогда не бросает: битый ключ, битая подпись, чужой формат — просто false. */
    fun verify(publicKeyB64: String, data: ByteArray, signatureB64: String): Boolean = try {
        val signature = Signature.getInstance(SIGNATURE_ALGORITHM)
        signature.initVerify(decodePublicKey(publicKeyB64))
        signature.update(data)
        signature.verify(decodeLenient(signatureB64))
    } catch (e: Exception) {
        false
    }

    private fun decodeLenient(b64: String): ByteArray = Base64.getMimeDecoder().decode(b64)
}
