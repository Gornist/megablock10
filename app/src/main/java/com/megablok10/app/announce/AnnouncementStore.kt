package com.megablok10.app.announce

import android.content.SharedPreferences
import com.megablok10.app.log.Mb10Log
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.json.JSONArray
import org.json.JSONObject

private const val KEY_LIST = "list"

/**
 * Объявления мастера с дашборда: приходят обычной мастерской записью
 * (field=announcement) через тот же опрос коллектора, что и правки. Хранятся
 * в SharedPreferences (последние [Announcements.MAX_KEPT]) — пара десятков
 * коротких строк, отдельная таблица Room ради них не стоит миграции базы
 * (та у нас пересоздаётся целиком, fallbackToDestructiveMigration). Файл настроек — `announcements` ([PREFS]; стенд e2e
 * читает shared_prefs/announcements.xml напрямую), [prefs] передаёт корень композиции.
 */
class AnnouncementStore(private val prefs: SharedPreferences) {
    private val _items = MutableStateFlow<List<Announcement>>(emptyList())
    val items: StateFlow<List<Announcement>> = _items
    @Volatile private var loaded = false

    fun load() {
        if (loaded) return
        synchronized(this) {
            if (loaded) return
            _items.value = read()
            loaded = true
        }
    }

    /** true — объявление новое (стоит показать/уведомить); false — такой id уже был. */
    fun add(id: String, text: String, now: Long = System.currentTimeMillis()): Boolean {
        Mb10Log.event("Announce", "announcement.add", "id" to id, "chars" to text.length)
        load()
        synchronized(this) {
            val before = _items.value
            val after = Announcements.addIfAbsent(before, Announcement(id, text, now))
            if (after === before) return false
            _items.value = after
            // Синхронно: объявление пришло правкой мастера, и сразу после этого серверу уходит подтверждение (см. MasterChangeHooks).
            // Не записалось — откатываем и в памяти: объявления нет, подтверждать нечего, сервер пришлёт его снова.
            if (!write(after, durable = true)) { _items.value = before; return false }
            return true
        }
    }

    /** Объявление [id] уже сохранено на телефоне. */
    fun contains(id: String): Boolean {
        load()
        return _items.value.any { it.id == id }
    }

    /** Полный сброс сессии на устройстве (identity/SessionReset): объявления мастера прежнего персонажа новому не нужны. */
    fun clear() {
        synchronized(this) {
            _items.value = emptyList()
            loaded = true
            prefs.edit().remove(KEY_LIST).apply()
        }
    }

    fun markAllRead() {
        load()
        synchronized(this) {
            val after = Announcements.markAllRead(_items.value)
            if (after === _items.value) return
            _items.value = after
            write(after)
        }
    }

    private fun read(): List<Announcement> {
        val raw = prefs.getString(KEY_LIST, null) ?: return emptyList()
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

    /** [durable] — дождаться записи на диск (commit); false — записать не удалось. Иначе — в фоне (apply), результат всегда true. */
    private fun write(list: List<Announcement>, durable: Boolean = false): Boolean {
        val arr = JSONArray(list.map { JSONObject().put("id", it.id).put("text", it.text).put("at", it.receivedAt).put("read", it.read) })
        val edit = prefs.edit().putString(KEY_LIST, arr.toString())
        return if (durable) edit.commit() else { edit.apply(); true }
    }

    companion object {
        const val PREFS = "announcements"
    }
}
