package com.megablok10.netrun.bridge

import kotlin.system.exitProcess

/** Параметры запуска Моста: `--port`, `--db`, `--test`, `--world-pub`; ключи ролей — `NETRUN_KEY_WORLD|MASTER|TEST` из окружения. */
data class LaunchOptions(val port: Int, val db: String, val config: BridgeConfig)

private fun bad(msg: String): Nothing = throw IllegalArgumentException(msg)

internal fun parseLaunch(args: List<String>, env: Map<String, String>): LaunchOptions {
    var port = 7410
    var db = "netrun-bridge.db"
    var test = false
    var pub: String? = null
    val it = args.iterator()
    fun value(name: String) = if (it.hasNext()) it.next() else bad("у $name нет значения")
    while (it.hasNext()) {
        when (val a = it.next()) {
            "--port" -> port = value(a).toIntOrNull() ?: bad("--port — число")
            "--db" -> db = value(a)
            "--test" -> test = true
            "--world-pub" -> pub = value(a)
            else -> bad("неизвестный аргумент $a")
        }
    }
    val keys = listOf("world", "master", "test").mapNotNull { r -> env["NETRUN_KEY_" + r.uppercase()]?.takeIf { it.isNotEmpty() }?.let { r to it } }.toMap()
    if ("world" !in keys || "master" !in keys) bad("нужны NETRUN_KEY_WORLD и NETRUN_KEY_MASTER")
    if (test && "test" !in keys) bad("с --test нужен NETRUN_KEY_TEST")
    return LaunchOptions(port, db, BridgeConfig(port = port, roleKeys = keys, testMode = test, worldPub = pub))
}

/** Настройки по умолчанию (протокол, раздел 5), создаются при первом старте; мастер правит на ходу. */
internal fun ensureDefaultSettings(store: DocStore) {
    if (store.get(ValueOps.SETTINGS, "global") != null) return
    store.put(
        ValueOps.SETTINGS, "global", 0,
        VJ.obj(
            "confirm_timeout_s" to VJ.p(120L), "inbox_timeout_s" to VJ.p(300L), "disconnect_grace_s" to VJ.p(20L),
            "soft_ice_reentry_pause_s" to VJ.p(600L), "terminal_silent_s" to VJ.p(30L), "auditor_period_s" to VJ.p(60L),
            "tutorial_node" to VJ.p("node_00"),
        ),
    )
}

/** Мост целиком: хранилище, API, правила, аудитор. [close] останавливает всё. */
class BridgeApp(private val options: LaunchOptions) : AutoCloseable {
    val store: DocStore = DocStore.open(options.db)
    private val server: BridgeServer
    private val rules: RuleEngine
    private val auditor: Auditor

    init {
        ensureDefaultSettings(store)
        server = BridgeServer(store, options.config)
        rules = RuleEngine(store)
        TerminalSilentRule(rules).register()
        auditor = Auditor(store)
    }

    val port: Int get() = server.port

    fun start() {
        server.start()
        rules.start()
        auditor.start()
    }

    override fun close() {
        auditor.close()
        rules.close()
        server.stop()
        store.close()
    }
}

fun main(args: Array<String>) {
    val options = try {
        parseLaunch(args.toList(), System.getenv())
    } catch (e: IllegalArgumentException) {
        System.err.println("Мост: ${e.message}\nИспользование: --port N --db путь.db [--test] [--world-pub КЛЮЧ]; ключи — в окружении")
        exitProcess(2)
    }
    val app = BridgeApp(options)
    Runtime.getRuntime().addShutdownHook(Thread { app.close() })
    app.start()
    System.err.println("Мост запущен: порт ${app.port}, база ${options.db}${if (options.config.testMode) ", режим --test" else ""}")
    Thread.currentThread().join()
}
