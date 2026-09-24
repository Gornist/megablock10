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
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
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
import com.megablok10.app.collector.ChangeField
import com.megablok10.app.collector.ChangeReason
import com.megablok10.app.collector.ChangeRecordStore
import com.megablok10.app.identity.Identity
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.sound.BreachCue
import com.megablok10.app.sound.BreachSfx
import com.megablok10.app.ui.theme.AppButton
import com.megablok10.app.ui.theme.ButtonVariant
import com.megablok10.app.ui.theme.ChamferedSurface
import com.megablok10.app.ui.theme.DottedDivider
import com.megablok10.app.ui.theme.HexBullet
import com.megablok10.app.ui.theme.IBMPlexSans
import com.megablok10.app.ui.theme.JetBrainsMono
import com.megablok10.app.ui.theme.Jura
import com.megablok10.app.ui.theme.MB10Colors
import com.megablok10.app.ui.theme.chamferBorder
import com.megablok10.app.ui.theme.chamferShape
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.roundToInt
import kotlin.random.Random
import org.json.JSONObject

/**
 * Взлом недоступен, пока не отсканирована QR-метка конкретного контейнера
 * (его печатают мастера на месте, либо это старая "точка доступа" — читается
 * как контейнер тира BASE без лута, см. Mb10Qr.kt). Сама точка входа для
 * скана — общая кнопка "Сканировать объект" на экране Кибердеки — этот
 * композабл только показывает сессию взлома, когда контейнер уже выбран.
 */
@Composable
internal fun BreachContainerFlow(container: Container, daemons: List<Daemon>, identity: Identity, onRescan: () -> Unit, onImmersive: (Boolean) -> Unit = {}) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
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

    val seed = sessionSeed
    if (seed != null) {
        Box(Modifier.fillMaxSize().padding(horizontal = 12.dp, vertical = 8.dp)) {
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
                    scope.launch {
                        val attemptId = "${container.id}:$seed"
                        ChangeRecordStore.enqueue(
                            context, ChangeField.COUNTERS_BREACH, null,
                            JSONObject().put("tier", container.tier.name).put("outcome", result.outcome.name.lowercase()).toString(),
                            ChangeReason.BREACH_ATTEMPT, sourceRef = attemptId, subjectKeyB64 = identity.publicKeyB64,
                        )
                        val outcome = DaemonRewards.apply(context, identity, container, result, attemptId = attemptId)
                        rewardOutcome = outcome
                        if (result.matchedIds.isNotEmpty()) {
                            ContainerCooldownStore.markRewarded(context, container.id)
                        }
                        SecAlertStore.dispatch(context, identity, container, result.outcome, outcome.matchedEffects)
                        secAlertStatus = secAlertStatusText(container, identity, result.outcome, outcome.matchedEffects)
                    }
                }
            )
        }
        return
    }

    // Список демонов скроллится в своей области (weight), а буфер (сверху) и кнопка старта (снизу) закреплены вне скролла.
    Column(Modifier.fillMaxSize().padding(horizontal = 12.dp, vertical = 8.dp)) {
        ContainerHeader(container, onCancel = onRescan)

        // Размер буфера и его заполнение — сверху, закреплено: видно, сколько места остаётся, пока выбираешь демонов ниже по списку.
        // Ячейки заполняются кодами выбранных демонов в порядке выбора.
        val pickedCodes = chosen.mapNotNull { id -> daemons.find { it.id == id } }.flatMap { it.sequence }
        BufferPanel(codes = pickedCodes, size = identity.ramCapacity, hint = if (overBudget) " — снимите демон" else "")
        Spacer(Modifier.height(6.dp))

        Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
            DaemonPicker(
                daemons = daemons,
                chosen = chosen,
                remainingBuffer = identity.ramCapacity - used,
                onToggle = { id -> chosen = if (id in chosen) chosen - id else chosen + id }
            )
        }

        Spacer(Modifier.height(8.dp))
        AppButton("Взломать контейнер", variant = ButtonVariant.Netrun, enabled = canStart, dense = true, modifier = Modifier.fillMaxWidth(),
            onClick = { sessionSeed = System.nanoTime() })
    }
}

