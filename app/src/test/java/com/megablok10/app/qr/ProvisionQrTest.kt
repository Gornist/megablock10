package com.megablok10.app.qr

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class ProvisionQrTest {
    private fun qr(
        id: String = "p-0001", url: String = "http://192.0.2.10:2517", secret: String = "код: игры/=+", callsign: String = "Ольга: RAZOR",
        faction: String = "Отряд: самообороны", balance: Long = 250, ram: Int = 9
    ) = Mb10Qr.Provision(id, url, secret, callsign, faction, balance, ram)

    @Test fun roundTripsWithColonsAndCyrillicInFreeText() {
        val p = qr()
        assertEquals(p, Mb10QrCodec.decode(Mb10QrCodec.encodeProvision(p)))
    }

    @Test fun emptyServerAndSecretAreAllowed() {
        val p = qr(url = "", secret = "", ram = 0, balance = 0)
        assertEquals(p, Mb10QrCodec.decode(Mb10QrCodec.encodeProvision(p)))
        assertNull(ProvisionRules.validate(p))
    }

    @Test fun otherVersionOrBrokenNumbersAreRejected() {
        val line = Mb10QrCodec.encodeProvision(qr())
        assertNull(Mb10QrCodec.decode(line.replace(":PROV:v1:", ":PROV:v2:")))
        assertNull(Mb10QrCodec.decode(Mb10QrCodec.encodeProvision(qr()).substringBeforeLast(':') + ":не-число"))
        assertNull(Mb10QrCodec.decode("MB10:PROV:v1:only:few:parts"))
        assertNotNull(Mb10QrCodec.decode(line))
    }

    @Test fun validCardPassesRules() { assertNull(ProvisionRules.validate(qr())) }

    @Test fun rulesRejectBadInput() {
        assertNotNull("нет номера выдачи", ProvisionRules.validate(qr(id = "")))
        assertNotNull("плохие символы в номере", ProvisionRules.validate(qr(id = "p 1/2")))
        assertNotNull("нет позывного", ProvisionRules.validate(qr(callsign = "  ")))
        assertNotNull("слишком длинный позывной", ProvisionRules.validate(qr(callsign = "x".repeat(41))))
        assertNotNull("адрес не http", ProvisionRules.validate(qr(url = "ftp://x")))
        assertNotNull("отрицательный баланс", ProvisionRules.validate(qr(balance = -1)))
        assertNotNull("огромный баланс", ProvisionRules.validate(qr(balance = ProvisionRules.MAX_BALANCE + 1)))
        assertNotNull("RAM вне 6..13", ProvisionRules.validate(qr(ram = 5)))
        assertNotNull("RAM вне 6..13", ProvisionRules.validate(qr(ram = 14)))
        assertNull("RAM 0 = по умолчанию", ProvisionRules.validate(qr(ram = 0)))
    }
}
