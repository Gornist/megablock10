package com.megablok10.app.netrun

import android.content.SharedPreferences
import com.megablok10.app.qr.Mb10Qr

/** Запрос входа, ждущий ответа Моста, вместе со стойкой на момент запроса (последний скан другой стойки его не меняет): переживает перезапуск процесса, пока не пришёл подписанный `MB10ENTERED` или игрок не закрыл. */
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
        val rack = Mb10Qr.Rack(
            terminal = prefs.getString(A_TERMINAL, "").orEmpty(),
            host = prefs.getString(A_HOST, null) ?: return null,
            port = prefs.getInt(A_PORT, 0).takeIf { it > 0 } ?: return null,
            worldPub = prefs.getString(A_WORLD, null) ?: return null,
            label = prefs.getString(A_LABEL, "").orEmpty(),
        )
        val request = EnterRequest(
            rid = rid,
            terminal = prefs.getString(A_TERMINAL, "").orEmpty(),
            runner = prefs.getString(A_RUNNER, "").orEmpty(),
            callsign = prefs.getString(A_CALLSIGN, "").orEmpty(),
            transfers = prefs.getString(A_TRANSFERS, "").orEmpty().split(",").filter { it.isNotEmpty() },
            protectedTransfer = prefs.getString(A_PROTECTED, "").orEmpty(),
            timestamp = prefs.getLong(A_TS, 0),
            signature = prefs.getString(A_SIG, "").orEmpty(),
            // нет поля — запрос начат до обновления: повторяется строкой v1 с прежней подписью
            ram = if (prefs.contains(A_RAM)) prefs.getInt(A_RAM, 0) else null,
        )
        return EnterAttempt(request, rack)
    }

    fun saveAttempt(request: EnterRequest, rack: Mb10Qr.Rack) {
        prefs.edit().putString(A_HOST, rack.host).putInt(A_PORT, rack.port).putString(A_WORLD, rack.worldPub).putString(A_LABEL, rack.label).putString(RID, request.rid).putString(A_TERMINAL, request.terminal).putString(A_RUNNER, request.runner)
            .putString(A_CALLSIGN, request.callsign).putString(A_TRANSFERS, request.transfers.joinToString(","))
            .putString(A_PROTECTED, request.protectedTransfer).putLong(A_TS, request.timestamp).putString(A_SIG, request.signature)
            .apply { request.ram?.let { putInt(A_RAM, it) } ?: remove(A_RAM) }.commit()
    }

    fun clearAttempt() {
        prefs.edit().remove(RID).remove(A_TERMINAL).remove(A_RUNNER).remove(A_CALLSIGN).remove(A_TRANSFERS).remove(A_PROTECTED)
            .remove(A_TS).remove(A_SIG).remove(A_RAM).remove(A_HOST).remove(A_PORT).remove(A_WORLD).remove(A_LABEL).commit()
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
        private const val A_RAM = "attempt_ram"
        private const val A_HOST = "attempt_host"
        private const val A_PORT = "attempt_port"
        private const val A_WORLD = "attempt_world"
        private const val A_LABEL = "attempt_label"
    }
}
