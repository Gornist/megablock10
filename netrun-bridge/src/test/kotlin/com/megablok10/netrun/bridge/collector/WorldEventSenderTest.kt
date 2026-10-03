package com.megablok10.netrun.bridge.collector

import com.megablok10.kit.log.RecordingLog
import com.megablok10.kit.sync.CollectorEndpoint
import com.megablok10.netrun.bridge.collector.FakeCollector.Companion.long
import com.megablok10.netrun.bridge.collector.FakeCollector.Companion.str
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.serialization.json.JsonNull
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.atomic.AtomicLong

/**
 * Отправка быстрых событий ([WorldEventSender]) на настоящий HTTP-сервер [FakeCollector], который принимает `POST /api/world-events` по
 * правилам настоящего коллектора. События собираются вручную: здесь проверяется транспорт (срок жизни, одна повторная попытка, обрыв,
 * очередь, секрет), а откуда события берутся — в [WorldFastEventsTest] и [WorldEventsBridgeTest].
 */
class WorldEventSenderTest {
    private val collector = FakeCollector()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val log = RecordingLog()

    /** «Сейчас» и у Моста, и у коллектора. */
    private val now = AtomicLong(T0)

    /** Короткие паузы: тест ждёт настоящий HTTP, но не настоящие 400 мс между попытками. */
    private val fast = WorldEventConfig(retryDelayMs = 40, connectTimeoutMs = 500, requestTimeoutMs = 2_000, notCapableTtlMs = 0, warnEveryMs = 600_000)

    @After fun tearDown() {
        scope.cancel()
        collector.close()
    }

    private fun sender(config: WorldEventConfig = fast, secret: String? = null, url: String = collector.url): WorldEventSender {
        collector.eventClock = now::get
        return WorldEventSender(CollectorEndpoint(url, secret), now::get, config, log)
    }

    private fun event(n: Int, kind: String = FastKinds.RUN_ENTER, ts: Long = now.get()) =
        FastEvent("e:test:$n:$kind:s_$n", kind, ts, 5_000, "node_07", "t03", "s_$n", if (kind == FastKinds.TRACE_LEVEL) "TRACE" else null)

    private fun await(what: String, timeoutMs: Long = 10_000, cond: () -> Boolean) {
        val until = System.currentTimeMillis() + timeoutMs
        while (!cond()) {
            check(System.currentTimeMillis() < until) { "не дождались: $what (журнал: ${log.all.takeLast(8)})" }
            Thread.sleep(POLL_MS)
        }
    }

    // ---------- доставка ----------

    @Test fun eventReachesTheCollectorWithContractFieldsAndTheGameSecret() {
        val s = sender(secret = "sekret")
        collector.requiredSecret = "sekret"
        s.start(scope)
        s.offer(listOf(event(1, FastKinds.TRACE_LEVEL)))
        await("событие у коллектора") { collector.events.size == 1 }
        val e = collector.events.single()
        assertEquals("e:test:1:trace.level:s_1", e.str("id"))
        assertEquals("trace.level", e.str("kind"))
        assertEquals(T0, e.long("ts"))
        assertEquals(5_000L, e.long("ttl_ms")) // имя поля — с подчёркиванием, как в контракте и в parseWorldEvent
        assertEquals(listOf("node_07", "t03", "s_1", "TRACE"), listOf("node", "terminal", "session", "level").map { e.str(it) })
        assertEquals(listOf("sekret"), collector.eventSecrets.distinct())
        assertEquals(0, collector.changePosts.get()) // события идут мимо /api/changes
        assertEquals(0, s.queued)
    }

    @Test fun nullFieldsAreSentAsJsonNullAndAcceptedAsValid() {
        val s = sender()
        s.start(scope)
        s.offer(listOf(FastEvent("e:test:2:alert.master:al_1", FastKinds.ALERT_MASTER, now.get(), 5_000, null, null, null, null)))
        await("событие у коллектора") { collector.events.size == 1 }
        val e = collector.events.single()
        assertTrue(listOf("node", "terminal", "session", "level").all { e[it] == JsonNull })
        assertEquals(0, collector.eventsInvalid.get())
    }

