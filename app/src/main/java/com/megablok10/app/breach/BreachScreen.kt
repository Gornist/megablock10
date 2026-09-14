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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CheckboxDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlin.random.Random

private val Bg = Color(0xFF0A0A0A)
private val SurfaceCol = Color(0xFF1A1A1A)
private val Lime = Color(0xFFD9FF3F)
private val DimCell = Color(0xFF2A2A2A)
private val DimText = Color(0xFF7A7A7A)
private val Danger = Color(0xFFFF4B4B)

private sealed interface BreachPhase {
    data class Selecting(val chosen: Set<String>) : BreachPhase
    data class Attempting(val initial: BreachAttemptState) : BreachPhase
    data class Resolved(val result: BreachResult) : BreachPhase
}

@Composable
fun BreachScreen(onExit: () -> Unit) {
    var phase by remember { mutableStateOf<BreachPhase>(BreachPhase.Selecting(emptySet())) }

    Surface(color = Bg, modifier = Modifier.fillMaxSize()) {
        Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
            Text(
                "← Профиль",
                color = DimText,
                modifier = Modifier.clickable(onClick = onExit)
            )
            Spacer(Modifier.height(12.dp))
            Text(
                "КИБЕРДЕКА",
                color = Lime,
                fontWeight = FontWeight.Bold,
                fontFamily = FontFamily.Monospace,
                fontSize = 22.sp
            )
            Spacer(Modifier.height(16.dp))

            when (val p = phase) {
                is BreachPhase.Selecting -> SelectingContent(
                    chosen = p.chosen,
                    onToggle = { id ->
                        phase = BreachPhase.Selecting(
                            if (id in p.chosen) p.chosen - id else p.chosen + id
                        )
                    },
                    onStart = { daemons ->
                        val grid = generateGrid(MockBreach.gridSize, daemons, Random(System.nanoTime()))
                        phase = BreachPhase.Attempting(BreachAttemptState(grid, daemons, MockBreach.ramCapacity))
                    }
                )

                is BreachPhase.Attempting -> AttemptingHost(
                    initial = p.initial,
                    onResolved = { result -> phase = BreachPhase.Resolved(result) }
                )

                is BreachPhase.Resolved -> ResolvedContent(
                    result = p.result,
                    onRetry = { phase = BreachPhase.Selecting(emptySet()) }
                )
            }
        }
    }
}

@Composable
private fun SelectingContent(
    chosen: Set<String>,
    onToggle: (String) -> Unit,
    onStart: (List<Daemon>) -> Unit
) {
    val chosenDaemons = MockBreach.daemons.filter { it.id in chosen }
    val used = chosenDaemons.sumOf { it.sequence.size }
    val overBudget = used > MockBreach.ramCapacity

    Column(Modifier.fillMaxSize()) {
        Text("Выбор программ", color = Color.White, fontSize = 16.sp)
        Spacer(Modifier.height(4.dp))
        Text(
            "Буфер: $used / ${MockBreach.ramCapacity}",
            color = if (overBudget) Danger else Lime,
            fontFamily = FontFamily.Monospace
        )
        if (overBudget) {
            Text(
                "Превышен буфер — снимите одну программу",
                color = Danger,
                fontSize = 12.sp
            )
        }
        Spacer(Modifier.height(12.dp))

        LazyColumn(modifier = Modifier.weight(1f)) {
            items(MockBreach.daemons) { daemon ->
                val isChecked = daemon.id in chosen
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { onToggle(daemon.id) }
                        .padding(vertical = 6.dp)
                ) {
                    Checkbox(
                        checked = isChecked,
                        onCheckedChange = { onToggle(daemon.id) },
                        colors = CheckboxDefaults.colors(checkedColor = Lime, uncheckedColor = DimText)
                    )
                    Column(Modifier.padding(start = 4.dp)) {
                        Text(daemon.name, color = Color.White, fontSize = 14.sp)
                        Row {
                            daemon.sequence.forEach { code -> CodeChip(code, Lime) }
                        }
                    }
                }
            }
        }

        Spacer(Modifier.height(12.dp))
        Button(
            onClick = { onStart(chosenDaemons) },
            enabled = chosenDaemons.isNotEmpty() && !overBudget,
            modifier = Modifier.fillMaxWidth()
        ) {
            Text("Начать взлом")
        }
    }
}

