package com.megablok10.app.wallet

import com.megablok10.app.collector.ChangeField
import com.megablok10.app.collector.ChangeReason
import com.megablok10.app.data.TransactionEntity
import com.megablok10.app.data.TransactionStatus
import com.megablok10.app.testing.RoomTest
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Не-переводные зачисления TransactionStore на настоящей Room: находка в шарде, эдди за взлом, стартовый баланс из QR мастера и
 * правка баланса с дашборда. Характеризационный тест — фиксирует то, что код делает сейчас (в т. ч. неочевидное, см. комментарии).
 */
@RunWith(RobolectricTestRunner::class)
class TransactionStoreTest : RoomTest() {
    private suspend fun rows(): List<TransactionEntity> = db.transactionDao().observeAll().first()

    private suspend fun row(id: String): TransactionEntity? = rows().singleOrNull { it.id == id }

    /** Записи баланса для мастера: (было, стало, причина, основание). */
    private suspend fun balanceRecords() = records().map { listOf(it.oldValue, it.newValue, it.reason, it.sourceRef) }

    // ── creditShardMoney ────────────────────────────────────────────────────────────────────────────────────────────

    @Test fun shardMoneyIsCreditedAsAConfirmedRowAndRecordedForTheMaster() = runBlocking {
        wallet.creditShardMoney("s1", 50, "Чертёж")

        assertEquals(50L, balance())
        val entity = row("shard:s1")!!
        assertEquals(TransactionEntity("shard:s1", "", 50, "Шард: Чертёж", entity.timestamp, TransactionStatus.CONFIRMED), entity)
        val record = records().single()
        assertEquals(ChangeField.BALANCE, record.field)
        assertEquals("0", record.oldValue)
        assertEquals("50", record.newValue)
        assertEquals(ChangeReason.SHARD_SCAN, record.reason)
        assertEquals("в записи — id шарда, без префикса shard:", "s1", record.sourceRef)
        assertEquals("зачисление от шарда — действие самого игрока", me.publicKeyB64, record.actor)
    }

    @Test fun theSameShardScannedAgainIsNotCreditedTwice() = runBlocking {
        wallet.creditShardMoney("s1", 50, "Чертёж")
        wallet.creditShardMoney("s1", 50, "Чертёж")
        wallet.creditShardMoney("s1", 999, "Другая копия")

        assertEquals(50L, balance())
        assertEquals(1, rows().size)
        assertEquals("повтор не оставляет и записи для мастера", 1, records().size)
    }

    @Test fun differentShardsAccumulateAndTheirRecordsFormAChain() = runBlocking {
        wallet.creditShardMoney("s1", 10, "А")
        wallet.creditShardMoney("s2", 20, "Б")

        assertEquals(30L, balance())
        assertEquals(listOf(listOf("0", "10", ChangeReason.SHARD_SCAN, "s1"), listOf("10", "30", ChangeReason.SHARD_SCAN, "s2")), balanceRecords())
    }

    @Test fun shardMoneyOfZeroOrLessIsIgnoredWithoutARow() = runBlocking {
        wallet.creditShardMoney("s0", 0, "Пусто")
        wallet.creditShardMoney("s-", -5, "Минус")

        assertEquals(0L, balance())
        assertEquals(emptyList<TransactionEntity>(), rows())
        assertEquals(emptyList<Any>(), records())
        wallet.creditShardMoney("s0", 7, "Теперь с деньгами")
        assertEquals("отказ по сумме не «занимает» id шарда", 7L, balance())
    }

    // ── creditContainerEddies ───────────────────────────────────────────────────────────────────────────────────────

    @Test fun containerEddiesAreCreditedPerAttemptAndRecorded() = runBlocking {
        wallet.creditContainerEddies("att-1", 120, "Панель СБ")

        assertEquals(120L, balance())
        val entity = row("breach:att-1")!!
        assertEquals("Взлом: Панель СБ", entity.memo)
        assertEquals(TransactionStatus.CONFIRMED, entity.status)
        assertEquals("", entity.counterpartyPubKeyB64)
        val record = records().single()
        assertEquals(listOf("0", "120", ChangeReason.BREACH_EDDIES, "att-1"), listOf(record.oldValue, record.newValue, record.reason, record.sourceRef))
        assertEquals(me.publicKeyB64, record.actor)
    }

    @Test fun aRepeatedCallForTheSameAttemptIsIgnoredButANewAttemptOnTheSameContainerPays() = runBlocking {
        wallet.creditContainerEddies("att-1", 120, "Панель СБ")
        wallet.creditContainerEddies("att-1", 120, "Панель СБ")
        assertEquals(120L, balance())
        assertEquals(1, records().size)

        wallet.creditContainerEddies("att-2", 80, "Панель СБ")
        assertEquals(200L, balance())
        assertEquals(listOf(listOf("0", "120", ChangeReason.BREACH_EDDIES, "att-1"), listOf("120", "200", ChangeReason.BREACH_EDDIES, "att-2")), balanceRecords())
    }

    @Test fun containerEddiesOfZeroOrLessAreIgnored() = runBlocking {
        wallet.creditContainerEddies("att-0", 0, "Панель")
        wallet.creditContainerEddies("att-neg", -1, "Панель")

        assertEquals(0L, balance())
        assertEquals(emptyList<Any>(), records())
        assertNull(row("breach:att-0"))
    }

    @Test fun shardAndBreachIdsDoNotCollideEvenWithTheSameSuffix() = runBlocking {
        wallet.creditShardMoney("x", 10, "Шард")
        wallet.creditContainerEddies("x", 20, "Контейнер")

        assertEquals(30L, balance())
        assertEquals(setOf("shard:x", "breach:x"), rows().map { it.id }.toSet())
    }

