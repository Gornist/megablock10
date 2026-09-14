package com.megablok10.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.megablok10.app.ui.theme.ChamferedPanel
import com.megablok10.app.ui.theme.IBMPlexSans
import com.megablok10.app.ui.theme.JetBrainsMono
import com.megablok10.app.ui.theme.MB10Colors
import com.megablok10.app.ui.theme.chamferShape

private data class ChatMessage(val sender: String, val time: String, val body: String, val self: Boolean = false)

/**
 * Заглушка на демо-данных из HTML-макета — реальный TCP-чат появится
 * только на этапе NSD/presence. Пока это визуальный макет экрана, не
 * подключённый ни к какому транспорту.
 */
private val demoFactionMessages = listOf(
    ChatMessage("Лидер · Отряд", "21:32", "Всем оставаться на 8 этаже. К клинике не подходить без пропуска второго уровня."),
    ChatMessage("Игрок_04", "21:40", "У западного лифта нашли ещё один пропуск, отдал на пост."),
    ChatMessage("Вы", "21:44", "Принято, иду проверять техэтаж вместе с Ольгой.", self = true)
)

@Composable
fun ChatScreen() {
    var activeSegment by remember { mutableStateOf(0) }
    var draft by remember { mutableStateOf("") }

    Column(Modifier.fillMaxSize().padding(16.dp)) {
        ChamferedPanel(
            borderColor = MB10Colors.inkFaint,
            fillColor = MB10Colors.bg1,
            cut = 6.dp,
            contentPadding = 0.dp,
            modifier = Modifier.fillMaxWidth()
        ) {
            Row(Modifier.fillMaxWidth()) {
                listOf("Фракция", "Личные").forEachIndexed { i, label ->
                    val active = i == activeSegment
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .background(if (active) MB10Colors.bg2 else MB10Colors.bg1)
                            .padding(vertical = 8.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            label,
                            color = if (active) MB10Colors.ink0 else MB10Colors.inkMuted,
                            fontFamily = IBMPlexSans,
                            fontSize = 13.sp,
                            modifier = Modifier.padding(0.dp)
                        )
                    }
                }
            }
        }
        Spacer(Modifier.height(14.dp))

        LazyColumn(modifier = Modifier.weight(1f)) {
            items(demoFactionMessages) { msg -> MessageBubble(msg) }
        }

        Row(
            modifier = Modifier.fillMaxWidth().padding(top = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            ChamferedPanel(
                modifier = Modifier.weight(1f),
                borderColor = MB10Colors.inkFaint,
                fillColor = MB10Colors.bg2,
                cut = 6.dp,
                contentPadding = 0.dp
            ) {
                TextField(
                    value = draft,
                    onValueChange = { draft = it },
                    placeholder = { Text("Сообщение фракции", color = MB10Colors.inkMuted, fontFamily = IBMPlexSans, fontSize = 13.sp) },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions.Default,
                    colors = TextFieldDefaults.colors(
                        focusedContainerColor = MB10Colors.bg2,
                        unfocusedContainerColor = MB10Colors.bg2,
                        focusedIndicatorColor = androidx.compose.ui.graphics.Color.Transparent,
                        unfocusedIndicatorColor = androidx.compose.ui.graphics.Color.Transparent,
                        focusedTextColor = MB10Colors.ink0,
                        unfocusedTextColor = MB10Colors.ink0
                    ),
                    textStyle = androidx.compose.ui.text.TextStyle(fontFamily = IBMPlexSans, fontSize = 13.sp),
                    modifier = Modifier.fillMaxWidth()
                )
            }
            Box(
                modifier = Modifier
                    .background(MB10Colors.yellow, chamferShape(6.dp))
                    .padding(horizontal = 16.dp, vertical = 12.dp)
            ) {
                Text("Отпр.", color = androidx.compose.ui.graphics.Color(0xFF1A1600), fontFamily = JetBrainsMono, fontSize = 12.sp, fontWeight = FontWeight.Medium)
            }
        }
    }
}

@Composable
private fun MessageBubble(msg: ChatMessage) {
    Column(Modifier.fillMaxWidth().padding(bottom = 12.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(msg.sender, color = MB10Colors.inkMuted, fontFamily = JetBrainsMono, fontSize = 10.sp)
            Text(msg.time, color = MB10Colors.inkMuted, fontFamily = JetBrainsMono, fontSize = 10.sp)
        }
        Spacer(Modifier.height(4.dp))
        Row {
            if (msg.self) {
                Box(Modifier.width(2.dp).background(MB10Colors.yellow))
            }
            Box(
                modifier = Modifier
                    .weight(1f)
                    .background(MB10Colors.bg2, chamferShape(6.dp))
                    .padding(vertical = 9.dp, horizontal = 11.dp)
            ) {
                Text(msg.body, color = MB10Colors.ink0, fontFamily = IBMPlexSans, fontSize = 13.5.sp, lineHeight = 19.sp)
            }
        }
    }
}
