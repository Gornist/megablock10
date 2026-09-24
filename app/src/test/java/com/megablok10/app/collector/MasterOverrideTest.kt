package com.megablok10.app.collector

import com.megablok10.kit.sync.ChangeRecord
import com.megablok10.kit.sync.MasterApply
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Правка мастера, которую нельзя применить, — явный отказ без повтора, а не «пропущена и подтверждена». */
class MasterOverrideTest {
    private fun change(field: String, value: String?, ref: String? = "штраф") =
        ChangeRecord("m1", "me", -1, 0, field, null, value, "MASTER_OVERRIDE", ref, "master", "sig")

    private fun rejected(field: String, value: String?): String {
        val parsed = MasterOverride.parse(change(field, value))
        assertTrue("ждали отказ, а получили $parsed", parsed is MasterOverride.Invalid)
        val failure = (parsed as MasterOverride.Invalid).failure
        assertTrue("такой отказ повторять бессмысленно", failure.permanent)
        return failure.reason
    }

    @Test fun validValuesAreParsed() {
        assertEquals(MasterOverride.Balance(500, "штраф"), MasterOverride.parse(change(ChangeField.BALANCE, "500")))
        assertEquals(MasterOverride.Balance(-20, "без основания"), MasterOverride.parse(change(ChangeField.BALANCE, "-20", ref = null)))
        assertEquals(MasterOverride.Ram(13), MasterOverride.parse(change(ChangeField.RAM_CAPACITY, "13")))
        assertEquals(MasterOverride.Callsign("BLADE"), MasterOverride.parse(change(ChangeField.CALLSIGN, " BLADE ")))
        assertEquals(MasterOverride.Faction("Мальстрём"), MasterOverride.parse(change(ChangeField.FACTION, "Мальстрём")))
        assertEquals(MasterOverride.Announcement("Сбор у бара"), MasterOverride.parse(change(ChangeField.ANNOUNCEMENT, "Сбор у бара")))
    }

    @Test fun malformedNumbersAreNotAppliedSilently() {
        assertTrue(rejected(ChangeField.BALANCE, "сто").contains("не целое число"))
        assertTrue(rejected(ChangeField.BALANCE, "1.5").contains("не целое число"))
        assertTrue(rejected(ChangeField.RAM_CAPACITY, "x").contains("RAM"))
        assertTrue("вне диапазона — тоже отказ, а не тихое зажатие", rejected(ChangeField.RAM_CAPACITY, "99").contains("от 6 до 13"))
    }

    @Test fun emptyAndUnknownAreRejected() {
        assertEquals("правка без значения", rejected(ChangeField.BALANCE, null))
        assertEquals("пустой позывной", rejected(ChangeField.CALLSIGN, "  "))
        assertEquals("пустая фракция", rejected(ChangeField.FACTION, ""))
        assertTrue(rejected("counters.new", "{}").contains("не поддерживается этой версией"))
    }

    @Test fun invalidCarriesAFailureForTheServer() {
        val parsed = MasterOverride.parse(change("x", "1")) as MasterOverride.Invalid
        assertEquals(MasterApply.Failed("поле «x» не поддерживается этой версией приложения", permanent = true), parsed.failure)
    }
}
