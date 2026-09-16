package com.megablok10.app.breach

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.megablok10.app.qr.Mb10Qr
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
import kotlin.random.Random

/**
 * Взлом недоступен, пока не отсканирована QR-метка конкретной точки доступа
 * (её печатают мастера на месте). Сама точка входа для скана теперь общая
 * для Демонов и Шардов (единая кнопка "Сканировать объект" на экране
 * Кибердеки выше) — этот композабл только показывает сессию взлома, когда
 * точка уже выбрана; вызывается из CyberdeckScreen.
 */
@Composable
internal fun BreachAccessPointFlow(point: Mb10Qr.AccessPoint, daemons: List<Daemon>, onRescan: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var chosen by remember(point.id) { mutableStateOf<Set<String>>(emptySet()) }
    var sessionSeed by remember(point.id) { mutableStateOf<Long?>(null) }

    val chosenDaemons = daemons.filter { it.id in chosen }
    val used = chosenDaemons.sumOf { it.sequence.size }
    val overBudget = used > MockBreach.ramCapacity
    val canStart = chosenDaemons.isNotEmpty() && !overBudget

    val seed = sessionSeed
    if (seed != null) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(bottom = 10.dp)) {
                HexBullet(MB10Colors.accentNetrun, size = 8.dp)
                Spacer(Modifier.width(6.dp))
                Text("Точка доступа: ${point.name}", color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 10.5.sp)
            }
            BreachSession(
                daemons = chosenDaemons,
                seed = seed,
                onRescan = onRescan,
                // Награда — деньги/шард у совпавших демонов (если заданы) —
                // и отметка кулдауна точки, только если реально что-то
                // засчиталось (FAIL кулдаун не запускает).
                onResult = { result ->
                    scope.launch {
                        DaemonRewards.apply(context, result)
                        if (result.matchedIds.isNotEmpty()) {
                            AccessPointCooldownStore.markRewarded(context, point.id)
                        }
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
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(bottom = 10.dp)) {
            HexBullet(MB10Colors.accentNetrun, size = 8.dp)
            Spacer(Modifier.width(6.dp))
            Text("Точка доступа: ${point.name}", color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 10.5.sp)
        }

        Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
            DaemonPicker(daemons = daemons, chosen = chosen, onToggle = { id -> chosen = if (id in chosen) chosen - id else chosen + id })
        }

        Text(
            "Буфер: $used / ${MockBreach.ramCapacity}" + if (overBudget) " — снимите демон" else "",
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
                "Взломать точку доступа",
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

/**
 * Мини-взлом одного зашифрованного шарда — тот же движок Breach Protocol
 * (BreachSession), что и у точки доступа, но без выбора демонов: цель ровно
 * одна, детерминированно выведенная из id шарда (shardDecryptTarget), так
 * что у одного и того же шарда всегда один и тот же набор кодов-цели на
 * этом устройстве. Сетка вокруг цели каждый раз новая (сид от nanoTime,
 * как и в BreachAccessPointFlow) — пересдать попытку можно, а не зубрить
 * один и тот же расклад. Вызывается из CyberdeckScreen поверх ShardDetailOverlay.
 */
@Composable
internal fun ShardDecryptFlow(shard: Mb10Qr.Shard, onDecrypted: () -> Unit, onCancel: () -> Unit) {
    val target = remember(shard.id) { shardDecryptTarget(shard) }
    val sessionSeed = remember(shard.id) { System.nanoTime() }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(bottom = 10.dp)) {
            HexBullet(MB10Colors.accentNetrun, size = 8.dp)
            Spacer(Modifier.width(6.dp))
            Text("Шифр-замок: ${shard.title}", color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 10.5.sp)
        }
        BreachSession(
            daemons = listOf(target),
            seed = sessionSeed,
            onRescan = onCancel,
            rescanLabel = "Отмена",
            failMessage = "Шифр-замок устоял. Шард остаётся зашифрован — можно попробовать ещё раз.",
            onResult = { result -> if (result.outcome == BreachOutcome.SUCCESS) onDecrypted() }
        )
    }
}

private fun shardDecryptTarget(shard: Mb10Qr.Shard): Daemon {
    val random = Random(shard.id.hashCode().toLong())
    val sequence = List(3) { BreachSymbols.ALPHABET.random(random) }
    return Daemon(id = "shard-decrypt:${shard.id}", name = "Шифр-замок", sequence = sequence)
}