    @Test fun everyOfTheSevenKindsPassesTheCollectorsValidation() {
        val s = sender()
        s.start(scope)
        s.offer(FastKinds.ALL.mapIndexed { i, kind -> event(i, kind) })
        await("все виды у коллектора") { collector.events.size == FastKinds.ALL.size }
        assertEquals(FastKinds.ALL.sorted(), collector.eventKinds().sorted())
        assertEquals(0, collector.eventsInvalid.get())
        assertEquals(0, collector.eventsExpired.get())
    }

    @Test fun capabilityIsAskedBeforeSendingAndRememberedWhileItIsPositive() {
        val s = sender()
        s.start(scope)
        s.offer(listOf(event(1)))
        await("первое событие") { collector.events.size == 1 }
        s.offer(listOf(event(2)))
        await("второе событие") { collector.events.size == 2 }
        assertEquals(1, collector.capabilityGets.get())
        assertEquals(2, collector.eventPosts.get())
    }

    @Test fun collectorThatDoesNotAnnounceWorldEventsGetsNothing() {
        val s = sender()
        s.start(scope)
        for ((i, caps) in listOf(null, """{"world_records":1}""", """{"world_events":0}""", """{"world_events":2}""").withIndex()) {
            collector.capabilities = caps // 404, поле не объявлено, не поддерживается, формат новее нашего
            s.offer(listOf(event(i)))
            await("проверка возможностей для случая $i") { collector.capabilityGets.get() > i }
            await("событие забыто в случае $i") { s.queued == 0 }
        }
        assertEquals(0, collector.eventPosts.get())
        assertTrue(log.has("world_events.not_supported"))
        collector.capabilities = """{"world_records":1,"world_events":1}"""
        s.offer(listOf(event(9)))
        await("после объявления возможностей") { collector.events.size == 1 }
        assertEquals("e:test:9:run.enter:s_9", collector.events.single().str("id")) // из прежних не догнано ни одно
    }

    @Test fun batchesAreAtMostFiftyAndEverythingArrives() {
        val s = sender(fast.copy(queueCapacity = 200))
        s.offer((1..120).map { event(it) }) // до старта: всё лежит в очереди и уходит пачками
        s.start(scope)
        await("все 120") { collector.events.size == 120 }
        assertTrue(collector.eventPosts.get() >= 3) // коллектор отвечает 400 на пачку больше 50: если бы Мост слал всё разом, не дошло бы ничего
        assertEquals(0, collector.eventsInvalid.get())
    }

    // ---------- срок жизни ----------

    @Test fun expiredEventIsNeverSentButTheFreshOneInTheSameBatchIs() {
        val s = sender()
        s.start(scope)
        s.offer(listOf(event(1, ts = now.get() - 6_000), event(2), event(3, ts = now.get() - 5_000))) // просрочено, свежее, ровно на границе срока
        await("свежие у коллектора") { collector.events.size == 2 }
        assertEquals(listOf("e:test:2:run.enter:s_2", "e:test:3:run.enter:s_3"), collector.events.map { it.str("id") })
        assertEquals(0, collector.eventsExpired.get()) // просроченное до коллектора не дошло вовсе
        assertTrue(log.has("world_events.expired"))
    }

    @Test fun eventThatExpiresWhileWaitingForTheRetryIsNotResent() {
        val s = sender(fast.copy(retryDelayMs = 1_500))
        collector.failEventPosts.set(1)
        s.start(scope)
        s.offer(listOf(event(1)))
        await("первая попытка") { collector.eventPosts.get() == 1 }
        now.addAndGet(10_000) // пока Мост ждёт перед повтором, срок вышел
        await("событие забыто") { log.has("world_events.expired") }
        Thread.sleep(SETTLE_MS)
        assertEquals(1, collector.eventPosts.get())
        assertEquals(0, collector.events.size)
        assertEquals(0, s.queued)
    }

    // ---------- повтор и обрыв ----------

