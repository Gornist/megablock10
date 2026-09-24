package com.megablok10.app.cyberdeck

import com.megablok10.app.breach.LootType
import com.megablok10.app.breach.Tier
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.testing.FakeShardCollection
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test

class ScanObjectTest {
    private val shard = Mb10Qr.Shard(id = "s1", decryptAction = false, tier = 1, valueHint = "низкий", title = "Обрывок", meta = "", body = "")
    private val ramUpgrade = Mb10Qr.RamUpgrade(token = "tok-1", delta = 2)
    private val grant = Mb10Qr.LootGrant(slotRef = "node-1:0", type = LootType.DAEMON, tier = Tier.BASE, encryptedPayload = "x")

    @Test fun scannedShardIsAddedToTheCollectionAndSwitchesToTheShardsSegment() = runTest {
        val shards = FakeShardCollection()
        val scan = ScanObject(shards, applyRamUpgrade = { null }, applyGrant = { null })

        val effects = scan(shard)

        assertEquals(listOf(shard), shards.items.value)
        assertEquals(listOf(ScanEffect.Collected(CollectedKind.Shard)), effects)
    }

    @Test fun ramUpgradeAppliedShowsTheNewCapacity() = runTest {
        val scan = ScanObject(FakeShardCollection(), applyRamUpgrade = { 8 }, applyGrant = { null })

        val effects = scan(ramUpgrade)

        assertEquals(listOf(ScanEffect.Notice("RAM деки увеличена до 8")), effects)
    }

    @Test fun alreadyConsumedRamTokenIsExplainedInsteadOfSilentlyDoingNothing() = runTest {
        val scan = ScanObject(FakeShardCollection(), applyRamUpgrade = { null }, applyGrant = { null })

        val effects = scan(ramUpgrade)

        assertEquals(listOf(ScanEffect.Notice("Этот RAM-токен уже был применён")), effects)
    }

    @Test fun successfulLootGrantSwitchesToTheSegmentMatchingItsType() = runTest {
        val scan = ScanObject(FakeShardCollection(), applyRamUpgrade = { null }, applyGrant = { "Демон получен: Ghostwalker" })

        val effects = scan(grant)

        assertEquals(listOf(ScanEffect.Notice("Демон получен: Ghostwalker"), ScanEffect.Collected(CollectedKind.Daemon)), effects)
    }

    @Test fun shardTypeLootGrantSwitchesToTheShardsSegment() = runTest {
        val scan = ScanObject(FakeShardCollection(), applyRamUpgrade = { null }, applyGrant = { "Шард получен: Обрывок" })

        val effects = scan(grant.copy(type = LootType.SHARD))

        assertEquals(listOf(ScanEffect.Notice("Шард получен: Обрывок"), ScanEffect.Collected(CollectedKind.Shard)), effects)
    }

    @Test fun brokenLootGrantIsExplainedToThePlayer() = runTest {
        val scan = ScanObject(FakeShardCollection(), applyRamUpgrade = { null }, applyGrant = { null })

        val effects = scan(grant)

        assertEquals(ScanEffect.Notice("Фрагмент повреждён — обратитесь к мастеру"), effects.first())
    }

    @Test fun unrecognizedQrIsExplainedToThePlayer() = runTest {
        val scan = ScanObject(FakeShardCollection(), applyRamUpgrade = { null }, applyGrant = { null })

        val effects = scan(Mb10Qr.Contact("pk", "Гость", "Нейтралы"))

        assertEquals(listOf(ScanEffect.Notice("Этот QR не распознан Кибердекой")), effects)
    }
}