/**
 * Владеет состоянием ровно одной попытки от начала до конца: тикающим
 * таймером и списком выбранных клеток. `remember(initial.grid)` — ключ на
 * идентичность сетки конкретной попытки, поэтому и таймер, и буфер
 * переживают тапы (которые меняют этот же state) и переинициализируются
 * только когда реально начинается НОВАЯ попытка (onRetry создаёт новый grid).
 * Резолвится ровно один раз — по таймеру, по заполнению буфера или по
 * ручной остановке, какое наступит раньше (`resolved` не даёт сработать дважды).
 */
@Composable
private fun AttemptingHost(
    initial: BreachAttemptState,
    onResolved: (BreachResult) -> Unit
) {
    var attempt by remember(initial.grid) { mutableStateOf(initial) }
    var secondsLeft by remember(initial.grid) { mutableIntStateOf(MockBreach.timerSec) }
    var resolved by remember(initial.grid) { mutableStateOf(false) }

    fun resolveOnce() {
        if (!resolved) {
            resolved = true
            onResolved(BreachResult(attempt.daemons, attempt.matchedDaemonIds))
        }
    }

    LaunchedEffect(initial.grid) {
        while (secondsLeft > 0 && !attempt.isFull && !resolved) {
            delay(1000)
            secondsLeft -= 1
        }
        resolveOnce()
    }

    AttemptingContent(
        state = attempt,
        secondsLeft = secondsLeft,
        onSelect = { cell ->
            attempt = attempt.select(cell)
            if (attempt.isFull) resolveOnce()
        },
        onStop = { resolveOnce() }
    )
}

@Composable
private fun AttemptingContent(
    state: BreachAttemptState,
    secondsLeft: Int,
    onSelect: (Pair<Int, Int>) -> Unit,
    onStop: () -> Unit
) {
    val selectable = state.selectableCells()

    Column(Modifier.fillMaxSize()) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                "Буфер: ${state.selected.size} / ${state.bufferSize}",
                color = Lime,
                fontFamily = FontFamily.Monospace
            )
            Text(
                "${secondsLeft}с",
                color = if (secondsLeft <= 10) Danger else Color.White,
                fontFamily = FontFamily.Monospace,
                fontWeight = FontWeight.Bold
            )
        }
        Spacer(Modifier.height(8.dp))

        // Буфер — слоты в порядке выбора.
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            val codes = state.bufferCodes
            for (i in 0 until state.bufferSize) {
                val filled = i < codes.size
                Box(
                    modifier = Modifier
                        .size(32.dp)
                        .border(1.dp, if (filled) Lime else DimCell, RoundedCornerShape(4.dp)),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        if (filled) codes[i] else "··",
                        color = if (filled) Lime else DimText,
                        fontSize = 11.sp,
                        fontFamily = FontFamily.Monospace
                    )
                }
            }
        }

        Spacer(Modifier.height(16.dp))

        // Сетка
        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            for (r in 0 until state.grid.size) {
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    for (c in 0 until state.grid.size) {
                        val cell = r to c
                        val order = state.selected.indexOf(cell)
                        val isSelected = order >= 0
                        val isSelectable = cell in selectable
                        BreachCell(
                            code = state.grid.codeAt(cell),
                            isSelected = isSelected,
                            orderLabel = if (isSelected) (order + 1).toString() else null,
                            isSelectable = isSelectable,
                            onClick = { if (isSelectable) onSelect(cell) }
                        )
                    }
                }
            }
        }

        Spacer(Modifier.height(16.dp))
        Text("Программы:", color = Color.White, fontSize = 14.sp)
        state.daemons.forEach { daemon ->
            val matched = daemon.id in state.matchedDaemonIds
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    if (matched) "✓" else "…",
                    color = if (matched) Lime else DimText,
                    modifier = Modifier.width(20.dp)
                )
                Text(
                    daemon.name,
                    color = if (matched) Lime else DimText,
                    fontSize = 13.sp
                )
            }
        }

        Spacer(Modifier.weight(1f))
        Button(
            onClick = onStop,
            modifier = Modifier.fillMaxWidth()
        ) {
            Text("Завершить")
        }
    }
}

