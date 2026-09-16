package com.megablok10.app.presence

/** Игрок, чьё устройство сейчас видно на локальной сети — host/port живут только пока он онлайн, в контактах не хранятся. */
data class PeerInfo(
    val pubKeyB64: String,
    val callsign: String,
    val faction: String,
    val host: String,
    val port: Int
)