@Composable
private fun ContainerHeader(container: Container, onCancel: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
        HexBullet(MB10Colors.accentNetrun, size = 8.dp)
        Spacer(Modifier.width(6.dp))
        Text(
            "${container.name} · ${container.tier.label}",
            color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f)
        )
        Text(
            "✕ Отмена", color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 11.sp,
            modifier = Modifier.clickable(onClick = onCancel).padding(horizontal = 6.dp, vertical = 6.dp)
        )
    }
}

/**
 * Что написать в строке "Сигнал СБ" на экране результата — те же правила
 * гейтинга, что у SecAlertStore.decide (свой контейнер/FAIL на BASE — сигнала
 * не было вовсе, тогда и строки нет), но здесь только для отображения: сам
 * сигнал уже поставлен в очередь отдельным вызовом SecAlertStore.dispatch.
 * Раньше это никак не показывалось на экране результата — игрок не мог
 * узнать, ушёл ли сигнал владельцу, не заглянув в чужой чат.
 */
private fun secAlertStatusText(container: Container, identity: Identity, outcome: BreachOutcome, matchedEffects: Set<DaemonEffect>): String? {
    if (container.ownerFaction.isBlank() || container.ownerFaction == identity.faction) return null
    if (outcome == BreachOutcome.FAIL && container.tier == Tier.BASE) return null
    return if (DaemonEffect.BLACKOUT in matchedEffects) "подавлен (Blackout)" else "отправлен фракции «${container.ownerFaction}»"
}

/**
 * Мини-взлом одного зашифрованного шарда — тот же движок Breach Protocol
 * (BreachSession), что и у контейнера, но без выбора демонов: цель ровно
 * одна, детерминированно выведенная из id шарда (shardDecryptTarget), так
 * что у одного и того же шарда всегда один и тот же набор кодов-цели на
 * этом устройстве. Длина цели — по тиру шарда (MockBreach.
 * shardDecryptTargetLength). Сетка вокруг цели каждый раз новая (сид от
 * nanoTime) — пересдать попытку можно, а не зубрить один и тот же расклад.
 * Вызывается из CyberdeckScreen поверх ShardDetailOverlay.
 */
@Composable
internal fun ShardDecryptFlow(shard: Mb10Qr.Shard, onDecrypted: () -> Unit, onCancel: () -> Unit) {
    val target = remember(shard.id) { shardDecryptTarget(shard) }
    val sessionSeed = remember(shard.id) { System.nanoTime() }
    val params = remember(shard.tier) { BreachTierParams.forTier(Tier.fromLevel(shard.tier)) }

    Box(Modifier.fillMaxSize().padding(horizontal = 12.dp, vertical = 8.dp)) {
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
 *
 * Выбранный демон — не заливка, а лаймовая скошенная грань (как у панели «Взлом завершён»).
 */
@Composable
internal fun DaemonPicker(daemons: List<Daemon>, chosen: Set<String>, remainingBuffer: Int, onToggle: (String) -> Unit) {
    Column {
        daemons.forEach { daemon ->
            val isChecked = daemon.id in chosen
            val fitsBuffer = isChecked || daemon.sequence.size <= remainingBuffer
            val textColor = if (!fitsBuffer) MB10Colors.inkTertiary else MB10Colors.inkPrimary
            val effectColor = if (!fitsBuffer) MB10Colors.accentDanger.copy(alpha = 0.7f) else MB10Colors.inkSecondary
            Column(
                Modifier
                    .fillMaxWidth()
                    .padding(vertical = 2.dp)
                    .then(if (isChecked) Modifier.chamferBorder(MB10Colors.accentNetrun, cut = 6.dp) else Modifier)
                    .clickable(enabled = fitsBuffer) { onToggle(daemon.id) }
                    .padding(horizontal = 10.dp, vertical = 6.dp)
            ) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        "${daemon.name} · ${daemon.tier.label}", color = textColor, fontFamily = IBMPlexSans, fontSize = 13.sp,
                        maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f)
                    )
                    Row { daemon.sequence.forEach { code -> CodePill(code, highlight = isChecked) } }
                }
                Text(if (fitsBuffer) daemon.effect.label() else "не влезает в буфер", color = effectColor, fontFamily = IBMPlexSans, fontSize = 11.sp)
                if (isChecked) {
                    Text(
                        "ЗАГРУЖЕНО В БУФЕР · занимает ${cellsLabel(daemon.sequence.size)}",
                        color = MB10Colors.accentNetrun, fontFamily = JetBrainsMono, fontWeight = FontWeight.Bold, fontSize = 11.sp
                    )
                }
            }
        }
    }
}

