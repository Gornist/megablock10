package com.megablok10.app.breach

/** Эффекты демонов живут в общем модуле правил (:rules); псевдоним — чтобы код приложения не менял импорты. */
typealias DaemonEffect = com.megablok10.rules.DaemonEffect

fun DaemonEffect.label(): String = when (this) {
    DaemonEffect.EXTRACT_SHARD -> "извлекает шард из контейнера"
    DaemonEffect.EXTRACT_DAEMON -> "извлекает демона из контейнера"
    DaemonEffect.GHOST -> "убирает ваш ID из сигнала СБ"
    DaemonEffect.TIMESKEW -> "+10 мин к задержке сигнала СБ"
    DaemonEffect.BLACKOUT -> "сигнал СБ не отправляется"
    DaemonEffect.JITTER -> "+15 сек к таймеру попытки"
    DaemonEffect.DECRYPT -> "расшифровывает зашифрованные шарды"
    DaemonEffect.MINER -> "добывает эдди из взломанного узла"
}

/** "N ячеек/ячейка/ячейки" с русским склонением — используется как цена демона в буфере взлома. */
fun cellsLabel(count: Int): String {
    val mod100 = count % 100
    val mod10 = count % 10
    val word = when {
        mod100 in 11..14 -> "ячеек"
        mod10 == 1 -> "ячейка"
        mod10 in 2..4 -> "ячейки"
        else -> "ячеек"
    }
    return "$count $word"
}
