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
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CheckboxDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.megablok10.app.ui.theme.ChamferedPanel
import com.megablok10.app.ui.theme.DottedDivider
import com.megablok10.app.ui.theme.FlagTab
import com.megablok10.app.ui.theme.HexBullet
import com.megablok10.app.ui.theme.IBMPlexSans
import com.megablok10.app.ui.theme.JetBrainsMono
import com.megablok10.app.ui.theme.Jura
import com.megablok10.app.ui.theme.MB10Colors
import com.megablok10.app.ui.theme.chamferShape
import kotlinx.coroutines.delay
import kotlin.random.Random

/**
 * Структура экрана повторяет референсный HTML-макет: выбор программ и
 * кнопка старта видны ПОСТОЯННО (а не прячутся на время попытки), терминал
 * взлома появляется под ними и после резолва не исчезает — результат
 * рисуется внутри той же рамки поверх замороженной сетки/буфера/демонов,
 * а не отдельным экраном. Повторный тап "Взломать точку доступа" всегда
 * стартует новую попытку с текущим выбором демонов.
 */
@Composable
fun BreachScreen() {
    var chosen by remember { mutableStateOf<Set<String>>(emptySet()) }
    var sessionSeed by remember { mutableStateOf<Long?>(null) }

    val chosenDaemons = MockBreach.daemons.filter { it.id in chosen }
    val used = chosenDaemons.sumOf { it.sequence.size }
    val overBudget = used > MockBreach.ramCapacity
    val canStart = chosenDaemons.isNotEmpty() && !overBudget

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(bottom = 10.dp)) {
            HexBullet(MB10Colors.lime, size = 8.dp)
            Spacer(Modifier.width(6.dp))
            Text("Точка доступа: панель вентиляции, техэтаж", color = MB10Colors.inkMuted, fontFamily = JetBrainsMono, fontSize = 10.5.sp)
        }

        DaemonPicker(chosen = chosen, onToggle = { id -> chosen = if (id in chosen) chosen - id else chosen + id })

        Text(
            "Буфер: $used / ${MockBreach.ramCapacity}" + if (overBudget) " — снимите демон" else "",
            color = if (overBudget) MB10Colors.red else MB10Colors.inkMuted,
            fontFamily = JetBrainsMono,
            fontSize = 11.sp,
            modifier = Modifier.padding(top = 10.dp, bottom = 14.dp)
        )

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .background(MB10Colors.lime, chamferShape(6.dp))
                .clickable(enabled = canStart) { sessionSeed = System.nanoTime() }
                .padding(vertical = 10.dp)
        ) {
            Text(
                "Взломать точку доступа",
                color = if (canStart) Color(0xFF0A0A00) else Color(0xFF0A0A00).copy(alpha = 0.4f),
                fontFamily = JetBrainsMono,
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth()
            )
        }

        sessionSeed?.let { seed ->
            Spacer(Modifier.height(14.dp))
            BreachSession(
                daemons = chosenDaemons,
                seed = seed,
                onRestart = { sessionSeed = System.nanoTime() }
            )
        }
    }
}

@Composable
private fun DaemonPicker(chosen: Set<String>, onToggle: (String) -> Unit) {
    Column {
        MockBreach.daemons.forEachIndexed { index, daemon ->
            val isChecked = daemon.id in chosen
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth().clickable { onToggle(daemon.id) }.padding(vertical = 9.dp)
            ) {
                Checkbox(
                    checked = isChecked,
                    onCheckedChange = { onToggle(daemon.id) },
                    colors = CheckboxDefaults.colors(checkedColor = MB10Colors.lime, uncheckedColor = MB10Colors.inkFaint)
                )
                Column(Modifier.padding(start = 2.dp)) {
                    Text(daemon.name, color = MB10Colors.ink0, fontFamily = IBMPlexSans, fontSize = 13.sp)
                    if (daemon.reward.isNotEmpty()) {
                        Text(daemon.reward, color = MB10Colors.inkMuted, fontFamily = IBMPlexSans, fontSize = 11.sp)
                    }
                    Row(Modifier.padding(top = 4.dp)) {
                        daemon.sequence.forEach { code -> CodePill(code) }
                    }
                }
            }
            if (index != MockBreach.daemons.lastIndex) DottedDivider()
        }
    }
}

