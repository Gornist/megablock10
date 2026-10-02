package com.megablok10.netrun.bridge

import com.megablok10.kit.log.KitLog
import com.megablok10.netrun.bridge.phone.PhoneDelivery
import com.megablok10.netrun.bridge.phone.PhoneInbox
import com.megablok10.netrun.bridge.phone.PhoneNetwork
import com.megablok10.netrun.bridge.phone.StderrLog
import com.megablok10.netrun.bridge.phone.WorldKey
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.system.exitProcess

/** Известный заранее адрес телефона (стенд e2e): `host:port=ключ`. Эмулятор за NAT виден Мосту как 127.0.0.1, такой адрес по строкам не узнать. */
data class StaticPhone(val host: String, val port: Int, val key: String)

/**
 * Параметры запуска Моста: `--port`, `--line-port`, `--db`, `--test`, `--seed` и `--phone host:port=ключ` (стенд, только с `--test`), `--world-pub`;
 * ключи ролей — `NETRUN_KEY_WORLD|MASTER|TEST` из окружения.
 */
data class LaunchOptions(
    val port: Int, val db: String, val config: BridgeConfig, val linePort: Int = DEFAULT_LINE_PORT, val seed: String? = null,
    val phones: List<StaticPhone> = emptyList(),
)

/** Порт, на котором Мост принимает строки телефонов (карточки сдачи, чеки, запрос входа); его телефон берёт из QR стойки. */
const val DEFAULT_LINE_PORT = 7411

private fun bad(msg: String): Nothing = throw IllegalArgumentException(msg)

/** Значения флагов командной строки до проверки сочетаний. */
private class Flags {
    var port = 7410
    var db = "netrun-bridge.db"
    var linePort = DEFAULT_LINE_PORT
    var test = false
    var pub: String? = null
    var seed: String? = null
    val phones = mutableListOf<StaticPhone>()
}

/** `host:port=ключ` — ключ base64 и сам содержит `=`, поэтому делим по первому. */
private fun parsePhone(spec: String): StaticPhone {
    val eq = spec.indexOf('=')
    val addr = if (eq > 0) spec.substring(0, eq) else ""
    val sep = addr.lastIndexOf(':')
    val port = addr.substring(sep + 1).toIntOrNull()
    if (eq <= 0 || sep <= 0 || port == null || eq == spec.length - 1) bad("--phone: нужен host:port=ключ, получено «$spec»")
    return StaticPhone(addr.substring(0, sep), port, spec.substring(eq + 1))
}

private fun parseFlags(args: List<String>): Flags {
    val f = Flags()
    val it = args.iterator()
    fun value(name: String) = if (it.hasNext()) it.next() else bad("у $name нет значения")
    while (it.hasNext()) {
        when (val a = it.next()) {
            "--port" -> f.port = value(a).toIntOrNull() ?: bad("--port — число")
            "--line-port" -> f.linePort = value(a).toIntOrNull() ?: bad("--line-port — число")
            "--db" -> f.db = value(a)
            "--test" -> f.test = true
            "--world-pub" -> f.pub = value(a)
            "--seed" -> f.seed = value(a)
            "--phone" -> f.phones += parsePhone(value(a))
            else -> bad("неизвестный аргумент $a")
        }
    }
    return f
}

private fun roleKeys(env: Map<String, String>, test: Boolean): Map<String, String> {
    val keys = listOf("world", "master", "test").mapNotNull { r -> env["NETRUN_KEY_" + r.uppercase()]?.takeIf { it.isNotEmpty() }?.let { r to it } }.toMap()
    if ("world" !in keys || "master" !in keys) bad("нужны NETRUN_KEY_WORLD и NETRUN_KEY_MASTER")
    if (test && "test" !in keys) bad("с --test нужен NETRUN_KEY_TEST")
    return keys
}

internal fun parseLaunch(args: List<String>, env: Map<String, String>): LaunchOptions {
    val f = parseFlags(args)
    val keys = roleKeys(env, f.test)
    if (f.seed != null && !f.test) bad("--seed работает только с --test")
    if (f.phones.isNotEmpty() && !f.test) bad("--phone работает только с --test")
    return LaunchOptions(f.port, f.db, BridgeConfig(port = f.port, roleKeys = keys, testMode = f.test, worldPub = f.pub), f.linePort, f.seed, f.phones)
}

/**
 * Настройки по умолчанию (протокол, раздел 5), создаются при первом старте; мастер правит на ходу. [worldPub] — публичный ключ
 * мира: пишется при создании и обновляется, если ключ сменился (потеряли файл ключа), чтобы дашборд и сервер мира читали актуальный.
 */
