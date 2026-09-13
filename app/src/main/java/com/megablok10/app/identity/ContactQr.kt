package com.megablok10.app.identity

import android.content.Context

/**
 * QR-код контакта кодирует публичный ключ + позывной + фракцию текстом,
 * без обращения к сети — сканирующее устройство всё разбирает локально.
 * Тот же принцип позже используется для Container (демоны/шарды/евродоллары)
 * и для риппердок-имплантов — просто другой префикс вместо CONTACT.
 */
object ContactQr {

    data class ScannedContact(
        val publicKeyB64: String,
        val callsign: String,
        val faction: String
    )

    fun encode(identity: Identity): String =
        "MB10:CONTACT:v1:${identity.publicKeyB64}:${identity.callsign}:${identity.faction}"

    fun decode(raw: String): ScannedContact? {
        val parts = raw.split(":")
        if (parts.size < 6 || parts[0] != "MB10" || parts[1] != "CONTACT") return null
        return ScannedContact(
            publicKeyB64 = parts[3],
            callsign = parts[4],
            faction = parts[5]
        )
    }
}

/** Плоское локальное хранилище отсканированных контактов (заглушка до Room). */
object ContactStore {
    private const val PREFS = "contacts_prefs"
    private const val KEY_SET = "contacts"

    fun all(context: Context): List<ContactQr.ScannedContact> {
        val raw = prefs(context).getStringSet(KEY_SET, emptySet()) ?: emptySet()
        return raw.mapNotNull { entry ->
            val p = entry.split("|")
            if (p.size == 3) ContactQr.ScannedContact(p[0], p[1], p[2]) else null
        }
    }

    fun add(context: Context, contact: ContactQr.ScannedContact) {
        val current = prefs(context).getStringSet(KEY_SET, emptySet())?.toMutableSet()
            ?: mutableSetOf()
        current.add("${contact.publicKeyB64}|${contact.callsign}|${contact.faction}")
        prefs(context).edit().putStringSet(KEY_SET, current).apply()
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
