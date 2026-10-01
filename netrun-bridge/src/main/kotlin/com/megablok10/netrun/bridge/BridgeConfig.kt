package com.megablok10.netrun.bridge

/** Версия протокола Моста (`NETRUN_PROTO`), раздел 1 протокола. */
const val NETRUN_PROTO = 1

/**
 * Настройки API. [roleKeys] — общий секрет каждой роли (`world`, `master`); роль `test` пускается только при [testMode]
 * и тоже с ключом из [roleKeys] (`test`). [idleTimeoutMs] — через сколько тишины Мост закрывает соединение (протокол: 30 с).
 */
data class BridgeConfig(
    val port: Int = 7410,
    val roleKeys: Map<String, String>,
    val testMode: Boolean = false,
    val idleTimeoutMs: Long = 30_000,
    val bridgeVersion: String = "0.1.0",
    val worldPub: String? = null,
)
