package com.megablok10.rules

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
        for (ch in body) {
            // Переводы строк и пробелы остаются как есть (форма текста читается), остальное — случайный символ; random тратится только на них.
            when (ch) {
                '\n', ' ' -> out.append(ch)
                else -> out.append(symbols[random.nextInt(symbols.length)])
            }
        }
        return out.toString()
    }
}