@Composable
internal fun CodePill(code: String, highlight: Boolean = false) {
    Box(Modifier.padding(start = 4.dp).background(MB10Colors.surfaceSunken, chamferShape(3.dp)).padding(horizontal = 5.dp, vertical = 2.dp)) {
        Text(code, color = if (highlight) MB10Colors.accentNetrun else MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 11.sp)
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
        Column(Modifier.fillMaxSize()) {
            TerminalFrame(Modifier.weight(1f), dotDecoration = true) {
                val urgent = secondsLeft in 1..10 && result == null && booted
                val blink by rememberInfiniteTransition(label = "timerBlink").animateFloat(
                    initialValue = 0f, targetValue = 1f,
                    animationSpec = infiniteRepeatable(tween(450, easing = LinearEasing), RepeatMode.Reverse), label = "blink"
                )
                val timerColor = if (urgent) lerp(MB10Colors.accentNetrun, MB10Colors.accentDanger, blink) else MB10Colors.accentNetrun

                // Одна строка: заголовок узла слева, таймер справа.
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Box(Modifier.weight(1f).background(MB10Colors.accentNetrun, chamferShape(5.dp)).padding(horizontal = 9.dp, vertical = 5.dp)) {
                        Text(
                            "BREACH // $title", color = MB10Colors.onAccent, fontFamily = Jura, fontWeight = FontWeight.Bold, fontSize = 12.sp,
                            maxLines = 1, overflow = TextOverflow.Ellipsis
                        )
                    }
                    if (booted) {
                        Text(
                            formatTime(secondsLeft), color = timerColor, fontFamily = JetBrainsMono, fontSize = 15.sp, fontWeight = FontWeight.Medium,
                            modifier = Modifier.chamferBorder(timerColor, cut = 5.dp).padding(horizontal = 9.dp, vertical = 3.dp)
                        )
                    }
                }

                if (!booted) {
                    Spacer(Modifier.height(10.dp))
                    BootLog(breachId, bufferSize)
                    return@TerminalFrame
                }

                Spacer(Modifier.height(5.dp))
                val progress = (secondsLeft.toFloat() / timerSec).coerceIn(0f, 1f)
                Box(Modifier.fillMaxWidth().height(3.dp).background(MB10Colors.surfaceSunken)) {
                    Box(Modifier.fillMaxWidth(progress).height(3.dp).background(timerColor))
                }

                // Строка-статус фиксированной высоты (одна строка), чтобы сетка не «прыгала» при смене реплик.
                val statusText = iceLine ?: if (!hintSeen && attempt.selected.isEmpty()) "Цепочка: строка → столбец → строка… Соберите коды демонов до нуля." else ""
                val statusColor = if (iceLine != null) MB10Colors.accentDanger else MB10Colors.inkSecondary
                Text(
                    statusText, color = statusColor, fontFamily = JetBrainsMono, fontSize = 11.sp, minLines = 1, maxLines = 1,
                    overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 5.dp)
                )

                // Буфер — над матрицей: игрок видит свой выбор, не листая экран.
                BufferPanel(codes = attempt.bufferCodes, size = attempt.bufferSize, topPadding = 4.dp)

                // Матрица занимает всё свободное место; размер ячейки — из меньшей стороны (ширина/высота).
                BoxWithConstraints(Modifier.weight(1f).fillMaxWidth().padding(vertical = 6.dp), contentAlignment = Alignment.Center) {
                    val n = attempt.grid.size
                    val gap = 4.dp
                    val cell = minOf((maxWidth - gap * (n - 1)) / n, (maxHeight - gap * (n - 1)) / n).coerceIn(20.dp, 64.dp)
                    Column(Modifier.offset { IntOffset(shake.value.roundToInt(), 0) }, verticalArrangement = Arrangement.spacedBy(gap)) {
                        for (r in 0 until n) {
                            Row(horizontalArrangement = Arrangement.spacedBy(gap)) {
                                for (c in 0 until n) {
                                    val at = r to c
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

                // Не только коды цели, но и что даст их совпадение — иначе на экране взлома нет ответа на «зачем я выбрал этих демонов».
                TerminalPanel {
                    attempt.daemons.forEach { daemon ->
                        val matched = daemon.id in attempt.matchedDaemonIds
                        val nameColor = if (matched) MB10Colors.inkPrimary else MB10Colors.inkSecondary
                        val codeColor = if (matched) MB10Colors.accentNetrun else MB10Colors.inkSecondary
                        val strike = if (matched) TextDecoration.LineThrough else null
                        Column(Modifier.padding(vertical = 2.dp)) {
                            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                                Text(daemon.name, color = nameColor, fontFamily = IBMPlexSans, fontSize = 12.5.sp, textDecoration = strike, modifier = Modifier.weight(1f))
                                Text(daemon.sequence.joinToString(" · "), color = codeColor, fontFamily = JetBrainsMono, fontSize = 12.sp, textDecoration = strike)
                            }
                            Text(daemon.effect.label(), color = MB10Colors.inkTertiary, fontFamily = IBMPlexSans, fontSize = 11.sp)
                        }
                    }
                }
            }

            if (result == null) {
                // Не "отмена без последствий" — сдаёт текущий буфер на резолв досрочно, так же как истечение таймера.
                Row(Modifier.fillMaxWidth().padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    AppButton("Сдать буфер", modifier = Modifier.weight(1f), variant = ButtonVariant.Secondary, dense = true, onClick = { resolveOnce() })
                    AppButton(rescanLabel, modifier = Modifier.weight(1f), variant = ButtonVariant.Secondary, dense = true, onClick = onRescan)
                }
            }
        }

        result?.let { ResultOverlay(it, failMessage, rewardOutcome, secAlertStatus, actionLabel = rescanLabel, onAction = onRescan) }
    }
}

/**
 * Скошенная рамка терминала: контур повторяет срез, остальные панели экрана взлома лежат внутри неё.
 * dotDecoration — полоса точек-делений сверху/снизу (HUD-линейка, см. Motion.DotTickRow); по умолчанию выключена —
 * не всякий вызов TerminalFrame это отдельный "терминал-сцена" (скриншот-тесты используют голую рамку).
 */
@Composable
internal fun TerminalFrame(modifier: Modifier = Modifier, dotDecoration: Boolean = false, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .chamferBorder(MB10Colors.borderMuted, cut = 10.dp)
            .padding(8.dp),
    ) {
        if (dotDecoration) {
            com.megablok10.app.ui.theme.DotTickRow(color = MB10Colors.borderMuted)
            Spacer(Modifier.height(6.dp))
        }
        content()
        if (dotDecoration) {
            Spacer(Modifier.height(6.dp))
            com.megablok10.app.ui.theme.DotTickRow(color = MB10Colors.borderMuted)
        }
    }
}

/** Тонкая скошенная панель внутри терминала (список демонов, лог входа). */
@Composable
internal fun TerminalPanel(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .chamferBorder(MB10Colors.borderMuted, cut = 6.dp)
            .padding(horizontal = 10.dp, vertical = 6.dp),
        content = content
    )
}

