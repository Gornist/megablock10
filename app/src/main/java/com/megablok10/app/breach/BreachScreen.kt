package com.megablok10.app.breach

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
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
import com.megablok10.app.ui.theme.DottedDivider
import com.megablok10.app.ui.theme.FlagTab
import com.megablok10.app.ui.theme.HexBullet
import com.megablok10.app.ui.theme.IBMPlexSans
import com.megablok10.app.ui.theme.JetBrainsMono
import com.megablok10.app.ui.theme.Jura
import com.megablok10.app.ui.theme.ListRow
import com.megablok10.app.ui.theme.MB10Colors
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
internal fun BreachContainerFlow(container: Container, daemons: List<Daemon>, identity: Identity, onRescan: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var chosen by remember(container.id) { mutableStateOf<Set<String>>(emptySet()) }
    var sessionSeed by remember(container.id) { mutableStateOf<Long?>(null) }
    var rewardOutcome by remember(container.id) { mutableStateOf<RewardOutcome?>(null) }
    var secAlertStatus by remember(container.id) { mutableStateOf<String?>(null) }

    val chosenDaemons = daemons.filter { it.id in chosen }
    val used = chosenDaemons.sumOf { it.sequence.size }
    val overBudget = used > identity.ramCapacity
    val canStart = chosenDaemons.isNotEmpty() && !overBudget
    val params = remember(container.tier) { BreachTierParams.forTier(container.tier) }
    val timerBonus = if (chosenDaemons.any { it.effect == DaemonEffect.JITTER }) 15 else 0

    val seed = sessionSeed
    if (seed != null) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
            ContainerHeader(container)
            BreachSession(
                tier = container.tier,
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

    // Список демонов скроллится в своей области (weight), а счётчик буфера и
    // кнопка старта закреплены снизу вне скролла — раньше счётчик стоял под
    // списком и терялся из виду, пока выбираешь демонов дальше по списку.
    Column(Modifier.fillMaxSize().padding(16.dp)) {
        ContainerHeader(container)

        Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
            DaemonPicker(
                daemons = daemons,
                chosen = chosen,
                remainingBuffer = identity.ramCapacity - used,
                onToggle = { id -> chosen = if (id in chosen) chosen - id else chosen + id }
            )
        }

        Text(
            "Буфер: $used / ${identity.ramCapacity}" + if (overBudget) " — снимите демон" else "",
            color = if (overBudget) MB10Colors.accentDanger else MB10Colors.inkSecondary,
            fontFamily = JetBrainsMono,
            fontSize = 11.sp,
            modifier = Modifier.padding(top = 10.dp, bottom = 14.dp)
        )

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .background(MB10Colors.accentNetrun, chamferShape(6.dp))
                .clickable(enabled = canStart) { sessionSeed = System.nanoTime() }
                .padding(vertical = 10.dp)
        ) {
            Text(
                "Взломать контейнер",
                color = if (canStart) MB10Colors.onAccent else MB10Colors.onAccent.copy(alpha = 0.4f),
                fontFamily = JetBrainsMono,
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth()
            )
        }
    }
}

