package com.megablok10.app.breach

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import com.megablok10.app.log.Mb10Log
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.style.TextOverflow
import com.megablok10.app.DebugConfig
import com.megablok10.app.identity.Identity
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.sound.BreachCue
import com.megablok10.app.sound.BreachSfx
import com.megablok10.app.ui.theme.LocalMbColors
import com.megablok10.app.ui.theme.MbBreadcrumb
import com.megablok10.app.ui.theme.MbBuffer
import com.megablok10.app.ui.theme.MbButton
import com.megablok10.app.ui.theme.MbColorsBreach
import com.megablok10.app.ui.theme.MbDimens
import com.megablok10.app.ui.theme.MbIconButton
import com.megablok10.app.ui.theme.MbIcons
import com.megablok10.app.ui.theme.MbListItem
import com.megablok10.app.ui.theme.MbLog
import com.megablok10.app.ui.theme.MbPanel
import com.megablok10.app.ui.theme.MbProgress
import com.megablok10.app.ui.theme.MbTag
import com.megablok10.app.ui.theme.MbTimer
import com.megablok10.app.ui.theme.MbTypography
import com.megablok10.rules.BreachConstants
import com.megablok10.rules.generateGrid
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.roundToInt
import kotlin.random.Random

/**
 * Взлом недоступен, пока не отсканирована QR-метка конкретного контейнера
 * (его печатают мастера на месте, либо это старая "точка доступа" — читается
 * как контейнер тира BASE без лута, см. Mb10Qr.kt). Сама точка входа для
 * скана — общая кнопка "Сканировать объект" на экране Кибердеки — этот
 * композабл только показывает сессию взлома, когда контейнер уже выбран.
 *
 * Тема Breach (лайм) на весь поток — раздел 5 гайдлайна: экран взлома рисуется теми же компонентами, что остальное
 * приложение, только с подменой токенов через LocalMbColors.
 */
@Composable
internal fun BreachContainerFlow(
    container: Container,
    daemons: List<Daemon>,
    identity: Identity,
    onRescan: () -> Unit,
    onImmersive: (Boolean) -> Unit = {},
    isHintSeen: () -> Boolean,
    onHintSeen: () -> Unit,
    /** Итог взлома — награда и прочее (BreachViewModel → сценарий FinishBreach); onDone получает награду для итогового экрана. */
    finish: (result: BreachResult, seed: Long, onDone: (RewardOutcome) -> Unit) -> Unit,
) {
    var chosen by remember(container.id) { mutableStateOf<Set<String>>(emptySet()) }
    var sessionSeed by remember(container.id) { mutableStateOf<Long?>(null) }
    var rewardOutcome by remember(container.id) { mutableStateOf<RewardOutcome?>(null) }
    var secAlertStatus by remember(container.id) { mutableStateOf<String?>(null) }
    var running by remember(container.id) { mutableStateOf(false) }

    // Пока идёт таймер, шапка и нижняя навигация приложения прячутся: взлом получает весь экран.
    LaunchedEffect(running) { onImmersive(running) }
    DisposableEffect(Unit) { onDispose { onImmersive(false) } }

    val chosenDaemons = daemons.filter { it.id in chosen }
    val used = chosenDaemons.sumOf { it.sequence.size }
    val overBudget = used > identity.ramCapacity
    val canStart = chosenDaemons.isNotEmpty() && !overBudget
    val params = remember(container.tier) { BreachTierParams.forTier(container.tier) }
    val timerBonus = if (chosenDaemons.any { it.effect == DaemonEffect.JITTER }) BreachConstants.JITTER_BONUS_SEC else 0

    CompositionLocalProvider(LocalMbColors provides MbColorsBreach) {
        val seed = sessionSeed
        if (seed != null) {
            Box(Modifier.fillMaxSize().padding(horizontal = MbDimens.screenPadding)) {
                BreachSession(
                    tier = container.tier,
                    title = "${container.name} · ${container.tier.label}",
                    daemons = chosenDaemons,
                    seed = seed,
                    gridSize = params.gridSize,
                    timerSec = DebugConfig.scaledTimerSec(params.timerSec + timerBonus),
                    bufferSize = identity.ramCapacity,
                    breachParams = params,
                    onRescan = onRescan,
                    isHintSeen = isHintSeen,
                    onHintSeen = onHintSeen,
                    rescanLabel = "Новый контейнер",
                    failMessage = "СБ зафиксировала попытку. Контейнер заблокирован до конца этого акта.",
                    rewardOutcome = rewardOutcome,
                    secAlertStatus = secAlertStatus,
                    onRunningChange = { running = it },
                    onResult = { result ->
                        finish(result, seed) { outcome ->
                            rewardOutcome = outcome
                            secAlertStatus = secAlertStatusText(container, identity, result.outcome, outcome.matchedEffects)
                        }
                    }
                )
            }
            return@CompositionLocalProvider
        }

        // Список демонов скроллится в своей области (weight), а буфер (сверху) и кнопка старта (снизу) закреплены вне скролла.
        Column(Modifier.fillMaxSize().padding(horizontal = MbDimens.screenPadding)) {
            ContainerHeader(container, onCancel = onRescan)

            // Размер буфера и его заполнение — сверху, закреплено: видно, сколько места остаётся, пока выбираешь демонов ниже по списку.
            val pickedCodes = chosen.mapNotNull { id -> daemons.find { it.id == id } }.flatMap { it.sequence }
            MbPanel("Буфер", meta = "${pickedCodes.size} / ${identity.ramCapacity}" + if (overBudget) " — снимите демон" else "") {
                MbBuffer(codes = pickedCodes, size = identity.ramCapacity)
            }
            Spacer(Modifier.height(MbDimens.blockGap))

            Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
                DaemonPicker(
                    daemons = daemons,
                    chosen = chosen,
                    remainingBuffer = identity.ramCapacity - used,
                    onToggle = { id -> chosen = if (id in chosen) chosen - id else chosen + id }
                )
            }

            Spacer(Modifier.height(MbDimens.blockGap))
            MbButton("Взломать контейнер", onClick = { sessionSeed = System.nanoTime() }, enabled = canStart, keyIcon = MbIcons.Hack)
        }
    }
}

