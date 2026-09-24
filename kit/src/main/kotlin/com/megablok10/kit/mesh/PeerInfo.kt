package com.megablok10.kit.mesh

/**
 * Игрок, чьё устройство сейчас видно в локальной сети. host/port — адрес его сервера строк (net.LineServer), живут только
 * пока он онлайн, в контактах не хранятся. pubKeyB64 — его постоянный идентификатор (публичный ключ, см. crypto.Ecdsa).
 */
data class PeerInfo(
    val pubKeyB64: String,
    val callsign: String,
    val faction: String,
    val host: String,
    val port: Int
)
