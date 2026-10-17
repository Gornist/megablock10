package com.megablok10.app.contracts

import com.megablok10.app.qr.ItemKind
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.qr.Mb10QrCodec
import com.megablok10.kit.handover.HandoverRules
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Карточки денег, предметов и чек против `cards.json`: байты подписи и строка карточки (вторая копия — Мост `PhoneWire`, третья — TS). */
class CardsContractTest {
    private val vectors = ContractVectors.load("cards.json")

    @Test fun moneyCardPreimageAndLine() {
        val all = vectors.list("money")
        assertTrue(all.isNotEmpty())
        for (v in all) {
            val tx = Mb10Qr.Transaction(v.str("id"), v.str("from"), v.str("to"), v.long("amount"), v.str("memo"), v.str("signature"))
            val name = v.str("name")
            assertEquals(name, v.str("preimage_utf8"), String(Mb10QrCodec.transactionSignaturePayload(tx.id, tx.fromPubKeyB64, tx.toPubKeyB64, tx.amount, tx.memo), Charsets.UTF_8))
            assertEquals(name, v.str("line"), Mb10QrCodec.encodeTransaction(tx))
            assertEquals(name, tx, Mb10QrCodec.decode(v.str("line")))
        }
    }

    @Test fun itemCardPreimageAndLine() {
        val all = vectors.list("items")
        assertTrue(all.isNotEmpty())
        for (v in all) {
            val card = Mb10Qr.ItemTransfer(v.str("id"), v.str("from"), v.str("to"), ItemKind.valueOf(v.str("kind")), v.str("payload"), v.str("signature"))
            val name = v.str("name")
            assertEquals(name, v.str("preimage_utf8"), String(Mb10QrCodec.itemTransferSignaturePayload(card.id, card.fromPubKeyB64, card.toPubKeyB64, card.kind, card.payload), Charsets.UTF_8))
            assertEquals(name, v.str("line"), Mb10QrCodec.encodeItemTransfer(card))
            assertEquals(name, card, Mb10QrCodec.decode(v.str("line")))
        }
    }

    @Test fun receiptPreimageAndLine() {
        val all = vectors.list("receipts")
        assertTrue(all.isNotEmpty())
        for (v in all) {
            val receipt = Mb10Qr.Receipt(v.str("id"), v.str("receiver"), v.str("signature"))
            val name = v.str("name")
            assertEquals(name, v.str("preimage_utf8"), String(HandoverRules.receiptSignaturePayload(receipt.id, receipt.receiverPubKeyB64), Charsets.UTF_8))
            assertEquals(name, v.str("line"), Mb10QrCodec.encodeReceipt(receipt))
            assertEquals(name, receipt, Mb10QrCodec.decode(v.str("line")))
        }
    }
}