@Composable
private fun ContainerHeader(container: Container, onCancel: () -> Unit) {
    MbBreadcrumb(parts = listOf("Кибердека", "${container.name} · ${container.tier.label}"), icon = MbIcons.Hack) {
        MbIconButton(MbIcons.Close, "Отмена", onCancel)
    }
}

/**
 * Что написать в строке "Сигнал СБ" на экране результата — те же правила
 * гейтинга, что у SecAlertStore.decide (свой контейнер/FAIL на BASE — сигнала
 * не было вовсе, тогда и строки нет), но здесь только для отображения: сам
 * сигнал уже поставлен в очередь отдельным вызовом SecAlertStore.dispatch.
 */
private fun secAlertStatusText(container: Container, identity: Identity, outcome: BreachOutcome, matchedEffects: Set<DaemonEffect>): String? {
    if (container.ownerFaction.isBlank() || container.ownerFaction == identity.faction) return null
    if (outcome == BreachOutcome.FAIL && container.tier == Tier.BASE) return null
    return if (DaemonEffect.BLACKOUT in matchedEffects) "подавлен (Blackout)" else "отправлен фракции «${container.ownerFaction}»"
}

/**
 * Мини-взлом одного зашифрованного шарда — тот же движок Breach Protocol
 * (BreachSession), что и у контейнера, но без выбора демонов: цель ровно
 * одна, детерминированно выведенная из id шарда (shardDecryptTarget).
 * Вызывается из CyberdeckScreen поверх ShardDetailDialog.
 */
