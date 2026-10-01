package com.megablok10.app.netrun

import android.content.SharedPreferences
import com.megablok10.app.qr.Mb10Qr

/** Запрос входа, ждущий ответа Моста: переживает перезапуск процесса, пока не пришёл подписанный `MB10ENTERED` или игрок не закрыл. */
data class EnterAttempt(val request: EnterRequest, val rack: Mb10Qr.Rack)

/**
 * Что телефон помнит о «Сети»: последняя отсканированная стойка (из неё — ключ мира, от которого принимается добыча без «Принять», и
 * адрес Моста) и запрос входа без ответа. Файл `netrun_prefs`; пишется синхронно (`commit`): по возврату уходят карточки и запрос.
 */
class NetrunStore(private val prefs: SharedPreferences) {
    /** Стойка последнего скана или null. */
    fun rack(): Mb10Qr.Rack? {
        val pub = prefs.getString(WORLD_PUB, null) ?: return null
        val host = prefs.getString(HOST, null) ?: return null
        val port = prefs.getInt(PORT, 0).takeIf { it > 0 } ?: return null
        return Mb10Qr.Rack(prefs.getString(TERMINAL, "").orEmpty(), host, port, pub, prefs.getString(LABEL, "").orEmpty())
    }

    /** Ключ мира для приёма добычи: только он, и только пока игрок хоть раз сканировал стойку. */
    fun worldPub(): String? = prefs.getString(WORLD_PUB, null)

    fun saveRack(rack: Mb10Qr.Rack) {
        prefs.edit().putString(WORLD_PUB, rack.worldPub).putString(HOST, rack.host).putInt(PORT, rack.port)
            .putString(TERMINAL, rack.terminal).putString(LABEL, rack.label).commit()
    }

    fun attempt(): EnterAttempt? {
        val rid = prefs.getString(RID, null) ?: return null
        val rack = rack() ?: return null
        val request = EnterRequest(
            rid = rid,
            terminal = prefs.getString(A_TERMINAL, "").orEmpty(),
            runner = prefs.getString(A_RUNNER, "").orEmpty(),
            callsign = prefs.getString(A_CALLSIGN, "").orEmpty(),
            transfers = prefs.getString(A_TRANSFERS, "").orEmpty().split(",").filter { it.isNotEmpty() },
            protectedTransfer = prefs.getString(A_PROTECTED, "").orEmpty(),
            timestamp = prefs.getLong(A_TS, 0),
            signature = prefs.getString(A_SIG, "").orEmpty(),
        )
        return EnterAttempt(request, rack)
    }

    fun saveAttempt(request: EnterRequest) {
        prefs.edit().putString(RID, request.rid).putString(A_TERMINAL, request.terminal).putString(A_RUNNER, request.runner)
            .putString(A_CALLSIGN, request.callsign).putString(A_TRANSFERS, request.transfers.joinToString(","))
            .putString(A_PROTECTED, request.protectedTransfer).putLong(A_TS, request.timestamp).putString(A_SIG, request.signature).commit()
    }

    fun clearAttempt() {
        prefs.edit().remove(RID).remove(A_TERMINAL).remove(A_RUNNER).remove(A_CALLSIGN).remove(A_TRANSFERS).remove(A_PROTECTED)
            .remove(A_TS).remove(A_SIG).commit()
    }

    /** Сброс сессии персонажа: стойка, ключ мира и запрос входа прежнего игрока не нужны новому. */
    fun clearAll() {
        prefs.edit().clear().commit()
    }

    companion object {
        const val PREFS = "netrun_prefs"
        private const val WORLD_PUB = "world_pub"
        private const val HOST = "world_host"
        private const val PORT = "world_port"
        private const val TERMINAL = "terminal"
        private const val LABEL = "label"
        private const val RID = "attempt_rid"
        private const val A_TERMINAL = "attempt_terminal"
        private const val A_RUNNER = "attempt_runner"
        private const val A_CALLSIGN = "attempt_callsign"
        private const val A_TRANSFERS = "attempt_transfers"
        private const val A_PROTECTED = "attempt_protected"
        private const val A_TS = "attempt_ts"
        private const val A_SIG = "attempt_sig"
    }
}
