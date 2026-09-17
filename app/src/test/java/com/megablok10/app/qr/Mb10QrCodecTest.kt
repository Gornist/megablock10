package com.megablok10.app.qr

import com.megablok10.app.breach.Container
import com.megablok10.app.breach.LootSlot
import com.megablok10.app.breach.LootType
import com.megablok10.app.breach.Tier
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Свободный текст (позывной, имя точки, текст шарда) идёт в QR через base64
 * именно чтобы двоеточия/пробелы/кириллица внутри него не ломали разбор —
 * эти тесты специально гоняют такой "неудобный" текст через полный цикл
 * encode -> decode, а не только простые ASCII-строки без пунктуации.
 */
class Mb10QrCodecTest {

    @Test
    fun `contact round-trips`() {
        val raw = Mb10QrCodec.encodeContact("pubKeyB64==", "Zipa_09", "Otryad_SB")
        val decoded = Mb10QrCodec.decode(raw)
        assertEquals(Mb10Qr.Contact("pubKeyB64==", "Zipa_09", "Otryad_SB"), decoded)
    }

    @Test
    fun `container round-trips with punctuation in the name and a loot slot`() {
        val container = Container(
            id = "container-vent-8",
            name = "Панель вентиляции: техэтаж, блок Б",
            tier = Tier.HARD,
            ownerFaction = "Otryad_SB",
            loot = listOf(LootSlot(type = LootType.SHARD, tier = Tier.BASE, copies = 3, payload = "cGF5bG9hZA=="))
        )
        val raw = Mb10QrCodec.encodeContainer(container)
        val decoded = Mb10QrCodec.decode(raw)
        assertEquals(Mb10Qr.ContainerQr(container), decoded)
    }

    @Test
    fun `legacy AP QR still decodes as a tier-BASE container with no loot`() {
        // Формат до ревизии v9 (MB10:AP:v1:id:b64(name)) — уже напечатанные до неё QR обязаны продолжать читаться.
        val decoded = Mb10QrCodec.decode("MB10:AP:v1:ap-vent-8:0J/QsNC90LXQu9GM")
        assertEquals(
            Mb10Qr.ContainerQr(Container(id = "ap-vent-8", name = "Панель", tier = Tier.BASE, ownerFaction = "", loot = emptyList())),
            decoded
        )
    }

    @Test
    fun `shard round-trips with colons, newlines and cyrillic in every free-text field`() {
        val raw = Mb10QrCodec.encodeShard(
            id = "shard-report-1",
            decryptAction = true,
            tier = 2,
            valueHint = "ценный тех. документ",
            title = "Служебный лог: клиника",
            meta = "получен 21:02 · клиника, уровень доступа 2",
            body = "«...партия С-9: брак клапана, ответа не было...»"
        )
        val decoded = Mb10QrCodec.decode(raw)
        assertEquals(
            Mb10Qr.Shard(
                id = "shard-report-1",
                decryptAction = true,
                tier = 2,
                valueHint = "ценный тех. документ",
                title = "Служебный лог: клиника",
                meta = "получен 21:02 · клиника, уровень доступа 2",
                body = "«...партия С-9: брак клапана, ответа не было...»"
            ),
            decoded
        )
    }

    @Test
    fun `shard decryptAction flag survives round-trip both ways`() {
        val lockedRaw = Mb10QrCodec.encodeShard("s1", decryptAction = true, tier = 1, valueHint = "", title = "t", meta = "m", body = "b")
        val publicRaw = Mb10QrCodec.encodeShard("s2", decryptAction = false, tier = 1, valueHint = "", title = "t", meta = "m", body = "b")
        assertEquals(true, (Mb10QrCodec.decode(lockedRaw) as Mb10Qr.Shard).decryptAction)
        assertEquals(false, (Mb10QrCodec.decode(publicRaw) as Mb10Qr.Shard).decryptAction)
    }

    @Test
    fun `transaction round-trips with memo containing colons`() {
        val tx = Mb10Qr.Transaction(
            id = "tx-1",
            fromPubKeyB64 = "pubKeyB64==",
            amount = 350,
            memo = "Антидот: у контрабандиста",
            signatureB64 = "sigB64=="
        )
        val decoded = Mb10QrCodec.decode(Mb10QrCodec.encodeTransaction(tx))
        assertEquals(tx, decoded)
    }

    @Test
    fun `transaction signature payload is deterministic for the same inputs`() {
        val a = Mb10QrCodec.transactionSignaturePayload("tx-1", "pub==", 100, "за информацию")
        val b = Mb10QrCodec.transactionSignaturePayload("tx-1", "pub==", 100, "за информацию")
        assertEquals(String(a), String(b))
    }

    @Test
    fun `transaction signature payload changes if amount is tampered`() {
        val original = Mb10QrCodec.transactionSignaturePayload("tx-1", "pub==", 100, "оплата")
        val tampered = Mb10QrCodec.transactionSignaturePayload("tx-1", "pub==", 100000, "оплата")
        assert(!original.contentEquals(tampered))
    }

    @Test
    fun `receipt round-trips`() {
        val receipt = Mb10Qr.Receipt(id = "tx-1", receiverPubKeyB64 = "recvPub==", signatureB64 = "sigB64==")
        val decoded = Mb10QrCodec.decode(Mb10QrCodec.encodeReceipt(receipt))
        assertEquals(receipt, decoded)
    }

    @Test
    fun `receipt signature payload changes if receiver key is tampered`() {
        val original = Mb10QrCodec.receiptSignaturePayload("tx-1", "recvPub==")
        val tampered = Mb10QrCodec.receiptSignaturePayload("tx-1", "otherPub==")
        assert(!original.contentEquals(tampered))
    }

    @Test
    fun `unknown magic prefix decodes to null`() {
        assertNull(Mb10QrCodec.decode("NOTMB10:CONTACT:v1:a:b:c"))
    }

    @Test
    fun `unknown type segment decodes to null`() {
        assertNull(Mb10QrCodec.decode("MB10:UNKNOWN:v1:a:b:c"))
    }

    @Test
    fun `truncated transaction decodes to null instead of throwing`() {
        assertNull(Mb10QrCodec.decode("MB10:TX:v1:only-id"))
    }

    @Test
    fun `non-numeric amount decodes to null instead of throwing`() {
        assertNull(Mb10QrCodec.decode("MB10:TX:v1:tx-1:pub==:notanumber:bWVtbw==:sig=="))
    }

    @Test
    fun `garbage base64 in a free-text field decodes to null instead of throwing`() {
        assertNull(Mb10QrCodec.decode("MB10:AP:v1:ap-1:not-valid-base64!!!"))
    }
}
