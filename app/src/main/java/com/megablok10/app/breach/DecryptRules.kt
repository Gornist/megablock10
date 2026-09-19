package com.megablok10.app.breach

import kotlin.random.Random

/**
 * Правила расшифровки шардов: мини-игра шифр-замка запускается только при наличии демона-дешифратора
 * (эффект DECRYPT) тира не ниже тира шарда; без него зашифрованный шард — просто набор символов.
 */
object DecryptRules {
    /** Лучший подходящий дешифратор коллекции для шарда данного тира, либо null. */
    fun bestDecrypter(daemons: List<Daemon>, shardTier: Int): Daemon? =
        daemons.filter { it.effect == DaemonEffect.DECRYPT && it.tier.level >= shardTier }.minByOrNull { it.tier.level }

    /**
     * Псевдотекст вместо содержимого зашифрованного шарда: столько же символов, сколько в настоящем теле, но без единого
     * читаемого. Детерминирован от [seed] (id шарда), чтобы экран не «мерцал» разными значениями при перерисовке.
     */
    fun garble(body: String, seed: Long): String {
        val random = Random(seed)
        val symbols = "0123456789ABCDEF▓▒░#%&@$"
        val out = StringBuilder()
        var run = 0
        for (ch in body) {
            if (ch == '\n') { out.append('\n'); run = 0; continue }
            if (ch == ' ') { out.append(' '); run = 0; continue }
            out.append(symbols[random.nextInt(symbols.length)])
            run += 1
        }
        return out.toString()
    }
}
