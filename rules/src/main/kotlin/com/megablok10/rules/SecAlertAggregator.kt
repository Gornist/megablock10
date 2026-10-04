package com.megablok10.rules

import java.util.concurrent.ConcurrentHashMap

/**
 * Склейка сигналов СБ по контейнеру: полное сообщение раз в [windowMs], в промежутке — однострочный счётчик повторов.
 * Живёт в памяти и не переживает перезапуск процесса — это осознанно (ревизия v9 §4). Время приходит снаружи.
 */
class SecAlertAggregator {
    private val states = ConcurrentHashMap<String, State>()
    private class State(var lastFullSentAt: Long = 0, var suppressed: Int = 0)

    /** Тело сообщения, которое нужно отправить сейчас: [payload] целиком или счётчик повторов. */
    fun body(containerId: String, containerName: String, payload: String, now: Long, windowMs: Long): String {
        val state = states.getOrPut(containerId) { State() }
        if (now - state.lastFullSentAt >= windowMs) {
            state.lastFullSentAt = now
            state.suppressed = 0
            return payload
        }
        state.suppressed += 1
        return "Повторные обращения к узлу «$containerName» (×${state.suppressed + 1})"
    }

    companion object {
        /** Окно полного сообщения — 15 минут на контейнер. */
        const val WINDOW_MS = 15 * 60_000L
    }
}