@Composable
private fun ContainerHeader(container: Container) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(bottom = 10.dp)) {
        HexBullet(MB10Colors.accentNetrun, size = 8.dp)
        Spacer(Modifier.width(6.dp))
        Text(
            "Контейнер: ${container.name} · ${container.tier.label}",
            color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 10.5.sp
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

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(bottom = 10.dp)) {
            HexBullet(MB10Colors.accentNetrun, size = 8.dp)
            Spacer(Modifier.width(6.dp))
            Text("Шифр-замок: ${shard.title}", color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 10.5.sp)
        }
        BreachSession(
            tier = Tier.fromLevel(shard.tier),
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
 * remainingBuffer — сколько буфера осталось ПОСЛЕ уже выбранных демонов (см.
 * BreachContainerFlow). Демон, который в него не влезает, показан приглушённым
 * и с явной причиной ("не влезает в буфер") вместо своего эффекта, а не
 * кликабелен — раньше это выяснялось только после попытки стартовать взлом,
 * общей надписью под списком. Уже выбранного демона это не касается: снять
 * его можно всегда, его вес уже учтён в remainingBuffer, а не заново против него.
 */
@Composable
private fun DaemonPicker(daemons: List<Daemon>, chosen: Set<String>, remainingBuffer: Int, onToggle: (String) -> Unit) {
    Column {
        daemons.forEachIndexed { index, daemon ->
            val isChecked = daemon.id in chosen
            val fitsBuffer = isChecked || daemon.sequence.size <= remainingBuffer
            val textColor = when {
                isChecked -> MB10Colors.onAccent
                !fitsBuffer -> MB10Colors.inkTertiary
                else -> MB10Colors.inkPrimary
            }
            val effectColor = when {
                isChecked -> MB10Colors.onAccent.copy(alpha = 0.8f)
                !fitsBuffer -> MB10Colors.accentDanger.copy(alpha = 0.7f)
                else -> MB10Colors.inkSecondary
            }
            ListRow(
                selected = isChecked,
                selectedColor = MB10Colors.accentNetrun,
                onClick = if (fitsBuffer) ({ onToggle(daemon.id) }) else null
            ) {
                Text("${daemon.name} · ${daemon.tier.label}", color = textColor, fontFamily = IBMPlexSans, fontSize = 13.sp)
                Text(if (fitsBuffer) daemon.effect.label() else "не влезает в буфер", color = effectColor, fontFamily = IBMPlexSans, fontSize = 11.sp)
                Row(Modifier.padding(top = 4.dp)) {
                    daemon.sequence.forEach { code -> CodePill(code) }
                }
            }
            if (index != daemons.lastIndex) DottedDivider()
        }
    }
}

@Composable
internal fun CodePill(code: String) {
    Box(Modifier.padding(end = 4.dp).background(MB10Colors.surfaceSunken, chamferShape(3.dp)).padding(horizontal = 5.dp, vertical = 2.dp)) {
        Text(code, color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 10.sp)
    }
}

/**
 * Владеет одной попыткой целиком: тикающим таймером и результатом, если он
 * уже наступил. `remember(seed)` — попытка живёт, пока seed (задаётся при
 * каждом старте) не меняется; тапы по сетке меняют этот же state, а не
 * пересоздают его. После резолва (таймер/буфер/ручной стоп) сетка и буфер
 * остаются на экране в финальном виде — просто перестают принимать тапы —
 * и поверх появляется result-panel, как в макете. breachParams — если не
 * null, задаёт мёртвые клетки/порченые коды (см. generateGrid); у
 * ShardDecryptFlow ловушек нет вовсе (null), это только для контейнеров.
 */
@Composable
private fun BreachSession(
    tier: Tier,
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
    onResult: (BreachResult) -> Unit = {}
) {
    val grid = remember(seed) { generateGrid(gridSize, daemons, Random(seed), breachParams) }
    val breachId = remember(seed) { "MB10-VENT-" + seed.toString(16).takeLast(4).uppercase() }

    var attempt by remember(seed) { mutableStateOf(BreachAttemptState(grid, daemons, bufferSize)) }
    var secondsLeft by remember(seed) { mutableIntStateOf(timerSec) }
    var result by remember(seed) { mutableStateOf<BreachResult?>(null) }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    // Вступительный «вход в узел» — только в живой игре: автосолвер (debug-прогоны) стартует сразу.
    var booted by remember(seed) { mutableStateOf(DebugConfig.autoSolve) }
    val shake = remember(seed) { Animatable(0f) }
    // Реплика защиты узла (см. IceLines) — одна строка над сеткой, обновляется по событиям взлома.
    var iceLine by remember(seed) { mutableStateOf<String?>(null) }
    fun ice(event: IceEvent) { iceLine = IceLines.line(tier, event, Random(seed xor event.ordinal.toLong())) }

    fun resolveOnce() {
        if (result == null) {
            val resolved = BreachResult(attempt.daemons, attempt.matchedDaemonIds)
            result = resolved
            BreachSfx.play(context, when (resolved.outcome) {
                BreachOutcome.SUCCESS -> BreachCue.SUCCESS
                BreachOutcome.PARTIAL -> BreachCue.PARTIAL
                BreachOutcome.FAIL -> BreachCue.FAIL
            })
            onResult(resolved)
        }
    }

    LaunchedEffect(seed) {
        if (!booted) {
            BreachSfx.play(context, BreachCue.ENTER)
            delay(BOOT_LINE_MS * BOOT_LINES)
            booted = true
            ice(IceEvent.INTRO)
        }
        if (DebugConfig.autoSolve) {
            for (cell in BreachAutoSolver.solve(attempt)) attempt = attempt.select(cell)
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

    TerminalFrame {
        Box(Modifier.fillMaxWidth().background(MB10Colors.accentNetrun).padding(10.dp, 8.dp)) {
            Column {
                Text("BREACH PROTOCOL // ИНТЕРФЕЙС", color = MB10Colors.onAccent, fontFamily = Jura, fontWeight = FontWeight.Bold, fontSize = 12.5.sp)
                Spacer(Modifier.height(4.dp))
                Text(
                    "доступ разрешён только персоналу с пропуском уровня 2 и выше",
                    color = MB10Colors.onAccent.copy(alpha = 0.8f), fontFamily = JetBrainsMono, fontSize = 8.sp, lineHeight = 11.sp
                )
                Spacer(Modifier.height(5.dp))
                Text(breachId, color = MB10Colors.onAccent, fontFamily = JetBrainsMono, fontSize = 9.sp, modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.End)
            }
        }
        Spacer(Modifier.height(14.dp))

        if (!booted) {
            BootLog(breachId, bufferSize)
            return@TerminalFrame
        }

        val urgent = secondsLeft in 1..10 && result == null
        val blink by rememberInfiniteTransition(label = "timerBlink").animateFloat(
            initialValue = 0f, targetValue = 1f,
            animationSpec = infiniteRepeatable(tween(450, easing = LinearEasing), RepeatMode.Reverse), label = "blink"
        )
        val timerColor = if (urgent) lerp(MB10Colors.accentNetrun, MB10Colors.accentDanger, blink) else MB10Colors.accentNetrun

        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.Bottom) {
            Text("Время взлома", color = MB10Colors.inkPrimary, fontFamily = Jura, fontWeight = FontWeight.Bold, fontSize = 14.sp)
            Text(
                formatTime(secondsLeft),
                color = timerColor,
                fontFamily = JetBrainsMono,
                fontSize = 15.sp,
                modifier = Modifier.border(1.dp, timerColor).padding(horizontal = 10.dp, vertical = 3.dp)
            )
        }
        Spacer(Modifier.height(6.dp))
        val progress = (secondsLeft.toFloat() / timerSec).coerceIn(0f, 1f)
        Box(Modifier.fillMaxWidth().height(3.dp).background(MB10Colors.surfaceSunken)) {
            Box(Modifier.fillMaxWidth(progress).height(3.dp).background(timerColor))
        }

        iceLine?.let {
            Text(
                it, color = MB10Colors.accentDanger, fontFamily = JetBrainsMono, fontSize = 10.5.sp,
                maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis, modifier = Modifier.padding(top = 10.dp)
            )
        }

        FlagTab("код-матрица", modifier = Modifier.padding(top = 14.dp))
        PanelBox(modifier = Modifier.offset { IntOffset(shake.value.roundToInt(), 0) }) {
            for (r in 0 until attempt.grid.size) {
                Row(horizontalArrangement = Arrangement.spacedBy(5.dp), modifier = Modifier.padding(bottom = 5.dp)) {
                    for (c in 0 until attempt.grid.size) {
                        val cell = r to c
                        val order = attempt.selected.indexOf(cell)
                        HackCell(
                            code = attempt.grid.codeAt(cell),
                            isSelected = order >= 0,
                            orderLabel = if (order >= 0) (order + 1).toString() else null,
                            isSelectable = cell in selectable,
                            onClick = {
                                val next = attempt.select(cell)
                                val hitTrap = cell in attempt.grid.trapCells
                                val matched = next.matchedDaemonIds.size > attempt.matchedDaemonIds.size
                                attempt = next
                                when {
                                    hitTrap -> {
                                        BreachSfx.play(context, BreachCue.TRAP)
                                        ice(IceEvent.TRAP)
                                        scope.launch {
                                            repeat(3) { shake.animateTo(if (it % 2 == 0) 9f else -9f, tween(40)) }
                                            shake.animateTo(0f, tween(40))
                                        }
                                    }
                                    matched -> { BreachSfx.play(context, BreachCue.MATCH); ice(IceEvent.MATCH) }
                                    else -> BreachSfx.play(context, BreachCue.TAP)
                                }
                                if (attempt.isFull) resolveOnce()
                            }
                        )
                    }
                }
            }
        }

        FlagTab("буфер ${attempt.selected.size}/${attempt.bufferSize}", modifier = Modifier.padding(top = 14.dp))
        PanelBox {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                val codes = attempt.bufferCodes
                for (i in 0 until attempt.bufferSize) {
                    val filled = i < codes.size
                    Box(
                        Modifier.size(width = 34.dp, height = 28.dp).border(1.dp, if (filled) MB10Colors.inkPrimary else MB10Colors.borderMuted),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(if (filled) codes[i] else "", color = MB10Colors.inkPrimary, fontFamily = JetBrainsMono, fontSize = 12.sp)
                    }
                }
            }
        }

        // Не только коды цели, но и что даст их совпадение — иначе на самом
        // экране взлома нет ответа на вопрос "а зачем я вообще выбрал этих демонов".
        FlagTab("демоны", modifier = Modifier.padding(top = 14.dp))
        PanelBox {
            attempt.daemons.forEach { daemon ->
                val matched = daemon.id in attempt.matchedDaemonIds
                val nameColor = if (matched) MB10Colors.inkPrimary else MB10Colors.inkSecondary
                val codeColor = if (matched) MB10Colors.accentNetrun else MB10Colors.inkSecondary
                Column(Modifier.padding(vertical = 6.dp)) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            daemon.name,
                            color = nameColor,
                            fontFamily = IBMPlexSans,
                            fontSize = 12.5.sp,
                            textDecoration = if (matched) TextDecoration.LineThrough else null,
                            modifier = Modifier.weight(1f)
                        )
                        Text(
                            daemon.sequence.joinToString(" · "),
                            color = codeColor,
                            fontFamily = JetBrainsMono,
                            fontSize = 12.sp,
                            textDecoration = if (matched) TextDecoration.LineThrough else null
                        )
                    }
                    Text(daemon.effect.label(), color = MB10Colors.inkTertiary, fontFamily = IBMPlexSans, fontSize = 10.5.sp)
                }
            }
        }

        Text(
            when {
                result != null -> ""
                attempt.selected.isEmpty() -> "Выберите первый символ в верхней строке."
                else -> "Продолжайте цепочку."
            },
            color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 11.sp, modifier = Modifier.padding(top = 6.dp)
        )

        result?.let { ResultPanel(it, failMessage = failMessage, rewardOutcome = rewardOutcome, secAlertStatus = secAlertStatus) }
    }

    Row(Modifier.fillMaxWidth().padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        if (result == null) {
            // Не "отмена без последствий" — сдаёт текущий буфер на резолв
            // досрочно, так же как истечение таймера. Название кнопки должно
            // это отражать, иначе игрок ждёт отмены без результата.
            AppButton("Сдать буфер досрочно", modifier = Modifier.weight(1f), variant = ButtonVariant.Secondary, onClick = { resolveOnce() })
        }
        AppButton(rescanLabel, modifier = Modifier.weight(1f), variant = ButtonVariant.Secondary, onClick = onRescan)
    }
}

