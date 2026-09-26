package com.megablok10.app.screenshots

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import com.megablok10.app.chat.ChatMessageType
import com.megablok10.app.data.ChatMessageEntity
import com.megablok10.app.data.MessageStatus
import com.megablok10.app.ui.screens.ConversationRow
import com.megablok10.app.ui.screens.MessageBubble
import com.megablok10.app.ui.theme.LocalMbColors
import com.megablok10.app.ui.theme.MbColorsDefault
import com.megablok10.app.ui.theme.MbEmptyState
import com.megablok10.app.ui.theme.MbIcons
import org.junit.Rule
import org.junit.Test

/** M4.1 плана миграции: экран «Сообщения» — фейковые данные, без ViewModel/AppGraph (их с Paparazzi не поднять). */
class ChatScreenTest {
    @get:Rule
    val paparazzi = Paparazzi(deviceConfig = DeviceConfig.PIXEL_5.copy(softButtons = false), maxPercentDifference = 0.5)

    private fun snap(name: String, content: @Composable () -> Unit) {
        paparazzi.snapshot(name) {
            CompositionLocalProvider(LocalMbColors provides MbColorsDefault) {
                Box(Modifier.background(MbColorsDefault.bg).padding(10.dp)) {
                    Column { content() }
                }
            }
        }
    }

    private fun msg(from: String, callsign: String, to: String, body: String, ts: Long, status: Int = MessageStatus.NONE) =
        ChatMessageEntity(type = ChatMessageType.DM.name, fromPubKeyB64 = from, fromCallsign = callsign, faction = "Вольные", toPubKeyB64 = to, body = body, timestamp = ts, status = status)

    @Test
    fun inboxList() = snap("chat_inbox") {
        ConversationRow(title = "Фракция: Вольные", preview = "Шептун: сбор у бойлерной в полночь", time = 1_700_000_000_000L, onClick = {})
        ConversationRow(title = "Вобла", preview = "Два. Нужен ПРИЗРАК, иначе тебя срисуют…", time = 1_700_000_001_000L, onClick = {})
        ConversationRow(title = "Лом", preview = "Вы: ок, жду у лифта", time = 1_700_000_002_000L, onClick = {})
    }

    @Test
    fun threadBubbles() = snap("chat_thread") {
        MessageBubble(msg = msg("bob", "Вобла", "me", "СБ крутится у лифтов на 37-м.", 1L), self = false, showSender = false)
        MessageBubble(msg = msg("me", "Alice", "bob", "Почти — это сколько слотов?", 2L, MessageStatus.READ), self = true, showSender = false)
        MessageBubble(msg = msg("bob", "Вобла", "me", "Два. Нужен ПРИЗРАК, иначе тебя срисуют через 4 минуты.", 3L), self = false, showSender = false)
    }

    @Test
    fun emptyState() = snap("chat_empty") {
        MbEmptyState(MbIcons.Chat, "Чатов пока нет", "Отсканируйте QR-код другого игрока в Профиле, чтобы начать с ним переписку.")
    }
}
