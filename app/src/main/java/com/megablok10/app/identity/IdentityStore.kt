package com.megablok10.app.identity

import android.content.SharedPreferences
import com.megablok10.kit.crypto.Ecdsa
import com.megablok10.kit.sync.RecordSigner
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

// Имена ключей — те же, что были у IdentityManager: по ним лежат данные на телефонах игроков, а стенд e2e читает
// shared_prefs/identity_prefs.xml напрямую (scripts/e2e/scenarios/zz-provisioning.sh).
private const val KEY_PRIVATE = "private_key"
private const val KEY_PUBLIC = "public_key"
private const val KEY_CALLSIGN = "callsign"
private const val KEY_FACTION = "faction"
private const val KEY_RAM = "ram_capacity"
private const val KEY_NEXT_SEQ = "next_change_seq"

/**
 * Личность персонажа на этом устройстве: пара ключей ECDSA (secp256r1, см. kit Ecdsa), сгенерированная один раз, позывной,
 * фракция и ёмкость буфера взлома. Хранится в SharedPreferences `identity_prefs` ([prefs] передаёт корень композиции).
 * Приватный ключ — в base64 в тех же настройках: для уровня угроз живой игры (не банк) этого достаточно; перенос в Android
 * Keystore можно сделать позже без изменения остального протокола.
 *
 * Реактивно: [state] меняется при создании, сбросе и правках мастера, поэтому экраны видят новый позывной, фракцию или RAM
 * сразу, а не после перезапуска приложения. Все изменения — только через этот класс.
 */
class IdentityStore(private val prefs: SharedPreferences) {
    private val _state = MutableStateFlow(read())
    val state: StateFlow<Identity?> = _state.asStateFlow()

    /** Личность сейчас; null — персонаж на устройстве ещё не создан (или сброшен). */
    val current: Identity? get() = _state.value

    fun hasIdentity(): Boolean = prefs.contains(KEY_PUBLIC)

    /** Уже есть личность — возвращает её как есть (параметры не применяются); нет — генерирует ключи и создаёт. */
    @Synchronized
    fun getOrCreate(callsign: String, faction: String): Identity {
        val existingPub = prefs.getString(KEY_PUBLIC, null)
        if (existingPub != null) {
            return Identity(
                publicKeyB64 = existingPub,
                callsign = prefs.getString(KEY_CALLSIGN, callsign) ?: callsign,
                faction = prefs.getString(KEY_FACTION, faction) ?: faction,
                ramCapacity = prefs.getInt(KEY_RAM, RAM_CAPACITY_DEFAULT)
            )
        }
        val keyPair = Ecdsa.generateKeyPair()
        val pubB64 = Ecdsa.encodeKey(keyPair.public)
        prefs.edit()
            .putString(KEY_PUBLIC, pubB64)
            .putString(KEY_PRIVATE, Ecdsa.encodeKey(keyPair.private))
            .putString(KEY_CALLSIGN, callsign)
            .putString(KEY_FACTION, faction)
            .apply()
        publish()
        return Identity(pubB64, callsign, faction)
    }

    /** Необратимо стирает личность этого устройства (ключи, позывной, фракция, счётчик записей). */
    @Synchronized
    fun clear() {
        prefs.edit().clear().apply()
        publish()
    }

    /** +delta к ёмкости буфера, зажато потолком — даже если QR сфотографируют и применят несколько раз с разных устройств, выше потолка на этом устройстве не прыгнуть. Дедупликация самого токена — на вызывающей стороне (RamUpgradeStore), не здесь. */
    @Synchronized
    fun applyRamUpgrade(delta: Int): Int {
        val next = (prefs.getInt(KEY_RAM, RAM_CAPACITY_DEFAULT) + delta).coerceIn(RAM_CAPACITY_DEFAULT, RAM_CAPACITY_MAX)
        prefs.edit().putInt(KEY_RAM, next).apply()
        publish()
        return next
    }

    /**
     * Применяет правку мастера с дашборда (§6.3 ТЗ) — в отличие от applyRamUpgrade/getOrCreate, НЕ эмитит новую запись обратно
     * на коллектор: этот вызов сам следствие уже существующей записи в его истории (MASTER_OVERRIDE), эхо было бы бессмысленным
     * дублем. Значение абсолютное (не дельта), поэтому применить пришедшую правку дважды (переотправка при повторном опросе)
     * безопасно само по себе.
     */
    @Synchronized
    fun applyRamOverride(newValue: Int) {
        prefs.edit().putInt(KEY_RAM, newValue.coerceIn(RAM_CAPACITY_DEFAULT, RAM_CAPACITY_MAX)).apply()
        publish()
    }

    /** См. applyRamOverride — тот же принцип, для позывного. */
    @Synchronized
    fun applyCallsignOverride(newValue: String) {
        prefs.edit().putString(KEY_CALLSIGN, newValue).apply()
        publish()
    }

    /** См. applyRamOverride — тот же принцип, для фракции. */
    @Synchronized
    fun applyFactionOverride(newValue: String) {
        prefs.edit().putString(KEY_FACTION, newValue).apply()
        publish()
    }

    /** Подписать произвольные данные приватным ключом персонажа (ECDSA P-256). Без личности — IllegalStateException. */
    fun sign(data: ByteArray): String {
        val privB64 = prefs.getString(KEY_PRIVATE, null) ?: error("Личность ещё не создана")
        return Ecdsa.sign(Ecdsa.decodePrivateKey(privB64), data)
    }

    /**
     * Следующий номер seq для записи мастерскому коллектору (§2.2/§3.4 ТЗ) — сквозной счётчик на устройстве, растёт монотонно
     * и не зависит от локальной очереди отправки: если очередь целиком подтвердится и опустеет, следующий вызов не должен
     * начать нумерацию заново. Synchronized: read-modify-write по SharedPreferences, а записи создают параллельные корутины —
     * без блокировки два вызова получали один seq, и коллектор отбраковывал вторую запись.
     */
    @Synchronized
    fun nextChangeSeq(): Long {
        val next = prefs.getLong(KEY_NEXT_SEQ, 0L) + 1
        prefs.edit().putLong(KEY_NEXT_SEQ, next).apply()
        return next
    }

    /** Подписант записей для мастерского коллектора (kit ChangeRecorder); null — личности нет, записывать нечем. */
    fun recordSigner(): RecordSigner? {
        val identity = current ?: return null
        return object : RecordSigner {
            override val publicKeyB64: String = identity.publicKeyB64
            override fun nextSeq(): Long = nextChangeSeq()
            override fun sign(data: ByteArray): String = this@IdentityStore.sign(data)
        }
    }

    private fun read(): Identity? {
        val pub = prefs.getString(KEY_PUBLIC, null) ?: return null
        return Identity(
            publicKeyB64 = pub,
            callsign = prefs.getString(KEY_CALLSIGN, "") ?: "",
            faction = prefs.getString(KEY_FACTION, "") ?: "",
            ramCapacity = prefs.getInt(KEY_RAM, RAM_CAPACITY_DEFAULT)
        )
    }

    private fun publish() { _state.value = read() }

    companion object {
        /** Файл настроек личности — тот же, что был у IdentityManager. */
        const val PREFS = "identity_prefs"
    }
}