internal fun ensureDefaultSettings(store: DocStore, worldPub: String? = null) {
    val cur = store.get(ValueOps.SETTINGS, "global")
    if (cur != null) {
        if (worldPub != null && VJ.str(cur.data, "world_pub") != worldPub) {
            store.put(ValueOps.SETTINGS, "global", cur.ver, VJ.with(cur.data, "world_pub" to VJ.p(worldPub)))
        }
        return
    }
    store.put(
        ValueOps.SETTINGS, "global", 0,
        VJ.obj(
            "confirm_timeout_s" to VJ.p(120L), "inbox_timeout_s" to VJ.p(300L), "disconnect_grace_s" to VJ.p(20L),
            "soft_ice_reentry_pause_s" to VJ.p(600L), "terminal_silent_s" to VJ.p(30L), "auditor_period_s" to VJ.p(60L),
            "tutorial_node" to VJ.p("node_00"), "world_pub" to VJ.p(worldPub),
        ),
    )
}

/** Как часто Мост досылает неподтверждённые карточки выдачи и сверяет `inbox` с тайм-аутом. */
private const val PHONE_TICK_MS = 10_000L

/** Мост целиком: хранилище, API, правила, аудитор и обмен карточками с телефонами. [close] останавливает всё. */
class BridgeApp(private val options: LaunchOptions) : AutoCloseable {
    val store: DocStore = DocStore.open(options.db)
    private val server: BridgeServer
    private val rules: RuleEngine
    private val auditor: Auditor
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val log: KitLog = StderrLog

    /** Ключ мира: создаётся при первом старте, лежит в `<база>.worldkey`. */
    val worldKey: WorldKey = WorldKey.fileFor(options.db)?.let { WorldKey.loadOrCreate(it) { msg -> log.warnEvent("Bridge", "bridge.worldkey_perms", "msg" to msg) } } ?: WorldKey.generate()
    private lateinit var inbox: PhoneInbox
    val phones = PhoneNetwork(worldKey, scope, { inbox.routes() }, options.linePort, log)
    val delivery = PhoneDelivery(store, worldKey, phones, log = log, scope = scope)

    init {
        options.phones.forEach { phones.addStatic(it.key, it.host, it.port) }
        require(options.config.worldPub == null || options.config.worldPub == worldKey.publicB64) {
            "--world-pub не совпадает с ключом мира из файла рядом с базой"
        }
        ensureDefaultSettings(store, worldKey.publicB64)
        ItemDecode.backfill(store) // предметы, принятые до M5b, без daemon/shard
        val ops = ValueOps(store, gateway = delivery)
        inbox = PhoneInbox(store, ops, worldKey, phones, delivery, log = log)
        val master = MasterOps(store)
        server = BridgeServer(store, options.config.copy(worldPub = worldKey.publicB64), ops, master = master)
        rules = RuleEngine(store)
        TerminalSilentRule(rules).register()
        MasterRules(rules, master).register()
        auditor = Auditor(store)
    }

    val port: Int get() = server.port

    fun start() {
        // Сервер строк — до всего остального: адрес Моста для телефонов постоянный и открыт к моменту первой выдачи.
        phones.start()
        server.start()
        rules.start()
        auditor.start()
        // Восстановление после рестарта: PENDING (и DELIVERED без чека) из документов досылаются сразу и затем по таймеру.
        scope.launch {
            while (isActive) {
                runCatching { delivery.flush(); inbox.sweep() }.onFailure { log.warnEvent("Bridge", "bridge.tick_failed", "error" to it.javaClass.simpleName) }
                delay(PHONE_TICK_MS)
            }
        }
    }

    override fun close() {
        scope.cancel()
        auditor.close()
        rules.close()
        phones.close()
        server.stop()
        store.close()
    }
}

fun main(args: Array<String>) {
    val options = try {
        parseLaunch(args.toList(), System.getenv())
    } catch (e: IllegalArgumentException) {
        System.err.println("Мост: ${e.message}\nИспользование: --port N [--line-port N] --db путь.db [--test [--seed файл.json] [--phone host:port=ключ]] [--world-pub КЛЮЧ]; ключи — в окружении")
        exitProcess(2)
    }
    val app = BridgeApp(options)
    options.seed?.let { System.err.println("Мост: из ${it} добавлено документов: ${seedDocs(app.store, java.io.File(it).readText())}") }
    Runtime.getRuntime().addShutdownHook(Thread { app.close() })
    app.start()
    System.err.println("Мост запущен: порт ${app.port}, база ${options.db}${if (options.config.testMode) ", режим --test" else ""}")
    Thread.currentThread().join()
}