@Composable
private fun TerminalFrame(content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .border(1.dp, MB10Colors.borderMuted)
            .drawWithContent {
                drawContent()
                val bracket = 9.dp.toPx()
                val stroke = 2.dp.toPx()
                val lime = MB10Colors.accentNetrun
                drawLine(lime, Offset(0f, 0f), Offset(bracket, 0f), stroke)
                drawLine(lime, Offset(0f, 0f), Offset(0f, bracket), stroke)
                drawLine(lime, Offset(size.width, 0f), Offset(size.width - bracket, 0f), stroke)
                drawLine(lime, Offset(size.width, 0f), Offset(size.width, bracket), stroke)
                drawLine(lime, Offset(0f, size.height), Offset(bracket, size.height), stroke)
                drawLine(lime, Offset(0f, size.height), Offset(0f, size.height - bracket), stroke)
                drawLine(lime, Offset(size.width, size.height), Offset(size.width - bracket, size.height), stroke)
                drawLine(lime, Offset(size.width, size.height), Offset(size.width, size.height - bracket), stroke)
            }
            .padding(14.dp),
        content = content
    )
}

/** Рамка без верхней стороны — визуально продолжает FlagTab, который стоит прямо над ней. */
@Composable
private fun PanelBox(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .drawWithContent {
                drawContent()
                drawLine(MB10Colors.borderMuted, Offset(0f, 0f), Offset(0f, size.height), 1.dp.toPx())
                drawLine(MB10Colors.borderMuted, Offset(size.width, 0f), Offset(size.width, size.height), 1.dp.toPx())
                drawLine(MB10Colors.borderMuted, Offset(0f, size.height), Offset(size.width, size.height), 1.dp.toPx())
            }
            .padding(10.dp, 12.dp, 10.dp, 10.dp)
    ) {
        content()
    }
}