    @Test fun oneRetryThenForgetAndNothingIsCaughtUpLater() {
        val s = sender()
        collector.failEventPosts.set(10) // коллектор отвечает 503 и на попытку, и на повтор
        s.start(scope)
        s.offer(listOf(event(1)))
        await("попытка и повтор") { collector.eventPosts.get() == 2 }
        await("забыто") { log.has("world_events.http_error") }
        Thread.sleep(SETTLE_MS)
        assertEquals(2, collector.eventPosts.get()) // ровно две отправки: ни третьей, ни по таймеру
        assertEquals(0, s.queued)
        assertTrue(log.all.toString(), log.all.any { "world_events.http_error" in it && "code=503" in it && "dropped=1" in it })
        collector.failEventPosts.set(0)
        s.offer(listOf(event(2)))
        await("новое событие") { collector.events.size == 1 }
        assertEquals(listOf("e:test:2:run.enter:s_2"), collector.events.map { it.str("id") }) // первое так и не пришло
    }

    @Test fun retrySucceedsAndKeepsTheSameId() {
        val s = sender()
        collector.failEventPosts.set(1)
        s.start(scope)
        s.offer(listOf(event(1)))
        await("со второй попытки") { collector.events.size == 1 }
        assertEquals(2, collector.eventPosts.get())
        assertEquals(0, s.queued)
        assertTrue(!log.has("world_events.http_error")) // повтор удался: предупреждать не о чем
    }

    @Test fun lostResponseIsRetriedWithTheSameIdAndCollectorDoesNotSoundTwice() {
        val s = sender()
        collector.dropNextEventResponse = true // коллектор принял событие, но ответ до Моста не дошёл
        s.start(scope)
        s.offer(listOf(event(1)))
        await("повтор принят как дубль") { collector.eventsDuplicate.get() == 1 }
        assertEquals(1, collector.events.size)
        assertEquals(listOf("e:test:1:run.enter:s_1", "e:test:1:run.enter:s_1"), collector.eventIdsSent.toList())
    }

    @Test fun unreachableCollectorLeavesNoQueueAndWarnsOnceWithoutTheSecret() {
        val url = "http://127.0.0.1:${java.net.ServerSocket(0).use { it.localPort }}" // порт, на котором никого нет: соединение отказано
        val s = sender(secret = "Sekret-QQMARKER", url = url)
        s.start(scope)
        for (round in 1..3) {
            s.offer(listOf(event(round * 10), event(round * 10 + 1)))
            await("раунд $round обработан") { s.queued == 0 && log.all.count { "world_events.unreachable" in it } >= 1 }
            Thread.sleep(SETTLE_MS)
        }
        assertEquals(0, s.queued) // ничего не копится и не догоняется
        val warns = log.all.filter { "world_events.unreachable" in it }
        assertEquals(warns.toString(), 1, warns.size) // раз в warnEveryMs, а не на каждое событие
        assertTrue(warns.single().startsWith("W/WorldEvents "))
        assertTrue(warns.single(), url in warns.single() && "dropped=" in warns.single())
        assertTrue(log.all.toString(), log.all.none { "QQMARKER" in it })
    }

    @Test fun connectionLostInsideThePostIsRetriedOnceAndLogsNoSecret() {
        val s = sender(secret = "Sekret-QQMARKER")
        collector.dropEventResponses.set(10) // запрос доходит, ответ — нет: обрыв внутри POST, а не при проверке возможностей
        s.start(scope)
        s.offer(listOf(event(1)))
        await("попытка и повтор") { collector.eventPosts.get() == 2 }
        await("забыто") { log.has("world_events.unreachable") }
        Thread.sleep(SETTLE_MS)
        assertEquals(2, collector.eventPosts.get())
        assertEquals(0, s.queued)
        assertEquals(1, collector.events.size) // коллектор событие принял (ответ потерян), повтор для него — дубль
        assertEquals(1, collector.eventsDuplicate.get())
        val warn = log.all.single { "world_events.unreachable" in it }
        assertTrue(warn, "error=" in warn && "dropped=1" in warn)
        assertTrue(log.all.toString(), log.all.none { "QQMARKER" in it })
    }

    @Test fun repeatedWarningsCarryTheNumberOfSuppressedOnes() {
        val s = sender(fast.copy(warnEveryMs = WARN_WINDOW_MS))
        collector.failEventPosts.set(1_000)
        s.start(scope)
        s.offer(listOf(event(1)))
        await("первое предупреждение") { log.has("world_events.http_error") }
        s.offer(listOf(event(2)))
        await("событие 2 обработано") { collector.eventPosts.get() >= 4 }
        assertEquals(1, log.all.count { "world_events.http_error" in it }) // второе внутри окна: в журнал не попало
        Thread.sleep(WARN_WINDOW_MS + SETTLE_MS) // окно предупреждений прошло
        s.offer(listOf(event(3)))
        await("предупреждение с числом пропущенных") { log.all.any { "world_events.http_error" in it && "suppressed=1" in it } }
    }

