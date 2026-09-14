package com.megablok10.app.qr

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
    fun `access point round-trips with punctuation in the name`() {
        val raw = Mb10QrCodec.encodeAccessPoint("ap-vent-8", "Панель вентиляции: техэтаж, блок Б")
        val decoded = Mb10QrCodec.decode(raw)
        assertEquals(Mb10Qr.AccessPoint("ap-vent-8", "Панель вентиляции: техэтаж, блок Б"), decoded)
    }

    @Test
    fun `shard round-trips with colons, newlines and cyrillic in every free-text field`() {
        val raw = Mb10QrCodec.encodeShard(
            id = "shard-report-1",
            badge = "LOCKED",
            decryptAction = true,
            title = "Служебный лог: клиника",
            meta = "получен 21:02 · клиника, уровень доступа 2",
            body = "«...партия С-9: брак клапана, ответа не было...»"
        )
        val decoded = Mb10QrCodec.decode(raw)
        assertEquals(
            Mb10Qr.Shard(
                id = "shard-report-1",
                badge = "LOCKED",
                decryptAction = true,
                title = "Служебный лог: клиника",
                meta = "получен 21:02 · клиника, уровень доступа 2",
                body = "«...партия С-9: брак клапана, ответа не было...»"
            ),
            decoded
        )
    }

    @Test
    fun `shard decryptAction flag survives round-trip both ways`() {
        val lockedRaw = Mb10QrCodec.encodeShard("s1", "LOCKED", true, "t", "m", "b")
        val publicRaw = Mb10QrCodec.encodeShard("s2", "PUBLIC", false, "t", "m", "b")
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