@Composable
internal fun ShardDecryptFlow(shard: Mb10Qr.Shard, isHintSeen: () -> Boolean, onHintSeen: () -> Unit, onDecrypted: () -> Unit, onCancel: () -> Unit) {
    val target = remember(shard.id) { shardDecryptTarget(shard) }
    val sessionSeed = remember(shard.id) { System.nanoTime() }
    val params = remember(shard.tier) { BreachTierParams.forTier(Tier.fromLevel(shard.tier)) }

    CompositionLocalProvider(LocalMbColors provides MbColorsBreach) {
        Box(Modifier.fillMaxSize().padding(horizontal = MbDimens.screenPadding)) {
            BreachSession(
                tier = Tier.fromLevel(shard.tier),
                title = "Шифр-замок: ${shard.title}",
                daemons = listOf(target),
                seed = sessionSeed,
                gridSize = params.gridSize,
                timerSec = params.cipherTimerSec,
                bufferSize = target.sequence.size + BreachConstants.DECRYPT_BUFFER_EXTRA,
                breachParams = null,
                onRescan = onCancel,
                isHintSeen = isHintSeen,
                onHintSeen = onHintSeen,
                rescanLabel = "Отмена",
                failMessage = "Шифр-замок устоял. Шард остаётся зашифрован — можно попробовать ещё раз.",
                onResult = { result -> if (result.outcome == BreachOutcome.SUCCESS) onDecrypted() }
            )
        }
    }
}

private fun shardDecryptTarget(shard: Mb10Qr.Shard): Daemon {
    val random = Random(shard.id.hashCode().toLong())
    val length = MockBreach.shardDecryptTargetLength.getOrElse(shard.tier - 1) { 3 }
    val sequence = List(length) { BreachSymbols.ALPHABET.random(random) }
    return Daemon(id = "shard-decrypt:${shard.id}", name = "Шифр-замок", sequence = sequence)
}

/**
 * remainingBuffer — сколько буфера осталось ПОСЛЕ уже выбранных демонов (см. BreachContainerFlow). Демон, который в него не влезает,
 * показан приглушённым и с явной причиной ("не влезает в буфер") вместо своего эффекта, а не кликабелен. Уже выбранного демона это
 * не касается: снять его можно всегда, его вес уже учтён в remainingBuffer.
 */
@Composable
internal fun DaemonPicker(daemons: List<Daemon>, chosen: Set<String>, remainingBuffer: Int, onToggle: (String) -> Unit) {
    val c = LocalMbColors.current
    Column {
        daemons.forEach { daemon ->
            val isChecked = daemon.id in chosen
            val fitsBuffer = isChecked || daemon.sequence.size <= remainingBuffer
            MbListItem(
                title = "${daemon.name} · ${daemon.tier.label}",
                sub = if (fitsBuffer) daemon.effect.label() else "не влезает в буфер",
                subWrap = true,
                trail = listOfNotNull(
                    { Text(daemon.sequence.joinToString(" "), style = MbTypography.demonCode, color = if (isChecked) c.acc else c.ink2) },
                    if (isChecked) { { MbTag("в буфере", filled = true) } } else null
                ),
                plate = true,
                state = if (!fitsBuffer) com.megablok10.app.ui.theme.MbListItemState.Off else com.megablok10.app.ui.theme.MbListItemState.Normal,
                onClick = if (fitsBuffer) { { onToggle(daemon.id) } } else null
            )
        }
    }
}

/**
 * Владеет одной попыткой целиком: тикающим таймером и результатом, если он уже наступил. `remember(seed)` — попытка живёт, пока
 * seed (задаётся при каждом старте) не меняется. Ход попытки — [BreachRun]; здесь только то, что касается экрана: звук, хаптик,
 * журнал, реплики защиты и автосолвер. Всё помещается на один экран без прокрутки: размер ячеек считается из доступной
 * высоты, а не только ширины. Итог показывается оверлеем поверх экрана (сетка и буфер остаются под ним в финальном виде).
 * breachParams — если не null, задаёт мёртвые клетки/порченые коды (см. generateGrid); у ShardDecryptFlow ловушек нет вовсе.
 */
