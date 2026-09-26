package com.megablok10.app.breach

import android.content.Context
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import com.megablok10.app.log.Mb10Log
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.megablok10.app.DebugConfig
import com.megablok10.app.identity.Identity
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.sound.BreachCue
import com.megablok10.app.sound.BreachSfx
import com.megablok10.app.ui.theme.LocalMbColors
import com.megablok10.app.ui.theme.MbBreadcrumb
import com.megablok10.app.ui.theme.MbBuffer
import com.megablok10.app.ui.theme.MbButton
import com.megablok10.app.ui.theme.MbChamferForm
import com.megablok10.app.ui.theme.MbColorsBreach
import com.megablok10.app.ui.theme.MbColorsSuccess
import com.megablok10.app.ui.theme.MbDimens
import com.megablok10.app.ui.theme.MbDone
import com.megablok10.app.ui.theme.MbIconButton
import com.megablok10.app.ui.theme.MbIcons
import com.megablok10.app.ui.theme.MbListItem
import com.megablok10.app.ui.theme.MbLog
import com.megablok10.app.ui.theme.MbPanel
import com.megablok10.app.ui.theme.MbProgress
import com.megablok10.app.ui.theme.MbTag
import com.megablok10.app.ui.theme.MbTagTone
import com.megablok10.app.ui.theme.MbTimer
import com.megablok10.app.ui.theme.MbTypography
import com.megablok10.app.ui.theme.formatMoney
import com.megablok10.app.ui.theme.mbFrame
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
    val timerBonus = if (chosenDaemons.any { it.effect == DaemonEffect.JITTER }) 15 else 0

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
internal fun ShardDecryptFlow(shard: Mb10Qr.Shard, onDecrypted: () -> Unit, onCancel: () -> Unit) {
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
                timerSec = params.timerSec,
                bufferSize = target.sequence.size + 2,
                breachParams = null,
                onRescan = onCancel,
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

/** Один раз объясняем механику новичку (не диалогом: он заблокировал бы таймер) — строкой над сеткой до первого тапа. */
private const val UX_PREFS = "ux_prefs"
private const val BREACH_HINT_SEEN = "breach_hint_seen"
private fun breachHintSeen(context: Context) = context.getSharedPreferences(UX_PREFS, Context.MODE_PRIVATE).getBoolean(BREACH_HINT_SEEN, false)
private fun markBreachHintSeen(context: Context) = context.getSharedPreferences(UX_PREFS, Context.MODE_PRIVATE).edit().putBoolean(BREACH_HINT_SEEN, true).apply()

/**
 * Владеет одной попыткой целиком: тикающим таймером и результатом, если он уже наступил. `remember(seed)` — попытка живёт, пока
 * seed (задаётся при каждом старте) не меняется. Всё помещается на один экран без прокрутки: размер ячеек считается из доступной
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

    var attempt by remember(seed) { mutableStateOf(BreachAttemptState(grid, daemons, bufferSize)) }
    var secondsLeft by remember(seed) { mutableIntStateOf(timerSec) }
    var result by remember(seed) { mutableStateOf<BreachResult?>(null) }
    val context = LocalContext.current
    val haptic = LocalHapticFeedback.current
    val scope = rememberCoroutineScope()
    // Вступительный «вход в узел» — только в живой игре: автосолвер (debug-прогоны) стартует сразу.
    var booted by remember(seed) { mutableStateOf(DebugConfig.autoSolve && DebugConfig.autoSolveStepMs == 0L) }
    val shake = remember(seed) { Animatable(0f) }
    // Реплика защиты узла (см. IceLines) — одна строка над сеткой, обновляется по событиям взлома.
    var iceLine by remember(seed) { mutableStateOf<String?>(null) }
    var hintSeen by remember(seed) { mutableStateOf(DebugConfig.autoSolve || breachHintSeen(context)) }
    fun ice(event: IceEvent) { iceLine = IceLines.line(tier, event, Random(seed xor event.ordinal.toLong())) }

    LaunchedEffect(result == null) { onRunningChange(result == null) }

    fun resolveOnce() {
        if (result == null) {
            val resolved = BreachResult(attempt.daemons, attempt.matchedDaemonIds)
            result = resolved
            Mb10Log.event("Breach", "breach.result", "id" to breachId, "title" to title, "tier" to tier.name, "outcome" to resolved.outcome.name, "matched" to attempt.matchedDaemonIds.size, "daemons" to attempt.daemons.size, "secondsLeft" to secondsLeft, "of" to timerSec)
            haptic.performHapticFeedback(HapticFeedbackType.LongPress)
            BreachSfx.play(context, when (resolved.outcome) {
                BreachOutcome.SUCCESS -> BreachCue.SUCCESS
                BreachOutcome.PARTIAL -> BreachCue.PARTIAL
                BreachOutcome.FAIL -> BreachCue.FAIL
            })
            onResult(resolved)
        }
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
            for (cell in BreachAutoSolver.solve(attempt)) {
                if (step > 0) {
                    delay(step)
                    val next = attempt.select(cell)
                    val hitTrap = cell in attempt.grid.trapCells
                    val matched = next.matchedDaemonIds.size > attempt.matchedDaemonIds.size
                    attempt = next
                    BreachSfx.play(context, if (hitTrap) BreachCue.TRAP else if (matched) BreachCue.MATCH else BreachCue.TAP)
                    if (matched) ice(IceEvent.MATCH)
                } else attempt = attempt.select(cell)
            }
            if (attempt.selected.isNotEmpty()) resolveOnce()
        }
        while (secondsLeft > 0 && !attempt.isFull && result == null) {
            delay(1000)
            secondsLeft -= 1
            if (secondsLeft in 1..5) BreachSfx.play(context, BreachCue.WARN)
            if (secondsLeft == timerSec / 2 && timerSec > 20) ice(IceEvent.HALF_TIME)
            if (secondsLeft == 10 && timerSec > 20) ice(IceEvent.LOW_TIME)
        }
        resolveOnce()
    }

    val selectable = if (result == null) attempt.selectableCells() else emptySet()

    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
            val urgent = secondsLeft in 1..10 && result == null && booted
            val blink by rememberInfiniteTransition(label = "timerBlink").animateFloat(
                initialValue = 0f, targetValue = 1f,
                animationSpec = infiniteRepeatable(tween(450, easing = LinearEasing), RepeatMode.Reverse), label = "blink"
            )
            val timerColor = if (urgent) lerp(c.acc, c.bad, blink) else c.acc

            MbTimer(label = title, time = if (booted) formatTime(secondsLeft) else "--:--", timeColor = timerColor) {
                MbIconButton(MbIcons.Close, "Выйти из взлома ($rescanLabel)", onRescan)
            }

            if (!booted) {
                Spacer(Modifier.height(MbDimens.blockGap))
                BootLog(breachId, bufferSize)
                return@Column
            }

            Spacer(Modifier.height(MbDimens.rowGap))
            MbProgress((secondsLeft.toFloat() / timerSec * 100).roundToInt())

            // Строка-статус фиксированной высоты (одна строка), чтобы сетка не «прыгала» при смене реплик.
            val statusText = iceLine ?: if (!hintSeen && attempt.selected.isEmpty()) "Цепочка: строка → столбец → строка… Соберите коды демонов до нуля." else ""
            if (statusText.isNotEmpty()) {
                Text(
                    statusText, color = if (iceLine != null) c.bad else c.ink2, style = MbTypography.meta, minLines = 1, maxLines = 1,
                    overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = MbDimens.rowGap)
                )
            }

            Spacer(Modifier.height(MbDimens.blockGap))
            MbPanel("Буфер", meta = "${attempt.bufferCodes.size} / ${attempt.bufferSize}") {
                MbBuffer(codes = attempt.bufferCodes, size = attempt.bufferSize)
            }

            Spacer(Modifier.height(MbDimens.blockGap))
            MbPanel("Матрица кодов", meta = "${attempt.grid.size}×${attempt.grid.size}") {
                BoxWithConstraints(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                    val n = attempt.grid.size
                    val gap = 4.dp
                    val cell = ((maxWidth - gap * (n - 1)) / n).coerceIn(28.dp, MbDimens.breachCell)
                    Column(Modifier.offset { IntOffset(shake.value.roundToInt(), 0) }, verticalArrangement = Arrangement.spacedBy(gap)) {
                        for (r in 0 until n) {
                            Row(horizontalArrangement = Arrangement.spacedBy(gap)) {
                                for (col in 0 until n) {
                                    val at = r to col
                                    val order = attempt.selected.indexOf(at)
                                    HackCell(
                                        size = cell,
                                        code = attempt.grid.codeAt(at),
                                        isSelected = order >= 0,
                                        orderLabel = if (order >= 0) (order + 1).toString() else null,
                                        isSelectable = at in selectable,
                                        onClick = {
                                            if (!hintSeen) { hintSeen = true; markBreachHintSeen(context) }
                                            val next = attempt.select(at)
                                            val hitTrap = at in attempt.grid.trapCells
                                            val matched = next.matchedDaemonIds.size > attempt.matchedDaemonIds.size
                                            attempt = next
                                            when {
                                                hitTrap -> {
                                                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                                    BreachSfx.play(context, BreachCue.TRAP)
                                                    ice(IceEvent.TRAP)
                                                    scope.launch {
                                                        repeat(3) { shake.animateTo(if (it % 2 == 0) 9f else -9f, tween(40)) }
                                                        shake.animateTo(0f, tween(40))
                                                    }
                                                }
                                                matched -> { haptic.performHapticFeedback(HapticFeedbackType.LongPress); BreachSfx.play(context, BreachCue.MATCH); ice(IceEvent.MATCH) }
                                                else -> { haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove); BreachSfx.play(context, BreachCue.TAP) }
                                            }
                                            if (attempt.isFull) resolveOnce()
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
            }

            Spacer(Modifier.height(MbDimens.blockGap))
            // Не только коды цели, но и что даст их совпадение — иначе на экране взлома нет ответа на «зачем я выбрал этих демонов».
            MbPanel("Последовательности", meta = "${attempt.daemons.size}") {
                attempt.daemons.forEach { daemon ->
                    val matched = daemon.id in attempt.matchedDaemonIds
                    MbListItem(
                        title = daemon.name,
                        sub = daemon.effect.label(),
                        subWrap = true,
                        trail = listOf({
                            Text(
                                daemon.sequence.joinToString(" "),
                                style = MbTypography.demonCode,
                                color = if (matched) c.acc else c.ink2,
                                textDecoration = if (matched) TextDecoration.LineThrough else null
                            )
                        })
                    )
                }
            }

            if (result == null) {
                Spacer(Modifier.height(MbDimens.blockGap))
                // Не "отмена без последствий" — сдаёт текущий буфер на резолв досрочно, так же как истечение таймера.
                MbButton("Сдать буфер", onClick = { resolveOnce() })
            }
        }

        result?.let { ResultOverlay(it, failMessage, rewardOutcome, secAlertStatus, actionLabel = rescanLabel, onAction = onRescan) }
    }
}

/** Ячейка матрицы: квадрат заданного размера. Шрифт растёт вместе с ячейкой, но не мельче 12 sp. */
@Composable
internal fun HackCell(size: Dp, code: String, isSelected: Boolean, orderLabel: String?, isSelectable: Boolean, onClick: () -> Unit) {
    val c = LocalMbColors.current
    val isDead = code == BreachSymbols.DEAD_MARKER
    val (bg, border, ink) = when {
        isDead && !isSelected -> Triple(c.bad.copy(alpha = 0.08f), c.bad, c.bad)
        isSelected -> Triple(c.bg, c.chromeDim, c.used)
        isSelectable -> Triple(c.acc.copy(alpha = 0.07f), c.acc, c.acc)
        else -> Triple(c.plate, c.plateEdge, c.ink)
    }
    Box(
        modifier = Modifier
            .size(size)
            .mbFrame(fill = bg, edge = border, form = MbChamferForm.Tab, cut = 4.dp)
            .clickable(enabled = isSelectable, onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        Text(code, style = MbTypography.breachCell.copy(fontSize = (size.value * 0.32f).coerceIn(12f, 18f).sp), color = ink)
        if (orderLabel != null) {
            Text(
                orderLabel, color = c.acc, fontSize = 11.sp, fontWeight = FontWeight.Bold,
                modifier = Modifier.align(Alignment.TopEnd).padding(horizontal = 3.dp, vertical = 1.dp)
            )
        }
    }
}

/**
 * Итог взлома поверх экрана, а не под сеткой: сетка и буфер остаются под затемнением в финальном виде; выход — кнопка
 * внутри панели. Помещается без прокрутки (раздел M4.5 плана миграции) — короткий журнал + плашка итога + список
 * демонов, без обёрток вроде ChamferedSurface/DottedDivider. Успех — тема Success поверх Breach (раздел 5 гайдлайна).
 */
@Composable
internal fun ResultOverlay(
    result: BreachResult,
    failMessage: String,
    rewardOutcome: RewardOutcome?,
    secAlertStatus: String?,
    actionLabel: String,
    onAction: () -> Unit
) {
    val colors = if (result.outcome == BreachOutcome.SUCCESS) MbColorsSuccess else LocalMbColors.current
    CompositionLocalProvider(LocalMbColors provides colors) {
        val c = colors
        Box(
            Modifier.fillMaxSize().background(c.bg.copy(alpha = 0.92f))
                .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {},
            contentAlignment = Alignment.BottomCenter
        ) {
            Column(Modifier.fillMaxWidth().padding(MbDimens.screenPadding)) {
                // Заголовок исхода — тексты, по которым стенд e2e (scripts/e2e/lib.sh, breach()) проверяет результат
                // взлома, не переименовывать без правки стенда в том же коммите (CLAUDE.md). «Демоны загружены · X из Y» —
                // формулировка гайдлайна для MbDone (раздел 5) — вторая строка, деталь поверх защищённого заголовка.
                MbPanel(
                    title = "Журнал",
                    meta = "${result.matchedIds.size} из ${result.allDaemons.size}"
                ) {
                    MbLog(
                        listOf("//КОРЕНЬ", "//ЗАПРОС_ДОСТУПА") + when (result.outcome) {
                            BreachOutcome.SUCCESS -> listOf("//ЗАГРУЗКА_ЗАВЕРШЕНА")
                            BreachOutcome.PARTIAL -> listOf("//ЗАГРУЗКА_ЧАСТИЧНАЯ")
                            BreachOutcome.FAIL -> listOf("//ДОСТУП_ОТКЛОНЁН")
                        }
                    )
                    MbDone(
                        when (result.outcome) {
                            BreachOutcome.SUCCESS -> "Взлом завершён"
                            BreachOutcome.PARTIAL -> "Взлом частично успешен"
                            BreachOutcome.FAIL -> "Взлом провален"
                        }
                    )
                    if (result.outcome == BreachOutcome.SUCCESS) {
                        Text(
                            "Демоны загружены · ${result.matchedIds.size} из ${result.allDaemons.size}",
                            style = MbTypography.meta, color = c.ink2, modifier = Modifier.padding(top = MbDimens.rowGap)
                        )
                    }
                }
                Spacer(Modifier.height(MbDimens.blockGap))
                Column(Modifier.fillMaxWidth()) {
                    result.allDaemons.forEach { daemon ->
                        val done = daemon.id in result.matchedIds
                        MbListItem(
                            title = daemon.name,
                            lead = { MbTag(if (done) "установлен" else "не вошёл", tone = if (done) MbTagTone.Ok else MbTagTone.Bad) },
                            plate = true,
                            end = true
                        )
                    }
                }
                if (result.outcome == BreachOutcome.FAIL) {
                    Spacer(Modifier.height(MbDimens.rowGap))
                    Text(failMessage, style = MbTypography.meta, color = c.ink2)
                }
                if (rewardOutcome != null || secAlertStatus != null) {
                    Spacer(Modifier.height(MbDimens.blockGap))
                    rewardOutcome?.let { outcome ->
                        outcome.extractedShardTitles.forEach { t -> RewardRow("Шард извлечён", "«$t»") }
                        outcome.extractedDaemonNames.forEach { name -> RewardRow("Демон извлечён", "«$name»") }
                        if (outcome.eddies > 0) RewardRow("Эдди начислены", "+${formatMoney(outcome.eddies)}", valueColor = c.money)
                        if (outcome.cacheExhausted) RewardRow("Тираж узла", "исчерпан", valueColor = c.bad)
                    }
                    secAlertStatus?.let { RewardRow("Сигнал СБ", it, valueColor = c.bad) }
                }
                Spacer(Modifier.height(MbDimens.blockGap))
                MbButton(actionLabel, onClick = onAction, inline = true, modifier = Modifier.align(Alignment.End))
            }
        }
    }
}

/** Одна строка разбора результата — тип награды/события слева, значение справа. */
@Composable
private fun RewardRow(label: String, value: String, valueColor: Color = LocalMbColors.current.acc) {
    Row(Modifier.fillMaxWidth().padding(vertical = 2.dp), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, style = MbTypography.rowSub, color = LocalMbColors.current.ink2)
        Text(value, style = MbTypography.demonCode, color = valueColor)
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
