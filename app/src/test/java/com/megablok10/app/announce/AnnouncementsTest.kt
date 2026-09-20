package com.megablok10.app.announce

import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

class AnnouncementsTest {
    private fun a(id: String, read: Boolean = false) = Announcement(id, "текст $id", 1L, read)

    @Test
    fun `новое объявление встаёт в начало`() {
        val list = Announcements.addIfAbsent(listOf(a("1")), a("2"))
        assertEquals(listOf("2", "1"), list.map { it.id })
    }

    @Test
    fun `повторная доставка того же id не создаёт дубль и возвращает тот же список`() {
        val list = listOf(a("1"))
        assertSame(list, Announcements.addIfAbsent(list, a("1")))
    }

    @Test
    fun `хранится не больше max, старые отбрасываются`() {
        var list = emptyList<Announcement>()
        for (i in 1..5) list = Announcements.addIfAbsent(list, a("$i"), max = 3)
        assertEquals(listOf("5", "4", "3"), list.map { it.id })
    }

    @Test
    fun `markAllRead помечает всё и не меняет уже прочитанный список`() {
        val marked = Announcements.markAllRead(listOf(a("1"), a("2", read = true)))
        assertEquals(listOf(true, true), marked.map { it.read })
        assertSame(marked, Announcements.markAllRead(marked))
    }

    @Test
    fun `unread отдаёт только непрочитанные`() {
        assertEquals(listOf("1"), Announcements.unread(listOf(a("1"), a("2", read = true))).map { it.id })
    }
}