@Composable
private fun BreachCell(
    code: String,
    isSelected: Boolean,
    orderLabel: String?,
    isSelectable: Boolean,
    onClick: () -> Unit
) {
    val borderColor = when {
        isSelected -> Lime
        isSelectable -> Lime.copy(alpha = 0.6f)
        else -> DimCell
    }
    val bg = when {
        isSelected -> SurfaceCol
        isSelectable -> SurfaceCol
        else -> Bg
    }
    val textColor = when {
        isSelected -> DimText
        isSelectable -> Lime
        else -> DimText.copy(alpha = 0.5f)
    }

    Box(
        modifier = Modifier
            .size(56.dp)
            .clip(RoundedCornerShape(6.dp))
            .background(bg)
            .border(if (isSelected || isSelectable) 1.5.dp else 1.dp, borderColor, RoundedCornerShape(6.dp))
            .clickable(enabled = isSelectable, onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        Text(code, color = textColor, fontFamily = FontFamily.Monospace, fontSize = 15.sp)
        if (orderLabel != null) {
            Text(
                orderLabel,
                color = Lime,
                fontSize = 9.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(2.dp)
            )
        }
    }
}

@Composable
private fun ResolvedContent(result: BreachResult, onRetry: () -> Unit) {
    val (label, color) = when (result.outcome) {
        BreachOutcome.SUCCESS -> "УСПЕХ" to Lime
        BreachOutcome.PARTIAL -> "ЧАСТИЧНЫЙ УСПЕХ" to Color(0xFFE0C34A)
        BreachOutcome.FAIL -> "ПРОВАЛ" to Danger
    }

    Column(Modifier.fillMaxSize()) {
        Text(label, color = color, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold, fontSize = 28.sp)
        Spacer(Modifier.height(16.dp))
        result.allDaemons.forEach { daemon ->
            val matched = daemon.id in result.matchedIds
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(vertical = 4.dp)) {
                Text(
                    if (matched) "✓" else "✗",
                    color = if (matched) Lime else Danger,
                    modifier = Modifier.width(24.dp),
                    fontWeight = FontWeight.Bold
                )
                Text(daemon.name, color = if (matched) Color.White else DimText)
            }
        }
        if (result.outcome == BreachOutcome.FAIL || result.outcome == BreachOutcome.PARTIAL) {
            Spacer(Modifier.height(12.dp))
            Text(
                "Последствия провала (репутация фракции, блокировка точки) подключатся вместе с Container на следующем этапе.",
                color = DimText,
                fontSize = 12.sp
            )
        }
        Spacer(Modifier.weight(1f))
        Button(onClick = onRetry, modifier = Modifier.fillMaxWidth()) {
            Text("Ещё раз")
        }
    }
}

@Composable
private fun CodeChip(code: String, accent: Color) {
    Box(
        modifier = Modifier
            .padding(end = 4.dp, top = 2.dp)
            .border(1.dp, accent, RoundedCornerShape(3.dp))
            .padding(horizontal = 5.dp, vertical = 1.dp)
    ) {
        Text(code, color = accent, fontSize = 11.sp, fontFamily = FontFamily.Monospace)
    }
}
