package com.megablok10.app.sound

import kotlin.math.PI
import kotlin.math.sin

/** Реплики звукового оформления взлома. Тоны синтезируются кодом — ни ассетов, ни лицензий. */
enum class BreachCue { ENTER, TAP, MATCH, TRAP, WARN, SUCCESS, PARTIAL, FAIL }

/**
 * Чистая генерация PCM (16 бит, моно) для терминальных звуков: короткие прямоугольные/пилообразные
 * «блипы» с затуханием. Отдельно от AudioTrack, чтобы длину и амплитуду можно было проверить юнит-тестом.
 */
object BreachTones {
    const val SAMPLE_RATE = 22_050
    private const val PEAK = 0.35 // тихо: не должно резать слух в тишине локации

    /** Одна нота: частота [fromHz]→[toHz] за [ms] миллисекунд, форма [shape], экспоненциальное затухание. */
    private data class Note(val fromHz: Double, val toHz: Double, val ms: Int, val shape: Shape = Shape.SQUARE, val gapMs: Int = 0)
    private enum class Shape { SQUARE, SAW }

    private val cues: Map<BreachCue, List<Note>> = mapOf(
        BreachCue.ENTER to listOf(Note(300.0, 1500.0, 320, Shape.SAW)),
        BreachCue.TAP to listOf(Note(1200.0, 1200.0, 35)),
        BreachCue.MATCH to listOf(Note(700.0, 700.0, 60), Note(1050.0, 1050.0, 60), Note(1400.0, 1400.0, 90)),
        BreachCue.TRAP to listOf(Note(150.0, 110.0, 220, Shape.SAW)),
        BreachCue.WARN to listOf(Note(1800.0, 1800.0, 70)),
        BreachCue.SUCCESS to listOf(Note(600.0, 600.0, 80), Note(800.0, 800.0, 80), Note(1000.0, 1000.0, 80), Note(1400.0, 1400.0, 180)),
        BreachCue.PARTIAL to listOf(Note(700.0, 700.0, 90), Note(900.0, 900.0, 140)),
        BreachCue.FAIL to listOf(Note(500.0, 500.0, 120, Shape.SAW), Note(350.0, 350.0, 120, Shape.SAW), Note(200.0, 160.0, 260, Shape.SAW)),
    )

    fun render(cue: BreachCue): ShortArray {
        val notes = cues.getValue(cue)
        val out = ArrayList<Short>()
        for (note in notes) {
            val n = SAMPLE_RATE * note.ms / 1000
            var phase = 0.0
            for (i in 0 until n) {
                val t = i.toDouble() / n
                val hz = note.fromHz + (note.toHz - note.fromHz) * t
                phase += hz / SAMPLE_RATE
                val frac = phase - Math.floor(phase)
                val wave = when (note.shape) {
                    Shape.SQUARE -> if (sin(2 * PI * frac) >= 0) 1.0 else -1.0
                    Shape.SAW -> 2 * frac - 1
                }
                // короткая атака (без щелчка) и затухание к концу ноты
                val attack = (i / (SAMPLE_RATE * 0.003)).coerceAtMost(1.0)
                val env = attack * Math.exp(-3.0 * t)
                out.add((wave * env * PEAK * Short.MAX_VALUE).toInt().toShort())
            }
            repeat(SAMPLE_RATE * note.gapMs / 1000) { out.add(0) }
        }
        return out.toShortArray()
    }
}
