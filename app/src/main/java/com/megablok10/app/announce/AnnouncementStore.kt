package com.megablok10.app.announce

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.json.JSONArray
import org.json.JSONObject

private const val PREFS = "announcements"
private const val KEY_LIST = "list"

/**
 * Объявления мастера с дашборда: приходят обычной мастерской записью
 * (field=announcement) через тот же опрос коллектора, что и правки. Хранятся
 * в SharedPreferences (последние [Announcements.MAX_KEPT]) — пара десятков
 * коротких строк, отдельная таблица Room ради них не стоит миграции базы
 * (та у нас пересоздаётся целиком, fallbackToDestructiveMigration).
 */
object AnnouncementStore {
    private val _items = MutableStateFlow<List<Announcement>>(emptyList())
    val items: StateFlow<List<Announcement>> = _items
    @Volatile private var loaded = false

    fun load(context: Context) {
        if (loaded) return
        synchronized(this) {
            if (loaded) return
            _items.value = read(context)
            loaded = true
        }
    }

    /** true — объявление новое (стоит показать/уведомить); false — такой id уже был. */
    fun add(context: Context, id: String, text: String, now: Long = System.currentTimeMillis()): Boolean {
        load(context)
        synchronized(this) {
            val before = _items.value
            val after = Announcements.addIfAbsent(before, Announcement(id, text, now))
            if (after === before) return false
            _items.value = after
            write(context, after)
            return true
        }
    }

    /** Полный сброс сессии на устройстве (identity/SessionReset): объявления мастера прежнего персонажа новому не нужны. */
    fun clear(context: Context) {
        synchronized(this) {
            _items.value = emptyList()
            loaded = true
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(KEY_LIST).apply()
        }
    }

    fun markAllRead(context: Context) {
        load(context)
        synchronized(this) {
            val after = Announcements.markAllRead(_items.value)
            if (after === _items.value) return
            _items.value = after
            write(context, after)
        }
    }

    private fun read(context: Context): List<Announcement> {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_LIST, null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).map {
                val o = arr.getJSONObject(it)
                Announcement(o.getString("id"), o.getString("text"), o.getLong("at"), o.optBoolean("read", false))
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    private fun write(context: Context, list: List<Announcement>) {
        val arr = JSONArray(list.map { JSONObject().put("id", it.id).put("text", it.text).put("at", it.receivedAt).put("read", it.read) })
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY_LIST, arr.toString()).apply()
    }
}
