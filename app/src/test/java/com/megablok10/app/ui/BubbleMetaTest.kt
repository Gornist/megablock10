package com.megablok10.app.ui

import androidx.compose.ui.graphics.Color
import com.megablok10.app.data.MessageStatus
import com.megablok10.app.ui.screens.statusMark
import com.megablok10.app.ui.theme.MbReadBlue
import com.megablok10.app.ui.theme.bubbleMeta
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Отметка у своего сообщения: «прочитано» и «прослушано» синие ✓✓, «доставлено» и остальные — обычным цветом метки (раньше флаг «синяя» нигде не использовался). */
class BubbleMetaTest {
    private val base = Color(0xFFA9E8C3)

    private fun markColor(status: Int): Color? {
        val meta = bubbleMeta("12:34", statusMark(status), base)
        return meta.spanStyles.singleOrNull()?.item?.color
    }

    @Test fun listenedAndReadAreBlue() {
        assertEquals(MbReadBlue, markColor(MessageStatus.LISTENED))
        assertEquals(MbReadBlue, markColor(MessageStatus.READ))
    }

    @Test fun deliveredSentAndPendingStayInTheMetaColor() {
        listOf(MessageStatus.DELIVERED, MessageStatus.SENT, MessageStatus.PENDING).forEach { assertEquals(base, markColor(it)) }
    }

    @Test fun textIsTimeThenSpaceThenMark() {
        assertEquals("12:34 ✓✓", bubbleMeta("12:34", statusMark(MessageStatus.LISTENED), base).text)
        assertEquals("12:34 ✓", bubbleMeta("12:34", statusMark(MessageStatus.SENT), base).text)
    }

    @Test fun noMarkMeansPlainTimeWithoutSpans() {
        val meta = bubbleMeta("12:34", statusMark(MessageStatus.NONE), base)
        assertEquals("12:34", meta.text)
        assertTrue(meta.spanStyles.isEmpty())
        assertNull(statusMark(MessageStatus.NONE))
    }
}
