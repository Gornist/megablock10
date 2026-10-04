package com.megablok10.app.ui.theme

import java.util.Calendar
import org.junit.Assert.assertEquals
import org.junit.Test

/** Заголовки дней и короткий ключ: формат один для чата, кошелька и профиля. */
class MbFormatTest {
    private fun day(year: Int, month: Int, dayOfMonth: Int): Calendar = Calendar.getInstance().apply { clear(); set(year, month, dayOfMonth, 12, 0) }

    private val today = day(2026, Calendar.OCTOBER, 5)

    @Test fun todayAndYesterdayAreWords() {
        assertEquals("Сегодня", dayLabel(day(2026, Calendar.OCTOBER, 5), today))
        assertEquals("Вчера", dayLabel(day(2026, Calendar.OCTOBER, 4), today))
    }

    @Test fun olderDayIsDateInRussian() {
        assertEquals("3 октября", dayLabel(day(2026, Calendar.OCTOBER, 3), today))
        assertEquals("1 января", dayLabel(day(2026, Calendar.JANUARY, 1), today))
    }

    @Test fun sameDayOfYearInAnotherYearIsNotToday() {
        assertEquals("5 октября", dayLabel(day(2025, Calendar.OCTOBER, 5), today))
        assertEquals("4 октября", dayLabel(day(2025, Calendar.OCTOBER, 4), today))
    }

    @Test fun shortKeyKeepsKeysUpToThresholdWhole() {
        assertEquals("ABCDEFGH", shortKey("ABCDEFGH", 8))
        assertEquals("ABCDEFGHI", shortKey("ABCDEFGHI", 9))
    }

    @Test fun shortKeyCutsLongerKeysToFirstFourAndLastThree() {
        assertEquals("ABCD…GHI", shortKey("ABCDEFGHI", 8))
        assertEquals("ABCD…IJK", shortKey("ABCDEFGHIJK", 9))
    }
}