    // ── setStartingBalance ──────────────────────────────────────────────────────────────────────────────────────────

    @Test fun startingBalanceOnAnEmptyWalletBecomesExactlyTheGivenValue() = runBlocking {
        wallet.setStartingBalance("p1", 300)

        assertEquals(300L, balance())
        val entity = row("prov:p1")!!
        assertEquals(300L, entity.amount)
        assertEquals("Стартовый баланс", entity.memo)
        assertEquals(TransactionStatus.CONFIRMED, entity.status)
        assertEquals(listOf(listOf("0", "300", ChangeReason.CHARACTER_CREATED, "p1")), balanceRecords())
    }

    @Test fun startingBalanceOverLeftoversOfThePreviousSessionIsADifferenceNotAnAddition() = runBlocking {
        // Сброс сессии стирает только ключи — деньги прежней сессии остались в базе.
        wallet.creditShardMoney("old", 40, "Остаток")

        wallet.setStartingBalance("p1", 500)
        assertEquals(500L, balance())
        assertEquals(460L, row("prov:p1")!!.amount)
        assertEquals(listOf("40", "500", ChangeReason.CHARACTER_CREATED, "p1"), records().last().let { listOf(it.oldValue, it.newValue, it.reason, it.sourceRef) })
    }

    @Test fun startingBalanceBelowTheLeftoversWritesANegativeRow() = runBlocking {
        wallet.creditShardMoney("old", 80, "Остаток")

        wallet.setStartingBalance("p1", 30)

        assertEquals(30L, balance())
        assertEquals(-50L, row("prov:p1")!!.amount)
    }

    @Test fun startingBalanceEqualToTheCurrentOneWritesNothing() = runBlocking {
        wallet.setStartingBalance("p0", 0)
        assertEquals("пустой кошелёк и ноль — ни строки, ни записи", emptyList<TransactionEntity>(), rows())

        wallet.setStartingBalance("p1", 300)
        wallet.setStartingBalance("p1", 300)
        wallet.setStartingBalance("p2", 300)
        assertEquals(listOf("prov:p1"), rows().map { it.id })
        assertEquals(1, records().size)
    }

    @Test fun repeatedProvisionAfterMoneyMovedKeepsTheBalanceAsIs() = runBlocking {
        // Повторная доставка того же QR после движения денег: баланс «до значения мастера» не подтягивается — insertIfAbsent по id выдачи
        // отказывает (дельта посчитана, но строка с таким id уже есть) и записи для мастера нет.
        wallet.setStartingBalance("p1", 300)
        wallet.creditShardMoney("s1", 10, "Находка")

        wallet.setStartingBalance("p1", 300)

        assertEquals(310L, balance())
        assertEquals(2, records().size)
        assertEquals(2, rows().size)
    }

    // ── applyBalanceOverride ────────────────────────────────────────────────────────────────────────────────────────

    @Test fun masterOverrideSetsTheAbsoluteBalanceThroughADifferenceRowAndDoesNotEchoARecord() = runBlocking {
        wallet.creditShardMoney("s1", 100, "Шард")
        val before = records()

        wallet.applyBalanceOverride("c1", 250, "штраф")

        assertEquals(250L, balance())
        val entity = row("override:c1")!!
        assertEquals(150L, entity.amount)
        assertEquals("Правка мастера: штраф", entity.memo)
        assertEquals(TransactionStatus.CONFIRMED, entity.status)
        assertEquals("правка — следствие записи на сервере, обратно на коллектор она не уходит", before, records())
    }

    @Test fun masterOverrideCanLowerTheBalanceAndEvenMakeItNegative() = runBlocking {
        wallet.creditShardMoney("s1", 100, "Шард")

        wallet.applyBalanceOverride("c1", 40, "налог")
        assertEquals(40L, balance())
        assertEquals(-60L, row("override:c1")!!.amount)

        // Проверки на неотрицательность в хранилище нет — отсекает её только тот, кто разбирает правку (MasterOverride.parse не отсекает).
        wallet.applyBalanceOverride("c2", -5, "долг")
        assertEquals(-5L, balance())
    }

    @Test fun aRepeatedOverrideWithTheSameChangeIdIsIgnoredEvenWithAnotherValue() = runBlocking {
        wallet.creditShardMoney("s1", 100, "Шард")
        wallet.applyBalanceOverride("c1", 250, "штраф")

        wallet.applyBalanceOverride("c1", 250, "штраф")
        wallet.applyBalanceOverride("c1", 10, "иное значение")

        assertEquals(250L, balance())
        assertEquals(2, rows().size)
    }

    @Test fun anOverrideEqualToTheCurrentBalanceStillLeavesAZeroRow() = runBlocking {
        // В отличие от setStartingBalance, нулевая разность не пропускается: строка нужна, чтобы id правки считался применённым.
        wallet.creditShardMoney("s1", 100, "Шард")

        wallet.applyBalanceOverride("c1", 100, "подтверждение")

        assertEquals(100L, balance())
        assertEquals(0L, row("override:c1")!!.amount)
    }

    @Test fun overrideRecomputesTheDifferenceFromTheBalanceAtApplyTime() = runBlocking {
        wallet.applyBalanceOverride("c1", 500, "выдача")
        wallet.creditShardMoney("s1", 30, "Шард")   // между правкой и следующей баланс сдвинулся

        wallet.applyBalanceOverride("c2", 500, "снова 500")

        assertEquals(500L, balance())
        assertEquals(-30L, row("override:c2")!!.amount)
    }
}