@Composable
private fun HackCell(code: String, isSelected: Boolean, orderLabel: String?, isSelectable: Boolean, onClick: () -> Unit) {
    val isDead = code == BreachSymbols.DEAD_MARKER
    val (bg, borderColor, textColor) = when {
        isDead && !isSelected -> Triple(MB10Colors.accentDanger.copy(alpha = 0.08f), MB10Colors.accentDanger, MB10Colors.accentDanger)
        isSelected -> Triple(MB10Colors.surfaceBase, MB10Colors.borderMuted, MB10Colors.borderMuted)
        isSelectable -> Triple(MB10Colors.accentNetrun.copy(alpha = 0.07f), MB10Colors.accentNetrun, MB10Colors.accentNetrun)
        else -> Triple(MB10Colors.surfaceSunken, MB10Colors.borderMuted, MB10Colors.inkPrimary)
    }
    Box(
        modifier = Modifier
            .size(48.dp)
            .background(bg)
            .border(1.dp, borderColor)
            .clickable(enabled = isSelectable, onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        Text(code, color = textColor, fontFamily = JetBrainsMono, fontWeight = FontWeight.Medium, fontSize = 15.sp)
        if (orderLabel != null) {
            Text(
                orderLabel, color = MB10Colors.accentNetrun, fontSize = 9.sp, fontWeight = FontWeight.Bold,
                modifier = Modifier.align(Alignment.TopEnd).padding(2.dp)
            )
        }
    }
}

@Composable
private fun ResultPanel(
    result: BreachResult,
    failMessage: String = "СБ зафиксировала попытку. Контейнер заблокирован до конца этого акта.",
    rewardOutcome: RewardOutcome? = null,
    secAlertStatus: String? = null
) {
    val (title, color) = when (result.outcome) {
        BreachOutcome.SUCCESS -> "Взлом завершён" to MB10Colors.accentNetrun
        BreachOutcome.PARTIAL -> "Взлом частично успешен" to MB10Colors.accentAction
        BreachOutcome.FAIL -> "Взлом провален" to MB10Colors.accentDanger
    }
    Column(Modifier.fillMaxWidth().padding(top = 14.dp).border(1.dp, color).padding(12.dp)) {
        Text(title, color = color, fontFamily = Jura, fontWeight = FontWeight.Bold, fontSize = 15.sp)
        Spacer(Modifier.height(8.dp))
        result.allDaemons.forEach { daemon ->
            val done = daemon.id in result.matchedIds
            Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(
                    daemon.name,
                    color = if (done) MB10Colors.inkPrimary else MB10Colors.inkSecondary,
                    fontFamily = IBMPlexSans,
                    fontSize = 12.5.sp,
                    textDecoration = if (done) null else TextDecoration.LineThrough
                )
                Text(
                    if (done) "загружен" else "не загружен",
                    color = if (done) MB10Colors.inkPrimary else MB10Colors.inkSecondary,
                    fontFamily = IBMPlexSans,
                    fontSize = 12.5.sp
                )
            }
        }
        DottedDivider(modifier = Modifier.padding(top = 8.dp))
        Text(
            when (result.outcome) {
                BreachOutcome.FAIL -> failMessage
                BreachOutcome.PARTIAL -> "Незагруженные демоны останутся недоступны до новой попытки на этом контейнере."
                BreachOutcome.SUCCESS -> "Следов взлома не осталось."
            },
            color = MB10Colors.inkSecondary,
            fontFamily = JetBrainsMono,
            fontSize = 10.5.sp,
            modifier = Modifier.padding(top = 8.dp)
        )
        if (rewardOutcome != null || secAlertStatus != null) {
            DottedDivider(modifier = Modifier.padding(top = 8.dp, bottom = 4.dp))
        }
        rewardOutcome?.let { outcome ->
            outcome.extractedShardTitles.forEach { title -> RewardRow("Шард извлечён", "«$title»") }
            outcome.extractedDaemonNames.forEach { name -> RewardRow("Демон извлечён", "«$name»") }
            if (outcome.eddies > 0) RewardRow("Эдди начислены", "+${outcome.eddies} €$")
            if (outcome.cacheExhausted) RewardRow("Тираж узла", "исчерпан", valueColor = MB10Colors.accentDanger)
        }
        secAlertStatus?.let { RewardRow("Сигнал СБ", it, valueColor = MB10Colors.accentDanger) }
    }
}

/** Одна строка разбора результата — тип награды/события слева, значение справа. Раньше это всё было одной склеенной строкой, из которой не разобрать, что случилось конкретно (см. ревизию мокапа "Результат · шард"). */
@Composable
private fun RewardRow(label: String, value: String, valueColor: Color = MB10Colors.accentNetrun) {
    Row(Modifier.fillMaxWidth().padding(vertical = 3.dp), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, color = MB10Colors.inkSecondary, fontFamily = IBMPlexSans, fontSize = 11.5.sp)
        Text(value, color = valueColor, fontFamily = JetBrainsMono, fontSize = 11.5.sp, fontWeight = FontWeight.Medium)
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
    PanelBox {
        lines.forEachIndexed { i, line ->
            Text(
                if (i < shown) line else "",
                color = if (i == lines.lastIndex) MB10Colors.accentNetrun else MB10Colors.inkSecondary,
                fontFamily = JetBrainsMono, fontSize = 12.sp, modifier = Modifier.padding(vertical = 3.dp)
            )
        }
    }
}