@Composable
private fun BreachSession(
    tier: Tier,
    title: String,
    daemons: List<Daemon>,
    seed: Long,
    gridSize: Int,
    timerSec: Int,
    bufferSize: Int,
    breachParams: BreachParams?,
    onRescan: () -> Unit,
    isHintSeen: () -> Boolean,
    onHintSeen: () -> Unit,
    rescanLabel: String = "Новый контейнер",
    failMessage: String = "СБ зафиксировала попытку. Контейнер заблокирован до конца этого акта.",
    rewardOutcome: RewardOutcome? = null,
    secAlertStatus: String? = null,
    onRunningChange: (Boolean) -> Unit = {},
    onResult: (BreachResult) -> Unit = {}
) {
    val c = LocalMbColors.current
    val grid = remember(seed) { generateGrid(gridSize, daemons, Random(seed), breachParams) }
    val breachId = remember(seed) { "MB10-VENT-" + seed.toString(16).takeLast(4).uppercase() }

    var run by remember(seed) { mutableStateOf(BreachRun(BreachAttemptState(grid, daemons, bufferSize), timerSec)) }
    val context = LocalContext.current
    val haptic = LocalHapticFeedback.current
    val scope = rememberCoroutineScope()
    // Вступительный «вход в узел» — только в живой игре: автосолвер (debug-прогоны) стартует сразу.
    var booted by remember(seed) { mutableStateOf(DebugConfig.autoSolve && DebugConfig.autoSolveStepMs == 0L) }
    val shake = remember(seed) { Animatable(0f) }
    // Реплика защиты узла (см. IceLines) — одна строка над сеткой, обновляется по событиям взлома.
    var iceLine by remember(seed) { mutableStateOf<String?>(null) }
    var hintSeen by remember(seed) { mutableStateOf(DebugConfig.autoSolve || isHintSeen()) }
    fun ice(event: IceEvent) { iceLine = IceLines.line(tier, event, Random(seed xor event.ordinal.toLong())) }

    LaunchedEffect(run.isFinished) { onRunningChange(!run.isFinished) }

    fun resolveOnce() {
        if (run.isFinished) return
        run = run.resolve()
        val resolved = checkNotNull(run.result)
        Mb10Log.event("Breach", "breach.result", "id" to breachId, "title" to title, "tier" to tier.name, "outcome" to resolved.outcome.name, "matched" to run.attempt.matchedDaemonIds.size, "daemons" to run.attempt.daemons.size, "secondsLeft" to run.secondsLeft, "of" to timerSec)
        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
        BreachSfx.play(context, when (resolved.outcome) {
            BreachOutcome.SUCCESS -> BreachCue.SUCCESS
            BreachOutcome.PARTIAL -> BreachCue.PARTIAL
            BreachOutcome.FAIL -> BreachCue.FAIL
        })
        onResult(resolved)
    }

    LaunchedEffect(seed) {
        Mb10Log.event("Breach", "breach.start", "id" to breachId, "title" to title, "tier" to tier.name, "grid" to gridSize, "timerSec" to timerSec, "buffer" to bufferSize, "daemons" to daemons.size, "autoSolve" to DebugConfig.autoSolve)
        if (!booted) {
            BreachSfx.play(context, BreachCue.ENTER)
            delay(BOOT_LINE_MS * BOOT_LINES)
            booted = true
            ice(IceEvent.INTRO)
        }
        if (DebugConfig.autoSolve) {
            val step = DebugConfig.autoSolveStepMs
            for (cell in BreachAutoSolver.solve(run.attempt)) {
                if (step > 0) {
                    delay(step)
                    val tap = run.tap(cell)
                    run = tap.run
                    BreachSfx.play(context, if (tap.hitTrap) BreachCue.TRAP else if (tap.matched) BreachCue.MATCH else BreachCue.TAP)
                    if (tap.matched) ice(IceEvent.MATCH)
                } else run = run.tap(cell).run
            }
            if (run.attempt.selected.isNotEmpty()) resolveOnce()
        }
        while (run.isTicking) {
            delay(1000)
            run = run.tick()
            if (run.isWarning) BreachSfx.play(context, BreachCue.WARN)
            run.timeEvent?.let(::ice)
        }
        resolveOnce()
    }

    fun onCell(at: Pair<Int, Int>) {
        if (!hintSeen) { hintSeen = true; onHintSeen() }
        val tap = run.tap(at)
        run = tap.run
        when {
            tap.hitTrap -> {
                haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                BreachSfx.play(context, BreachCue.TRAP)
                ice(IceEvent.TRAP)
                scope.launch {
                    repeat(3) { shake.animateTo(if (it % 2 == 0) 9f else -9f, tween(40)) }
                    shake.animateTo(0f, tween(40))
                }
            }
            tap.matched -> { haptic.performHapticFeedback(HapticFeedbackType.LongPress); BreachSfx.play(context, BreachCue.MATCH); ice(IceEvent.MATCH) }
            else -> { haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove); BreachSfx.play(context, BreachCue.TAP) }
        }
        if (run.attempt.isFull) resolveOnce()
    }

    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
            val urgent = run.isLowTime && booted
            val blink by rememberInfiniteTransition(label = "timerBlink").animateFloat(
                initialValue = 0f, targetValue = 1f,
                animationSpec = infiniteRepeatable(tween(450, easing = LinearEasing), RepeatMode.Reverse), label = "blink"
            )
            val timerColor = if (urgent) lerp(c.acc, c.bad, blink) else c.acc

            MbTimer(label = title, time = if (booted) formatTime(run.secondsLeft) else "--:--", timeColor = timerColor) {
                MbIconButton(MbIcons.Close, "Выйти из взлома ($rescanLabel)", onRescan)
            }

            if (!booted) {
                Spacer(Modifier.height(MbDimens.blockGap))
                BootLog(breachId, bufferSize)
                return@Column
            }

            Spacer(Modifier.height(MbDimens.rowGap))
            MbProgress((run.secondsLeft.toFloat() / timerSec * 100).roundToInt())

            // Строка-статус фиксированной высоты (одна строка), чтобы сетка не «прыгала» при смене реплик.
            val statusText = iceLine ?: if (!hintSeen && run.attempt.selected.isEmpty()) "Цепочка: строка → столбец → строка… Соберите коды демонов до нуля." else ""
            if (statusText.isNotEmpty()) {
                Text(
                    statusText, color = if (iceLine != null) c.bad else c.ink2, style = MbTypography.meta, minLines = 1, maxLines = 1,
                    overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = MbDimens.rowGap)
                )
            }

            Spacer(Modifier.height(MbDimens.blockGap))
            MbPanel("Буфер", meta = "${run.attempt.bufferCodes.size} / ${run.attempt.bufferSize}") {
                MbBuffer(codes = run.attempt.bufferCodes, size = run.attempt.bufferSize)
            }

            Spacer(Modifier.height(MbDimens.blockGap))
            MbPanel("Матрица кодов", meta = "${run.attempt.grid.size}×${run.attempt.grid.size}") {
                BreachMatrix(run, shake, ::onCell)
            }

            Spacer(Modifier.height(MbDimens.blockGap))
            MbPanel("Последовательности", meta = "${run.attempt.daemons.size}") {
                BreachSequences(run.attempt)
            }

            if (!run.isFinished) {
                Spacer(Modifier.height(MbDimens.blockGap))
                // Не "отмена без последствий" — сдаёт текущий буфер на резолв досрочно, так же как истечение таймера.
                MbButton("Сдать буфер", onClick = { resolveOnce() })
            }
        }

        run.result?.let { ResultOverlay(it, failMessage, rewardOutcome, secAlertStatus, actionLabel = rescanLabel, onAction = onRescan) }
    }
}

private fun formatTime(totalSeconds: Int): String {
    val s = totalSeconds.coerceAtLeast(0)
    return "${(s / 60).toString().padStart(2, '0')}:${(s % 60).toString().padStart(2, '0')}"
}

private const val BOOT_LINES = 4
private const val BOOT_LINE_MS = 350L

/** Вступление «вход в узел»: строки лога проявляются по одной, пока в фоне не истечёт [BOOT_LINES]×[BOOT_LINE_MS]. */
@Composable
private fun BootLog(breachId: String, bufferSize: Int) {
    val lines = listOf(
        "> подключение к $breachId…",
        "> обход контура ICE…",
        "> буфер: $bufferSize ячеек",
        "> доступ получен",
    )
    var shown by remember { mutableIntStateOf(0) }
    LaunchedEffect(Unit) {
        while (shown < lines.size) {
            delay(BOOT_LINE_MS)
            shown += 1
        }
    }
    MbPanel("Вход в узел") {
        MbLog(lines.take(shown))
    }
}
