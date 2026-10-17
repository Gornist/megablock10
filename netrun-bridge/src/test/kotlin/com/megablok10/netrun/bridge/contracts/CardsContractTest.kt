package com.megablok10.netrun.bridge.contracts

import com.megablok10.netrun.bridge.phone.ItemCard
import com.megablok10.netrun.bridge.phone.MoneyCard
import com.megablok10.netrun.bridge.phone.PhoneWire
import com.megablok10.netrun.bridge.phone.ReceiptCard
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Карточки денег, предметов и чек Моста (`PhoneWire`) против `cards.json`: байты подписи и строка карточки (первая копия — приложение, третья — TS). */
class CardsContractTest {
    private val vectors = ContractVectors.load("cards.json")

    @Test fun карточкаДенегБайтыПодписиИСтрока() {
        val all = vectors.list("money")
        assertTrue(all.isNotEmpty())
        for (v in all) {
            val name = v.str("name")
            val card = MoneyCard(v.str("id"), v.str("from"), v.str("to"), v.long("amount"), v.str("memo"), v.str("signature"))
            assertEquals(name, v.str("preimage_utf8"), String(PhoneWire.moneySignedBytes(card.id, card.from, card.to, card.amount, card.memo), Charsets.UTF_8))
            assertEquals(name, v.str("line"), PhoneWire.encodeMoney(card))
            assertEquals(name, card, PhoneWire.decodeMoney(v.str("line")))
        }
    }

    @Test fun карточкаПредметаБайтыПодписиИСтрока() {
        val all = vectors.list("items")
        assertTrue(all.isNotEmpty())
        for (v in all) {
            val name = v.str("name")
            val card = ItemCard(v.str("id"), v.str("from"), v.str("to"), v.str("kind"), v.str("payload"), v.str("signature"))
            assertEquals(name, v.str("preimage_utf8"), String(PhoneWire.itemSignedBytes(card), Charsets.UTF_8))
            assertEquals(name, v.str("line"), PhoneWire.encodeItem(card))
            assertEquals(name, card, PhoneWire.decodeItem(v.str("line")))
        }
    }

    /** Байты подписи чека в Мосте не строятся (он их только пересылает, подпись над `id|ключ` проверяет kit): сверяются строка и разбор. */
    @Test fun чекПолучателяСтрокаИРазбор() {
        val all = vectors.list("receipts")
        assertTrue(all.isNotEmpty())
        for (v in all) {
            val name = v.str("name")
            val receipt = ReceiptCard(v.str("id"), v.str("receiver"), v.str("signature"))
            assertEquals(name, v.str("line"), PhoneWire.encodeReceipt(receipt))
            assertEquals(name, receipt, PhoneWire.decodeReceipt(v.str("line")))
        }
    }

    /** Карточки v1 принимать нельзя (подпись без адресата): декодеры Моста обязаны отказать. */
    @Test fun карточкиСтаройВерсииОтвергаются() {
        assertEquals(null, PhoneWire.decodeMoney("MB10:TX:v1:tx-1:PK_A:PK_B:30:0LfQsA==:SIG_1"))
        assertEquals(null, PhoneWire.decodeItem("MB10:ITEM:v1:i1:PK_A:PK_B:SHARD:U0hBUkQ=:SIG"))
    }
}
