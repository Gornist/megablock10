package com.megablok10.app.qr

import com.megablok10.app.collector.ChangeField
import com.megablok10.app.data.ConsumedTokenEntity
import com.megablok10.app.testing.RoomTest
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Выдача персонажа по QR и RAM-апгрейд переживают смерть процесса посередине: при запуске (или повторном скане) доделываются,
 * без дублей записей и без потери QR. Раньше код выдачи становился «уже использован» при несозданном персонаже, а RAM-токен —
 * списанным без прибавки RAM.
 */
@RunWith(RobolectricTestRunner::class)
class InterruptedIssueTest : RoomTest() {
    private val provision = Mb10Qr.Provision("P-7", "http://10.0.0.1:8080", "код-игры", "V", "Малстром", startBalance = 300, ramCapacity = 8)

    private fun noCharacterYet() = identity.clear()

    @Test fun provisionInterruptedBeforeTheCharacterExistsIsFinishedAtStartup() = runBlocking {
        noCharacterYet()
        settings.beginProvision(provision.id, Mb10QrCodec.encodeProvision(provision))   // процесс умер сразу после отметки «в процессе»

        restart()
        assertTrue(provisioning.resumeInterrupted() is ProvisionResult.Applied)

        assertEquals("V", identity.current?.callsign)
        assertEquals(8, identity.current?.ramCapacity)
        assertEquals(300L, balance())
        assertEquals(listOf(ChangeField.CALLSIGN, ChangeField.FACTION, ChangeField.RAM_CAPACITY, ChangeField.BALANCE), records().map { it.field })
        assertEquals("http://10.0.0.1:8080", settings.baseUrl())
        assertNull(settings.provisionInProgress())
        assertNull("доделанную выдачу второй раз не доделывают", provisioning.resumeInterrupted())
    }

    @Test fun crashWhileRecordingIsResumedWithoutDuplicates() = runBlocking {
        noCharacterYet()
        failOnSign = 2   // запись позывного прошла, запись фракции — нет: транзакция записей и баланса откатывается целиком
        assertTrue(runCatching { provisioning.apply(provision) }.isFailure)
        assertEquals("V", identity.current?.callsign)
        assertTrue(records().isEmpty())
        assertEquals(0L, balance())

        restart()
        provisioning.resumeInterrupted()
        provisioning.resumeInterrupted()
        assertEquals(listOf(ChangeField.CALLSIGN, ChangeField.FACTION, ChangeField.RAM_CAPACITY, ChangeField.BALANCE), records().map { it.field })
        assertEquals(300L, balance())
    }

    @Test fun sameQrScannedAgainFinishesInsteadOfSayingAlreadyUsed() = runBlocking {
        noCharacterYet()
        failOnSign = 1
        assertTrue(runCatching { provisioning.apply(provision) }.isFailure)

        restart()
        assertTrue(provisioning.apply(provision) is ProvisionResult.Applied)
        assertEquals(300L, balance())
        assertTrue("а после выдачи — уже нельзя", provisioning.apply(provision) is ProvisionResult.AlreadyHasIdentity)
    }

    @Test fun ramUpgradeInterruptedAfterTheTokenWasConsumedIsFinishedAtStartup() = runBlocking {
        identity.beginRamUpgrade("ram-1", 8)
        db.consumedTokenDao().insertIfAbsent(ConsumedTokenEntity("ram-1", 1))   // токен списан, а ёмкость поставить не успели

        restart()
        ramUpgrades.resumeInterrupted()
        assertEquals(8, identity.current?.ramCapacity)
        assertNull(identity.pendingRamUpgrade())
    }

    @Test fun ramUpgradeInterruptedBeforeTheTokenWasConsumedLeavesTheQrUsable() = runBlocking {
        failOnSign = 1
        assertTrue(runCatching { ramUpgrades.apply(Mb10Qr.RamUpgrade("ram-1", 2)) }.isFailure)
        assertEquals(6, identity.current?.ramCapacity)

        restart()
        ramUpgrades.resumeInterrupted()
        assertNull(identity.pendingRamUpgrade())
        assertEquals(6, identity.current?.ramCapacity)
        assertEquals("QR не сгорел — срабатывает снова", 8, ramUpgrades.apply(Mb10Qr.RamUpgrade("ram-1", 2)))
        assertNull("и только один раз", ramUpgrades.apply(Mb10Qr.RamUpgrade("ram-1", 2)))
        assertEquals(listOf("6" to "8"), records().filter { it.field == ChangeField.RAM_CAPACITY }.map { it.oldValue to it.newValue })
    }
}
