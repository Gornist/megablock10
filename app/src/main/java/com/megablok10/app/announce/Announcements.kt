package com.megablok10.app.announce

/** Объявление мастера, дошедшее до этого устройства. id — id мастерской записи на сервере: повторная доставка того же объявления (потерянный ack) не создаёт дубля. */
data class Announcement(val id: String, val text: String, val receivedAt: Long, val read: Boolean = false)

/** Чистая логика списка объявлений (без Android) — отдельно от хранилища, чтобы её можно было проверить обычным юнит-тестом. */
object Announcements {
    const val MAX_KEPT = 30

    /** Новое — в начало; уже известный id возвращает тот же список без изменений (по ссылке); старше MAX_KEPT — отбрасываются. */
    fun addIfAbsent(list: List<Announcement>, item: Announcement, max: Int = MAX_KEPT): List<Announcement> {
        if (list.any { it.id == item.id }) return list
        return (listOf(item) + list).take(max)
    }

    fun markAllRead(list: List<Announcement>): List<Announcement> =
        if (list.none { !it.read }) list else list.map { it.copy(read = true) }

    fun unread(list: List<Announcement>): List<Announcement> = list.filter { !it.read }
}