@Composable
private fun CodePill(code: String) {
    Box(Modifier.padding(end = 4.dp).background(MB10Colors.bg2, chamferShape(3.dp)).padding(horizontal = 5.dp, vertical = 2.dp)) {
        Text(code, color = MB10Colors.inkMuted, fontFamily = JetBrainsMono, fontSize = 10.sp)
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
private fun BreachSession(daemons: List<Daemon>, seed: Long, onRestart: () -> Unit) {
    val grid = remember(seed) { generateGrid(MockBreach.gridSize, daemons, Random(seed)) }
    val breachId = remember(seed) { "MB10-VENT-" + seed.toString(16).takeLast(4).uppercase() }

    var attempt by remember(seed) { mutableStateOf(BreachAttemptState(grid, daemons, MockBreach.ramCapacity)) }
    var secondsLeft by remember(seed) { mutableIntStateOf(MockBreach.timerSec) }
    var result by remember(seed) { mutableStateOf<BreachResult?>(null) }

    fun resolveOnce() {
        if (result == null) result = BreachResult(attempt.daemons, attempt.matchedDaemonIds)
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
        Box(Modifier.fillMaxWidth().background(MB10Colors.lime).padding(10.dp, 8.dp)) {
            Column {
                Text("BREACH PROTOCOL // ИНТЕРФЕЙС", color = Color(0xFF0A0A00), fontFamily = Jura, fontWeight = FontWeight.Bold, fontSize = 12.5.sp)
                Spacer(Modifier.height(4.dp))
                Text(
                    "доступ разрешён только персоналу с пропуском уровня 2 и выше",
                    color = Color(0xFF0A0A00).copy(alpha = 0.8f), fontFamily = JetBrainsMono, fontSize = 8.sp, lineHeight = 11.sp
                )
                Spacer(Modifier.height(5.dp))
                Text(breachId, color = Color(0xFF0A0A00), fontFamily = JetBrainsMono, fontSize = 9.sp, modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.End)
            }
        }
        Spacer(Modifier.height(14.dp))

        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.Bottom) {
            Text("Время взлома", color = MB10Colors.ink0, fontFamily = Jura, fontWeight = FontWeight.Bold, fontSize = 14.sp)
            Text(
                formatTime(secondsLeft),
                color = MB10Colors.lime,
                fontFamily = JetBrainsMono,
                fontSize = 15.sp,
                modifier = Modifier.border(1.dp, MB10Colors.lime).padding(horizontal = 10.dp, vertical = 3.dp)
            )
        }
        Spacer(Modifier.height(6.dp))
        val progress = (secondsLeft.toFloat() / MockBreach.timerSec).coerceIn(0f, 1f)
        Box(Modifier.fillMaxWidth().height(3.dp).background(MB10Colors.bg2)) {
            Box(Modifier.fillMaxWidth(progress).height(3.dp).background(MB10Colors.lime))
        }

        Row(Modifier.fillMaxWidth().padding(top = 12.dp, bottom = 4.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            val codes = attempt.bufferCodes
            for (i in 0 until attempt.bufferSize) {
                val filled = i < codes.size
                Box(
                    Modifier.size(20.dp).border(1.dp, if (filled) MB10Colors.lime else MB10Colors.inkFaint)
                        .background(if (filled) MB10Colors.lime.copy(alpha = 0.1f) else Color.Transparent)
                )
            }
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

        FlagTab("буфер", modifier = Modifier.padding(top = 14.dp))
        PanelBox {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                val codes = attempt.bufferCodes
                for (i in 0 until attempt.bufferSize) {
                    val filled = i < codes.size
                    Box(
                        Modifier.size(width = 34.dp, height = 28.dp).border(1.dp, if (filled) MB10Colors.ink0 else MB10Colors.inkFaint),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(if (filled) codes[i] else "", color = MB10Colors.ink0, fontFamily = JetBrainsMono, fontSize = 12.sp)
                    }
                }
            }
        }

        FlagTab("демоны", modifier = Modifier.padding(top = 14.dp))
        PanelBox {
            attempt.daemons.forEach { daemon ->
                val matched = daemon.id in attempt.matchedDaemonIds
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(vertical = 6.dp)) {
                    Text(
                        daemon.sequence.joinToString(" · "),
                        color = if (matched) MB10Colors.lime else MB10Colors.inkMuted,
                        fontFamily = JetBrainsMono,
                        fontSize = 13.sp,
                        textDecoration = if (matched) TextDecoration.LineThrough else null
                    )
                }
            }
        }

        Text(
            when {
                result != null -> ""
                attempt.selected.isEmpty() -> "Выберите первый символ в верхней строке."
                else -> "Продолжайте цепочку."
            },
            color = MB10Colors.inkMuted, fontFamily = JetBrainsMono, fontSize = 11.sp, modifier = Modifier.padding(top = 6.dp)
        )

        result?.let { ResultPanel(it) }
    }

    Row(Modifier.fillMaxWidth().padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        if (result == null) {
            OutlineActionButton("Прервать взлом", modifier = Modifier.weight(1f), onClick = { resolveOnce() })
        }
        OutlineActionButton("Новая точка доступа", modifier = Modifier.weight(1f), onClick = onRestart)
    }
}

@Composable
private fun TerminalFrame(content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .border(1.dp, MB10Colors.inkFaint)
            .drawWithContent {
                drawContent()
                val bracket = 9.dp.toPx()
                val stroke = 2.dp.toPx()
                val lime = MB10Colors.lime
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
                drawLine(MB10Colors.inkFaint, Offset(0f, 0f), Offset(0f, size.height), 1.dp.toPx())
                drawLine(MB10Colors.inkFaint, Offset(size.width, 0f), Offset(size.width, size.height), 1.dp.toPx())
                drawLine(MB10Colors.inkFaint, Offset(0f, size.height), Offset(size.width, size.height), 1.dp.toPx())
            }
            .padding(10.dp, 12.dp, 10.dp, 10.dp)
    ) {
        content()
    }
}

