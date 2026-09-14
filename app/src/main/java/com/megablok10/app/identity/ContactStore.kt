package com.megablok10.app.identity

import android.content.Context
import com.megablok10.app.qr.Mb10Qr

/** Плоское локальное хранилище отсканированных контактов (заглушка до Room). */
object ContactStore {
    private const val PREFS = "contacts_prefs"
    private const val KEY_SET = "contacts"

    fun all(context: Context): List<Mb10Qr.Contact> {
        val raw = prefs(context).getStringSet(KEY_SET, emptySet()) ?: emptySet()
        return raw.mapNotNull { entry ->
            val p = entry.split("|")
            if (p.size == 3) Mb10Qr.Contact(p[0], p[1], p[2]) else null
        }
    }

    fun add(context: Context, contact: Mb10Qr.Contact) {
        val current = prefs(context).getStringSet(KEY_SET, emptySet())?.toMutableSet()
            ?: mutableSetOf()
        current.add("${contact.publicKeyB64}|${contact.callsign}|${contact.faction}")
        prefs(context).edit().putStringSet(KEY_SET, current).apply()
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
