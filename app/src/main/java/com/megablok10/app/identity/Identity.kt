package com.megablok10.app.identity

import android.content.Context
import android.util.Base64
import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.PrivateKey
import java.security.PublicKey
import java.security.Signature
import java.security.spec.ECGenParameterSpec
import java.security.spec.PKCS8EncodedKeySpec
import java.security.spec.X509EncodedKeySpec

private const val PREFS = "identity_prefs"
private const val KEY_PRIVATE = "private_key"
private const val KEY_PUBLIC = "public_key"
private const val KEY_CALLSIGN = "callsign"
private const val KEY_FACTION = "faction"

data class Identity(
    val publicKeyB64: String,
    val callsign: String,
    val faction: String
)

/**
 * Персонаж = пара ключей ECDSA (secp256r1), сгенерированная один раз на устройстве.
 * Публичный ключ — это и есть его первичный идентификатор во всей системе
 * (контакты, шарды, транзакции). Приватный ключ пока хранится в обычных
 * SharedPreferences в base64 — для MVP-уровня угроз (живая игра, не банк)
 * этого достаточно; перенос в Android Keystore можно сделать позже без
 * изменения остального протокола.
 */
object IdentityManager {

    fun hasIdentity(context: Context): Boolean =
        prefs(context).contains(KEY_PUBLIC)

    fun getOrCreate(context: Context, callsign: String, faction: String): Identity {
        val p = prefs(context)
        val existingPub = p.getString(KEY_PUBLIC, null)
        if (existingPub != null) {
            return Identity(
                publicKeyB64 = existingPub,
                callsign = p.getString(KEY_CALLSIGN, callsign) ?: callsign,
                faction = p.getString(KEY_FACTION, faction) ?: faction
            )
        }

        val keyPair = generateKeyPair()
        val pubB64 = Base64.encodeToString(keyPair.public.encoded, Base64.NO_WRAP)
        val privB64 = Base64.encodeToString(keyPair.private.encoded, Base64.NO_WRAP)

        p.edit()
            .putString(KEY_PUBLIC, pubB64)
            .putString(KEY_PRIVATE, privB64)
            .putString(KEY_CALLSIGN, callsign)
            .putString(KEY_FACTION, faction)
            .apply()

        return Identity(pubB64, callsign, faction)
    }

    fun current(context: Context): Identity? {
        val p = prefs(context)
        val pub = p.getString(KEY_PUBLIC, null) ?: return null
        return Identity(
            publicKeyB64 = pub,
            callsign = p.getString(KEY_CALLSIGN, "") ?: "",
            faction = p.getString(KEY_FACTION, "") ?: ""
        )
    }

    fun getPrivateKey(context: Context): PrivateKey {
        val privB64 = prefs(context).getString(KEY_PRIVATE, null)
            ?: error("Личность ещё не создана")
        val spec = PKCS8EncodedKeySpec(Base64.decode(privB64, Base64.NO_WRAP))
        return KeyFactory.getInstance("EC").generatePrivate(spec)
    }

    fun publicKeyFromB64(b64: String): PublicKey {
        val spec = X509EncodedKeySpec(Base64.decode(b64, Base64.NO_WRAP))
        return KeyFactory.getInstance("EC").generatePublic(spec)
    }

    /** Подписать произвольные данные приватным ключом персонажа. */
    fun sign(context: Context, data: ByteArray): String {
        val signature = Signature.getInstance("SHA256withECDSA")
        signature.initSign(getPrivateKey(context))
        signature.update(data)
        return Base64.encodeToString(signature.sign(), Base64.NO_WRAP)
    }

    /** Проверить подпись данных чужим публичным ключом. */
    fun verify(publicKeyB64: String, data: ByteArray, signatureB64: String): Boolean = try {
        val signature = Signature.getInstance("SHA256withECDSA")
        signature.initVerify(publicKeyFromB64(publicKeyB64))
        signature.update(data)
        signature.verify(Base64.decode(signatureB64, Base64.NO_WRAP))
    } catch (e: Exception) {
        false
    }

    private fun generateKeyPair(): KeyPair {
        val generator = KeyPairGenerator.getInstance("EC")
        generator.initialize(ECGenParameterSpec("secp256r1"))
        return generator.generateKeyPair()
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