@Composable
private fun HackCell(code: String, isSelected: Boolean, orderLabel: String?, isSelectable: Boolean, onClick: () -> Unit) {
    val (bg, borderColor, textColor) = when {
        isSelected -> Triple(Color(0xFF0E1414), MB10Colors.inkFaint, MB10Colors.inkFaint)
        isSelectable -> Triple(MB10Colors.lime.copy(alpha = 0.07f), MB10Colors.lime, MB10Colors.lime)
        else -> Triple(MB10Colors.bg2, MB10Colors.inkFaint, MB10Colors.ink0)
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
                orderLabel, color = MB10Colors.lime, fontSize = 9.sp, fontWeight = FontWeight.Bold,
                modifier = Modifier.align(Alignment.TopEnd).padding(2.dp)
            )
        }
    }
}

@Composable
private fun ResultPanel(result: BreachResult) {
    val (title, color) = when (result.outcome) {
        BreachOutcome.SUCCESS -> "Взлом завершён" to MB10Colors.lime
        BreachOutcome.PARTIAL -> "Взлом частично успешен" to MB10Colors.yellow
        BreachOutcome.FAIL -> "Взлом провален" to MB10Colors.red
    }
    Column(Modifier.fillMaxWidth().padding(top = 14.dp).border(1.dp, color).padding(12.dp)) {
        Text(title, color = color, fontFamily = Jura, fontWeight = FontWeight.Bold, fontSize = 15.sp)
        Spacer(Modifier.height(8.dp))
        result.allDaemons.forEach { daemon ->
            val done = daemon.id in result.matchedIds
            Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(
                    daemon.name,
                    color = if (done) MB10Colors.ink0 else MB10Colors.inkMuted,
                    fontFamily = IBMPlexSans,
                    fontSize = 12.5.sp,
                    textDecoration = if (done) null else TextDecoration.LineThrough
                )
                Text(
                    if (done) "загружен" else "не загружен",
                    color = if (done) MB10Colors.ink0 else MB10Colors.inkMuted,
                    fontFamily = IBMPlexSans,
                    fontSize = 12.5.sp
                )
            }
        }
        DottedDivider(modifier = Modifier.padding(top = 8.dp))
        Text(
            when (result.outcome) {
                BreachOutcome.FAIL -> "СБ зафиксировала попытку. Точка доступа заблокирована до конца этого акта, репутация фракции-владельца снижена."
                BreachOutcome.PARTIAL -> "Незагруженные демоны останутся недоступны до новой попытки на этой точке."
                BreachOutcome.SUCCESS -> "Следов взлома не осталось."
            },
            color = MB10Colors.inkMuted,
            fontFamily = JetBrainsMono,
            fontSize = 10.5.sp,
            modifier = Modifier.padding(top = 8.dp)
        )
    }
}

@Composable
private fun OutlineActionButton(text: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Box(
        modifier = modifier
            .border(1.dp, MB10Colors.inkFaint, chamferShape(5.dp))
            .clickable(onClick = onClick)
            .padding(vertical = 8.dp)
    ) {
        Text(text, color = MB10Colors.ink0, fontFamily = JetBrainsMono, fontSize = 11.sp, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
    }
}

private fun formatTime(totalSeconds: Int): String {
    val s = totalSeconds.coerceAtLeast(0)
    return "${(s / 60).toString().padStart(2, '0')}:${(s % 60).toString().padStart(2, '0')}"
}
