package com.megablok10.app.headset

/**
 * Пересэмплировка моно PCM 16 бит линейной интерполяцией (голос очков 44,1 кГц ↔ частота звонка в WebRTC, обычно 48 или 16 кГц). Состояние (фаза и
 * последний отсчёт) держится между кусками, поэтому стыки кусков не щёлкают. Для прототипа: без фильтра перед понижением частоты (речь выдерживает).
 */
class PcmResampler(private val fromRate: Int, val toRate: Int) {
    init {
        require(fromRate > 0 && toRate > 0) { "частота должна быть положительной: $fromRate → $toRate" }
    }

    private val step = fromRate.toDouble() / toRate

    /** Позиция следующего выходного отсчёта во входной шкале текущего куска; индекс −1 — последний отсчёт предыдущего куска. */
    private var pos = 0.0
    private var prev = 0

    fun process(input: ShortArray): ShortArray {
        if (input.isEmpty()) return ShortArray(0)
        if (fromRate == toRate) return input.copyOf()
        val n = input.size
        val out = ShortArray((n / step).toInt() + 2)
        var count = 0
        var p = pos
        while (p < n - 1) {
            val i = Math.floor(p).toInt()
            val frac = p - i
            val a = if (i < 0) prev else input[i].toInt()
            val b = input[i + 1].toInt()
            out[count++] = (a + (b - a) * frac).toInt().toShort()
            p += step
        }
        pos = p - n
        prev = input[n - 1].toInt()
        return out.copyOf(count)
    }
}

/**
 * Ограниченная по длине очередь отсчётов: пишет сеть, читает аудиопоток. Переполнение вытесняет самое старое — задержка не копится
 * (приёмная сторона всегда играет свежее, а не то, что накопилось за провал сети).
 */
class PcmQueue(private val capacity: Int) {
    private val buf = ShortArray(capacity)
    private var head = 0
    private var size = 0

    /** Сколько отсчётов сейчас в очереди. */
    @Synchronized fun available(): Int = size

    /** Кладёт [data]; возвращает, сколько отсчётов пришлось выбросить (старые, если не поместилось). */
    @Synchronized fun push(data: ShortArray): Int {
        var dropped = 0
        var src = data
        if (src.size > capacity) {
            dropped += src.size - capacity
            src = src.copyOfRange(src.size - capacity, src.size)
        }
        val overflow = size + src.size - capacity
        if (overflow > 0) {
            head = (head + overflow) % capacity
            size -= overflow
            dropped += overflow
        }
        var tail = (head + size) % capacity
        for (s in src) {
            buf[tail] = s
            tail = (tail + 1) % capacity
        }
        size += src.size
        return dropped
    }

    /** Читает до [count] отсчётов в начало [into]; возвращает, сколько прочитано (остальное [into] не трогает). */
    @Synchronized fun read(into: ShortArray, count: Int = into.size): Int {
        val n = minOf(count, into.size, size)
        for (i in 0 until n) {
            into[i] = buf[(head + i) % capacity]
        }
        head = (head + n) % capacity
        size -= n
        return n
    }

    @Synchronized fun clear() {
        head = 0
        size = 0
    }
}