/** Ячейка матрицы: квадрат заданного размера, скошенный. Шрифт растёт вместе с ячейкой, но не мельче 12 sp. */
@Composable
internal fun HackCell(size: Dp, code: String, isSelected: Boolean, orderLabel: String?, isSelectable: Boolean, onClick: () -> Unit) {
    val isDead = code == BreachSymbols.DEAD_MARKER
    val (bg, borderColor, textColor) = when {
        isDead && !isSelected -> Triple(MB10Colors.accentDanger.copy(alpha = 0.08f), MB10Colors.accentDanger, MB10Colors.accentDanger)
        isSelected -> Triple(MB10Colors.surfaceBase, MB10Colors.borderMuted, MB10Colors.borderMuted)
        isSelectable -> Triple(MB10Colors.accentNetrun.copy(alpha = 0.07f), MB10Colors.accentNetrun, MB10Colors.accentNetrun)
        else -> Triple(MB10Colors.surfaceSunken, MB10Colors.borderMuted, MB10Colors.inkPrimary)
    }
    Box(
        modifier = Modifier
            .size(size)
            .background(bg, chamferShape(4.dp))
            .chamferBorder(borderColor, cut = 4.dp)
            .clickable(enabled = isSelectable, onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        Text(code, color = textColor, fontFamily = JetBrainsMono, fontWeight = FontWeight.Medium, fontSize = (size.value * 0.32f).coerceIn(12f, 18f).sp)
        if (orderLabel != null) {
            Text(
                orderLabel, color = MB10Colors.accentNetrun, fontSize = 11.sp, fontWeight = FontWeight.Bold,
                modifier = Modifier.align(Alignment.TopEnd).padding(horizontal = 3.dp, vertical = 1.dp)
            )
        }
    }
}

/**
 * Итог взлома поверх экрана, а не под сеткой: раньше игрок узнавал результат, только прокрутив вниз. Сетка и буфер остаются под
 * затемнением в финальном виде; выход — кнопка внутри панели.
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
    val (title, color) = when (result.outcome) {
        BreachOutcome.SUCCESS -> "Взлом завершён" to MB10Colors.accentNetrun
        BreachOutcome.PARTIAL -> "Взлом частично успешен" to MB10Colors.accentAction
        BreachOutcome.FAIL -> "Взлом провален" to MB10Colors.accentDanger
    }
    Box(
        Modifier.fillMaxSize().background(MB10Colors.surfaceBase.copy(alpha = 0.8f))
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {},
        contentAlignment = Alignment.BottomCenter
    ) {
        ChamferedSurface(
            borderColor = color, fillColor = MB10Colors.surfaceRaised, cut = 10.dp, contentPadding = 12.dp,
            augmented = true,
            modifier = Modifier.fillMaxWidth().padding(bottom = 4.dp)
        ) {
            Column {
                Column(Modifier.heightIn(max = 420.dp).verticalScroll(rememberScrollState())) {
                    Text(title, color = color, fontFamily = Jura, fontWeight = FontWeight.Bold, fontSize = 16.sp)
                    Spacer(Modifier.height(6.dp))
                    result.allDaemons.forEach { daemon ->
                        val done = daemon.id in result.matchedIds
                        Row(Modifier.fillMaxWidth().padding(vertical = 2.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text(
                                daemon.name, color = if (done) MB10Colors.inkPrimary else MB10Colors.inkSecondary, fontFamily = IBMPlexSans, fontSize = 12.5.sp,
                                textDecoration = if (done) null else TextDecoration.LineThrough
                            )
                            Text(
                                if (done) "загружен" else "не загружен", color = if (done) MB10Colors.inkPrimary else MB10Colors.inkSecondary,
                                fontFamily = IBMPlexSans, fontSize = 12.5.sp
                            )
                        }
                    }
                    DottedDivider(modifier = Modifier.padding(top = 6.dp))
                    Text(
                        when (result.outcome) {
                            BreachOutcome.FAIL -> failMessage
                            BreachOutcome.PARTIAL -> "Незагруженные демоны останутся недоступны до новой попытки на этом контейнере."
                            BreachOutcome.SUCCESS -> "Следов взлома не осталось."
                        },
                        color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 11.sp, modifier = Modifier.padding(top = 6.dp)
                    )
                    if (rewardOutcome != null || secAlertStatus != null) {
                        DottedDivider(modifier = Modifier.padding(top = 6.dp, bottom = 2.dp))
                    }
                    rewardOutcome?.let { outcome ->
                        outcome.extractedShardTitles.forEach { t -> RewardRow("Шард извлечён", "«$t»") }
                        outcome.extractedDaemonNames.forEach { name -> RewardRow("Демон извлечён", "«$name»") }
                        if (outcome.eddies > 0) RewardRow("Эдди начислены", "+${outcome.eddies} €$")
                        if (outcome.cacheExhausted) RewardRow("Тираж узла", "исчерпан", valueColor = MB10Colors.accentDanger)
                    }
                    secAlertStatus?.let { RewardRow("Сигнал СБ", it, valueColor = MB10Colors.accentDanger) }
                }
                Spacer(Modifier.height(10.dp))
                AppButton(actionLabel, modifier = Modifier.fillMaxWidth(), variant = ButtonVariant.Secondary, dense = true, onClick = onAction)
            }
        }
    }
}

/** Одна строка разбора результата — тип награды/события слева, значение справа. */
@Composable
private fun RewardRow(label: String, value: String, valueColor: Color = MB10Colors.accentNetrun) {
    Row(Modifier.fillMaxWidth().padding(vertical = 2.dp), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, color = MB10Colors.inkSecondary, fontFamily = IBMPlexSans, fontSize = 12.sp)
        Text(value, color = valueColor, fontFamily = JetBrainsMono, fontSize = 12.sp, fontWeight = FontWeight.Medium)
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
    TerminalPanel {
        lines.forEachIndexed { i, line ->
            Text(
                if (i < shown) line else "",
                color = if (i == lines.lastIndex) MB10Colors.accentNetrun else MB10Colors.inkSecondary,
                fontFamily = JetBrainsMono, fontSize = 12.sp, minLines = 1, modifier = Modifier.padding(vertical = 3.dp)
            )
        }
    }
}

/**
 * Буфер: ряд ячеек, которые заполняются кодами. Один и тот же компонент на экране выбора демонов (там ячейки заполняют коды выбранных
 * демонов) и на экране взлома (там — выбранные клетки сетки). Ячейки равной ширины на всю строку, при большом буфере (RAM до 13) —
 * в две строки, иначе фиксированные ячейки не влезали и последняя сжималась. Заголовок — одна строка текста, без отдельной рамки.
 */
@Composable
internal fun BufferPanel(codes: List<String>, size: Int, topPadding: Dp = 2.dp, hint: String = "") {
    Column(Modifier.fillMaxWidth().padding(top = topPadding)) {
        Row {
            Text("БУФЕР ${codes.size}/$size", color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 11.sp)
            if (hint.isNotEmpty()) Text(hint, color = MB10Colors.accentDanger, fontFamily = JetBrainsMono, fontSize = 11.sp)
        }
        Spacer(Modifier.height(3.dp))
        val perRow = if (size <= 8) size else (size + 1) / 2
        for (start in 0 until size step perRow) {
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp), modifier = Modifier.padding(bottom = if (start + perRow < size) 4.dp else 0.dp)) {
                for (i in start until start + perRow) {
                    if (i >= size) { Spacer(Modifier.weight(1f)); continue }
                    val filled = i < codes.size
                    Box(
                        Modifier.weight(1f).height(26.dp)
                            .background(if (filled) MB10Colors.surfaceSunken else Color.Transparent, chamferShape(3.dp))
                            .chamferBorder(if (filled) MB10Colors.inkPrimary else MB10Colors.borderMuted, cut = 3.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(if (filled) codes[i] else "", color = MB10Colors.inkPrimary, fontFamily = JetBrainsMono, fontSize = 12.sp)
                    }
                }
            }
        }
    }
}
