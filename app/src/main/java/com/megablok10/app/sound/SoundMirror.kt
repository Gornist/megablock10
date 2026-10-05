package com.megablok10.app.sound

/**
 * Получатель дубля звуков приложения — очки Pico (headset.HeadsetRuntime). [SoundPlayer] сообщает ему о каждом звуке; если [takesOver]
 * истинно, очки играют звук сами (у них копии тех же файлов), и телефон молчит. Нет связи — [takesOver] ложно, телефон играет как раньше.
 */
interface SoundMirror {
    val takesOver: Boolean

    /** [kind]: [RING] | [RINGBACK] | [MESSAGE] | [STOP] — значения поля `kind` кадра `sound`. */
    fun onSound(kind: String)

    companion object {
        /** Рингтон входящего звонка (петля). */
        const val RING = "ring"
        /** Гудок дозвона исходящего (петля). */
        const val RINGBACK = "ringback"
        /** Сигнал нового сообщения (одиночный). */
        const val MESSAGE = "message"
        /** Выключить петлю: ответили, сбросили, звонок закончился. */
        const val STOP = "stop"
    }
}