@Composable
private fun DaemonPicker(daemons: List<Daemon>, chosen: Set<String>, onToggle: (String) -> Unit) {
    Column {
        daemons.forEachIndexed { index, daemon ->
            val isChecked = daemon.id in chosen
            val textColor = if (isChecked) MB10Colors.onAccent else MB10Colors.inkPrimary
            val rewardColor = if (isChecked) MB10Colors.onAccent.copy(alpha = 0.8f) else MB10Colors.inkSecondary
            ListRow(
                selected = isChecked,
                selectedColor = MB10Colors.accentNetrun,
                onClick = { onToggle(daemon.id) }
            ) {
                Text(daemon.name, color = textColor, fontFamily = IBMPlexSans, fontSize = 13.sp)
                if (daemon.reward.isNotEmpty()) {
                    Text(daemon.reward, color = rewardColor, fontFamily = IBMPlexSans, fontSize = 11.sp)
                }
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
 * и поверх появляется result-panel, как в макете.
 */
@Composable
private fun BreachSession(
    daemons: List<Daemon>,
    seed: Long,
    onRescan: () -> Unit,
    rescanLabel: String = "Новая точка доступа",
    failMessage: String = "СБ зафиксировала попытку. Точка доступа заблокирована до конца этого акта.",
    onResult: (BreachResult) -> Unit = {}
) {
    val grid = remember(seed) { generateGrid(MockBreach.gridSize, daemons, Random(seed)) }
    val breachId = remember(seed) { "MB10-VENT-" + seed.toString(16).takeLast(4).uppercase() }

    var attempt by remember(seed) { mutableStateOf(BreachAttemptState(grid, daemons, MockBreach.ramCapacity)) }
    var secondsLeft by remember(seed) { mutableIntStateOf(MockBreach.timerSec) }
    var result by remember(seed) { mutableStateOf<BreachResult?>(null) }

    fun resolveOnce() {
        if (result == null) {
            val resolved = BreachResult(attempt.daemons, attempt.matchedDaemonIds)
            result = resolved
            onResult(resolved)
        }
    }

    LaunchedEffect(seed) {
        while (secondsLeft > 0 && !attempt.isFull && result == null) {
            delay(1000)
            secondsLeft -= 1
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

        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.Bottom) {
            Text("Время взлома", color = MB10Colors.inkPrimary, fontFamily = Jura, fontWeight = FontWeight.Bold, fontSize = 14.sp)
            Text(
                formatTime(secondsLeft),
                color = MB10Colors.accentNetrun,
                fontFamily = JetBrainsMono,
                fontSize = 15.sp,
                modifier = Modifier.border(1.dp, MB10Colors.accentNetrun).padding(horizontal = 10.dp, vertical = 3.dp)
            )
        }
        Spacer(Modifier.height(6.dp))
        val progress = (secondsLeft.toFloat() / MockBreach.timerSec).coerceIn(0f, 1f)
        Box(Modifier.fillMaxWidth().height(3.dp).background(MB10Colors.surfaceSunken)) {
            Box(Modifier.fillMaxWidth(progress).height(3.dp).background(MB10Colors.accentNetrun))
        }

        FlagTab("код-матрица", modifier = Modifier.padding(top = 14.dp))
        PanelBox {
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
                                attempt = attempt.select(cell)
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
                    if (daemon.reward.isNotEmpty()) {
                        Text(daemon.reward, color = MB10Colors.inkTertiary, fontFamily = IBMPlexSans, fontSize = 10.5.sp)
                    }
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

        result?.let { ResultPanel(it, failMessage = failMessage) }
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
private fun PanelBox(content: @Composable () -> Unit) {
    Column(
        modifier = Modifier
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
    val (bg, borderColor, textColor) = when {
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
    failMessage: String = "СБ зафиксировала попытку. Точка доступа заблокирована до конца этого акта."
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
                BreachOutcome.PARTIAL -> "Незагруженные демоны останутся недоступны до новой попытки на этой точке."
                BreachOutcome.SUCCESS -> "Следов взлома не осталось."
            },
            color = MB10Colors.inkSecondary,
            fontFamily = JetBrainsMono,
            fontSize = 10.5.sp,
            modifier = Modifier.padding(top = 8.dp)
        )
    }
}

private fun formatTime(totalSeconds: Int): String {
    val s = totalSeconds.coerceAtLeast(0)
    return "${(s / 60).toString().padStart(2, '0')}:${(s % 60).toString().padStart(2, '0')}"
}
