package com.megablok10.app.collector

/**
 * Отказы сервера, связанные с кодом персонажа (docs/provisioning-qr.md): запись CHARACTER_CREATED с sourceRef выдачи отклоняется, если код уже применён
 * на другом телефоне или погашен новой выдачей. Тексты приходят в `rejected[].error` ответа /api/changes; распознаём по общему началу.
 */
object ProvisionRejection {
    const val PREFIX = "provision code"
    const val PLAYER_MESSAGE = "Код персонажа уже использован или заменён. Обратитесь к мастеру"

    fun isProvisionError(error: String): Boolean = error.trim().startsWith(PREFIX, ignoreCase = true)

    fun anyProvisionError(errors: Collection<String>): Boolean = errors.any(::isProvisionError)
}
