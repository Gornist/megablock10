package com.megablok10.app.cyberdeck

import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.testing.FakeShardCollection
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test

class ScanObjectTest {
    private val shard = Mb10Qr.Shard(id = "s1", decryptAction = false, tier = 1, valueHint = "низкий", title = "Обрывок", meta = "", body = "")
    private val ramUpgrade = Mb10Qr.RamUpgrade(token = "tok-1", delta = 2)

    @Test fun scannedShardIsAddedToTheCollectionAndSwitchesToTheShardsSegment() = runTest {
        val shards = FakeShardCollection()
        val scan = ScanObject(shards, applyRamUpgrade = { null })

        val effects = scan(shard)

        assertEquals(listOf(shard), shards.items.value)
        assertEquals(listOf(ScanEffect.Collected(CollectedKind.Shard)), effects)
    }

    @Test fun ramUpgradeAppliedShowsTheNewCapacity() = runTest {
        val scan = ScanObject(FakeShardCollection(), applyRamUpgrade = { 8 })

        val effects = scan(ramUpgrade)

        assertEquals(listOf(ScanEffect.Notice("RAM деки увеличена до 8")), effects)
    }

    @Test fun alreadyConsumedRamTokenIsExplainedInsteadOfSilentlyDoingNothing() = runTest {
        val scan = ScanObject(FakeShardCollection(), applyRamUpgrade = { null })

        val effects = scan(ramUpgrade)

        assertEquals(listOf(ScanEffect.Notice("Этот RAM-токен уже был применён")), effects)
    }

    @Test fun unrecognizedQrIsExplainedToThePlayer() = runTest {
        val scan = ScanObject(FakeShardCollection(), applyRamUpgrade = { null })

        val effects = scan(Mb10Qr.Contact("pk", "Гость", "Нейтралы"))

        assertEquals(listOf(ScanEffect.Notice("Этот QR не распознан Кибердекой")), effects)
    }
}