    // ---------- переполнение очереди ----------

    @Test fun overflowDropsTheOldestAndKeepsTheNewest() {
        val s = sender(fast.copy(queueCapacity = 3))
        s.offer((1..7).map { event(it) }) // отправка ещё не запущена
        assertEquals(3, s.queued)
        assertTrue(log.all.toString(), log.all.any { "world_events.overflow" in it && "dropped=4" in it && "capacity=3" in it })
        s.start(scope)
        await("три свежих") { collector.events.size == 3 }
        assertEquals((5..7).map { "e:test:$it:run.enter:s_$it" }, collector.events.map { it.str("id") })
    }

    @Test fun offerNeverBlocksEvenWhenTheCollectorHangs() {
        val s = sender(fast.copy(requestTimeoutMs = 3_000))
        collector.eventDelayMs = 2_500
        s.start(scope)
        s.offer(listOf(event(1)))
        await("запрос завис у коллектора") { collector.eventPosts.get() == 1 }
        val t0 = System.nanoTime()
        repeat(50) { s.offer(listOf(event(100 + it))) } // отправка занята: offer только кладёт в очередь
        val ms = (System.nanoTime() - t0) / NS_IN_MS
        assertTrue("offer занял $ms мс", ms < 500)
        assertTrue(s.queued in 1..50)
    }

    // ---------- секрет ----------

    @Test fun wrongGameSecretIsNotRetriedAndNeverShownInTheLog() {
        collector.requiredSecret = "right-secret"
        val s = sender(secret = "WrongSecret-QQMARKER")
        s.start(scope)
        s.offer(listOf(event(1)))
        await("отказ записан") { log.has("world_events.http_error") }
        Thread.sleep(SETTLE_MS)
        assertEquals(1, collector.eventPosts.get()) // 401 за 0.4 с не пройдёт: повтора нет
        assertEquals(0, collector.events.size)
        assertTrue(log.all.any { "code=401" in it })
        assertTrue(log.all.toString(), log.all.none { "QQMARKER" in it || "right-secret" in it })
    }

    @Test fun secretThatCannotBeAHeaderNeverReachesTheLogOrTheNetwork() {
        val s = sender(secret = "СЕКРЕТ\nQQMARKER")
        s.start(scope)
        s.offer(listOf(event(1)))
        await("отказ записан") { log.has("world_events.bad_secret") }
        assertEquals(0, collector.eventPosts.get())
        assertEquals(0, collector.capabilityGets.get())
        assertTrue(log.all.toString(), log.all.none { "QQMARKER" in it || "СЕКРЕТ" in it })
    }

    @Test fun brokenCollectorAddressDoesNotKillTheSendLoop() {
        val s = sender(fast.copy(warnEveryMs = 0), url = "http://bad host:1") // адрес, который JDK не разберёт: исключение изнутри отправки
        s.start(scope)
        s.offer(listOf(event(1)))
        await("сбой записан") { log.has("world_events.failed") }
        s.offer(listOf(event(2)))
        await("цикл жив и разобрал второе событие") { log.all.count { "world_events.failed" in it } == 2 }
        assertEquals(0, s.queued)
        assertEquals(0, collector.eventPosts.get())
    }

    @Test fun encodeKeepsExactlyTheFieldsOfTheContract() {
        val body = WorldEventSender.encode(listOf(event(1, FastKinds.TRACE_LEVEL))).toString()
        assertEquals(
            """{"events":[{"id":"e:test:1:trace.level:s_1","kind":"trace.level","ts":$T0,"ttl_ms":5000,"node":"node_07","terminal":"t03","session":"s_1","level":"TRACE"}]}""",
            body,
        )
    }

    private companion object {
        const val T0 = 1_790_000_000_000L
        const val POLL_MS = 10L
        const val SETTLE_MS = 300L
        const val NS_IN_MS = 1_000_000L
        const val WARN_WINDOW_MS = 800L
    }
}
