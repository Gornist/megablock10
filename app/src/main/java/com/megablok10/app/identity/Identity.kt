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
private const val KEY_RAM = "ram_capacity"
private const val KEY_NEXT_SEQ = "next_change_seq"

/** Стартовая и максимальная ёмкость буфера взлома (см. ревизию v9 §2 — раньше это была глобальная константа MockBreach.ramCapacity). */
const val RAM_CAPACITY_DEFAULT = 6
const val RAM_CAPACITY_MAX = 13

data class Identity(
    val publicKeyB64: String,
    val callsign: String,
    val faction: String,
    val ramCapacity: Int = RAM_CAPACITY_DEFAULT
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
                faction = p.getString(KEY_FACTION, faction) ?: faction,
                ramCapacity = p.getInt(KEY_RAM, RAM_CAPACITY_DEFAULT)
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

    /** Необратимо стирает личность этого устройства (ключи, позывной, фракция). */
    fun clear(context: Context) {
        prefs(context).edit().clear().apply()
    }

    fun current(context: Context): Identity? {
        val p = prefs(context)
        val pub = p.getString(KEY_PUBLIC, null) ?: return null
        return Identity(
            publicKeyB64 = pub,
            callsign = p.getString(KEY_CALLSIGN, "") ?: "",
            faction = p.getString(KEY_FACTION, "") ?: "",
            ramCapacity = p.getInt(KEY_RAM, RAM_CAPACITY_DEFAULT)
        )
    }

    /** +delta к ёмкости буфера, зажато потолком — даже если QR сфотографируют и применят несколько раз с разных устройств, выше потолка на этом устройстве не прыгнуть. Дедупликация самого токена — на вызывающей стороне (RamUpgradeStore), не здесь. */
    fun applyRamUpgrade(context: Context, delta: Int): Int {
        val p = prefs(context)
        val next = (p.getInt(KEY_RAM, RAM_CAPACITY_DEFAULT) + delta).coerceIn(RAM_CAPACITY_DEFAULT, RAM_CAPACITY_MAX)
        p.edit().putInt(KEY_RAM, next).apply()
        return next
    }

    /**
     * Применяет правку мастера с дашборда (§6.3 ТЗ) — в отличие от
     * applyRamUpgrade/getOrCreate, НЕ эмитит новый ChangeRecord обратно на
     * коллектор: этот вызов сам следствие уже существующей записи в его
     * истории (MASTER_OVERRIDE), эхо было бы бессмысленным дублем. Значение
     * абсолютное (не дельта), поэтому применить пришедшую правку дважды
     * (переотправка при повторном опросе) безопасно само по себе.
     */
    fun applyRamOverride(context: Context, newValue: Int) {
        prefs(context).edit().putInt(KEY_RAM, newValue.coerceIn(RAM_CAPACITY_DEFAULT, RAM_CAPACITY_MAX)).apply()
    }

    /** См. applyRamOverride — тот же принцип, для позывного. */
    fun applyCallsignOverride(context: Context, newValue: String) {
        prefs(context).edit().putString(KEY_CALLSIGN, newValue).apply()
    }

    /** См. applyRamOverride — тот же принцип, для фракции. */
    fun applyFactionOverride(context: Context, newValue: String) {
        prefs(context).edit().putString(KEY_FACTION, newValue).apply()
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

    /**
     * Следующий номер seq для ChangeRecord к мастерскому коллектору (§2.2/
     * §3.4 ТЗ) — сквозной счётчик на устройстве, растёт монотонно и не
     * зависит от локальной очереди отправки: если очередь целиком
     * подтвердится и опустеет, следующий вызов не должен начать нумерацию
     * заново. Здесь же, а не в очереди — тот же SharedPreferences, что и
     * остальное состояние личности.
     */
    // @Synchronized: read-modify-write по SharedPreferences, а enqueue зовут параллельные корутины —
    // без блокировки два вызова получали один seq, и коллектор отбраковывал вторую запись.
    @Synchronized
    fun nextChangeSeq(context: Context): Long {
        val p = prefs(context)
        val next = p.getLong(KEY_NEXT_SEQ, 0L) + 1
        p.edit().putLong(KEY_NEXT_SEQ, next).apply()
        return next
    }

    private fun generateKeyPair(): KeyPair {
        val generator = KeyPairGenerator.getInstance("EC")
        generator.initialize(ECGenParameterSpec("secp256r1"))
        return generator.generateKeyPair()
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
