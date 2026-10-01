package com.megablok10.app.netrun

import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.qr.Mb10QrCodec
import com.megablok10.app.qr.RackQrCodec
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** QR стойки: `MB10:RACK:v1:<терминал>:<b64 host:port>:<world_pub>[:<b64 подпись>]` (протокол Моста, раздел 8). */
class RackQrTest {
    private val worldPub = "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE+/=="

    @Test fun `round-trips with a label that has colons and cyrillic`() {
        val rack = Mb10Qr.Rack("t03", "10.10.0.10", 7411, worldPub, "Подвал: стойка 3")
        assertEquals(rack, Mb10QrCodec.decode(RackQrCodec.encode(rack)))
    }

    @Test fun `label is optional`() {
        val raw = "MB10:RACK:v1:t03:${com.megablok10.kit.text.Base64Text.encode("10.10.0.10:7411")}:$worldPub"
        assertEquals(Mb10Qr.Rack("t03", "10.10.0.10", 7411, worldPub, ""), Mb10QrCodec.decode(raw))
    }

    @Test fun `ipv6 host keeps its colons because the address is base64`() {
        val rack = Mb10Qr.Rack("t01", "fd00::10", 7411, worldPub)
        assertEquals(rack, Mb10QrCodec.decode(RackQrCodec.encode(rack)))
    }

    @Test fun `broken codes are not racks`() {
        val addr = com.megablok10.kit.text.Base64Text.encode("10.10.0.10:7411")
        assertNull("версия", Mb10QrCodec.decode("MB10:RACK:v2:t03:$addr:$worldPub"))
        assertNull("нет ключа мира", Mb10QrCodec.decode("MB10:RACK:v1:t03:$addr:"))
        assertNull("нет терминала", Mb10QrCodec.decode("MB10:RACK:v1::$addr:$worldPub"))
        assertNull("порт не число", Mb10QrCodec.decode("MB10:RACK:v1:t03:${com.megablok10.kit.text.Base64Text.encode("10.10.0.10:x")}:$worldPub"))
        assertNull("порт вне диапазона", Mb10QrCodec.decode("MB10:RACK:v1:t03:${com.megablok10.kit.text.Base64Text.encode("10.10.0.10:70000")}:$worldPub"))
        assertNull("адрес без порта", Mb10QrCodec.decode("MB10:RACK:v1:t03:${com.megablok10.kit.text.Base64Text.encode("10.10.0.10")}:$worldPub"))
        assertNull("мало частей", Mb10QrCodec.decode("MB10:RACK:v1:t03"))
    }
}
