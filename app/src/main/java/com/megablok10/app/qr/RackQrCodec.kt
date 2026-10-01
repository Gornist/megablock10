package com.megablok10.app.qr

import com.megablok10.kit.text.Base64Text.decode as unb64
import com.megablok10.kit.text.Base64Text.encode as b64

/**
 * Кодек QR стойки «Сети» (`Mb10Qr.Rack`): `MB10:RACK:v1:<терминал>:<b64 host:port>:<world_pub>[:<b64 подпись>]`, протокол Моста,
 * раздел 8. Адрес — в base64, чтобы двоеточие IPv6 не ломало разбор. Вызывается из [Mb10QrCodec.decode]; отдельным объектом — чтобы
 * не раздувать общий кодек.
 */
object RackQrCodec {
    private const val MIN_PARTS = 6
    private const val PORT_MAX = 65535

    fun encode(r: Mb10Qr.Rack): String =
        listOf("MB10", "RACK", "v1", r.terminal, b64("${r.host}:${r.port}"), r.worldPub, b64(r.label)).joinToString(":")

    /** [parts] — QR, разрезанный по `:`, магия и тип уже проверены. */
    internal fun decode(parts: List<String>): Mb10Qr.Rack? {
        val terminal = parts.getOrNull(3).orEmpty()
        val address = if (parts.size >= MIN_PARTS && parts[2] == "v1") unb64(parts[4]) else ""
        val sep = address.lastIndexOf(':')
        val port = address.substring(sep + 1).toIntOrNull()?.takeIf { it in 1..PORT_MAX }
        val worldPub = parts.getOrNull(5).orEmpty()
        val label = parts.getOrNull(6)?.let { unb64(it) }.orEmpty()
        return if (terminal.isEmpty() || sep <= 0 || worldPub.isEmpty()) null else port?.let { Mb10Qr.Rack(terminal, address.substring(0, sep), it, worldPub, label) }
    }
}
