package com.megablok10.netrun.bridge.collector

import com.megablok10.kit.log.KitLog
import com.megablok10.kit.log.NoopLog
import com.megablok10.kit.sync.ChangeRecord
import com.megablok10.kit.sync.CollectorEndpoint
import com.megablok10.kit.sync.CollectorTransport
import com.megablok10.kit.sync.MasterApply
import com.megablok10.kit.sync.SyncConfig
import com.megablok10.kit.sync.SyncEngine
import com.megablok10.kit.sync.SyncHooks
import com.megablok10.kit.time.Clock
import com.megablok10.netrun.bridge.DocStore
import com.megablok10.netrun.bridge.phone.WorldKey
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import java.net.http.HttpClient

/**
 * Записи мира для коллектора (docs/netrun-world-records.md, M4): запись в очередь и отправка.
 *
 * Запись идёт всегда, даже когда коллектор не задан или недоступен: [WorldRecorder] подписывает события мира ключом мира и кладёт их
 * в [queue] (SQLite Моста) в той же транзакции, что и документы. Отправляет `SyncEngine` ([start]) — только если задан [collector];
 * очередь дождётся его появления, переживёт рестарт Моста, а `id` записи детерминирован, поэтому повтор отправки не плодит дублей.
 * Создавать до первой записи в [store]: конструктор ставит расширение коммита.
 *
 * Быстрые события на точки площадки (раздел 3 контракта, L3) выводятся в той же точке, но идут мимо очереди: [WorldEventSender] шлёт их
 * `POST /api/world-events` из памяти и ничего не копит. Включаются тем же [collector] (флаг `--collector`, секрет `NETRUN_COLLECTOR_SECRET`);
 * без коллектора события не выводятся.
 */
class WorldSync(
    store: DocStore,
    key: WorldKey,
    private val collector: CollectorEndpoint?,
    private val scope: CoroutineScope,
    transport: CollectorTransport? = null,
    clock: Clock = Clock.System,
    private val log: KitLog = NoopLog,
    config: SyncConfig = SyncConfig(),
    eventConfig: WorldEventConfig = WorldEventConfig(),
    eventHttp: HttpClient? = null,
) {
    val queue = WorldRecordQueue(store, clock::nowMs)
    private val events: WorldEventSender? = collector?.let { WorldEventSender(it, clock::nowMs, eventConfig, log, eventHttp) }
    private val recorder = WorldRecorder(queue, key, store.epoch, log, events?.let { it::offer })
    private val engine = SyncEngine(
        queue = queue,
        transport = transport ?: WorldCollectorTransport(clock = clock::nowMs, log = log),
        endpoint = { collector },
        subjectKey = { key.publicB64 },
        presence = { stats -> mapOf("pendingCount" to stats.pendingCount, "oldestPendingAgeMs" to stats.oldestPendingAgeMs) },
        hooks = WorldSyncHooks,
        clock = clock,
        log = log,
        tag = WorldCollectorTransport.TAG,
        config = config,
    )

    init {
        store.commitHook = recorder
        // Слушатели хранилища зовутся после COMMIT: запись уже видна очереди, значит отправку можно будить.
        store.addListener { recorder.committed(engine::wake) }
    }

    /** Итог последней попытки синка одной строкой (для диагностики). */
    val lastSummary: String get() = engine.lastSummary

    /** Быстрых событий в памяти ждёт отправки (для тестов); без коллектора всегда 0. */
    val eventsQueued: Int get() = events?.queued ?: 0

    /** Запустить отправку записей и быстрых событий; без коллектора ничего не делает (записи копятся в [queue], события не выводятся). */
    fun start(): Job? {
        if (collector == null) return null
        events?.start(scope)
        return scope.launch { engine.run() }
    }

    /** Мост не принимает правки мастера: ключ мира не игрок. Случайная правка уходит отказом без повтора и видна мастеру. */
    private object WorldSyncHooks : SyncHooks {
        override suspend fun applyMasterChange(change: ChangeRecord): MasterApply =
            MasterApply.Failed("Мост не принимает правки мастера", permanent = true)
    }
}
