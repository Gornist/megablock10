package com.megablok10.app.ui.screens

import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import com.megablok10.app.announce.AnnouncementStore
import com.megablok10.app.announce.Announcements
import com.megablok10.app.ui.theme.AppDialog
import com.megablok10.app.ui.theme.ButtonVariant
import com.megablok10.app.ui.theme.MB10Colors

/**
 * Окно с непрочитанными объявлениями мастера — показывается поверх любого
 * экрана, пока игрок не нажмёт «Принято». «Позже» прячет окно до следующего
 * нового объявления (или перезапуска приложения), но не помечает прочитанным.
 */
@Composable
fun AnnouncementDialogHost() {
    val context = LocalContext.current
    val items by AnnouncementStore.items.collectAsState()
    var snoozedIds by remember { mutableStateOf(emptySet<String>()) }

    val unread = Announcements.unread(items)
    if (unread.none { it.id !in snoozedIds }) return

    // items хранится новыми вперёд; читать удобнее по порядку прихода.
    val ordered = unread.reversed()
    AppDialog(
        onDismissRequest = { snoozedIds = snoozedIds + unread.map { it.id } },
        title = if (unread.size > 1) "Сообщения от мастера (${unread.size})" else "Сообщение от мастера",
        body = ordered.joinToString("\n\n") { it.text },
        confirmText = "Принято",
        onConfirm = { AnnouncementStore.markAllRead(context) },
        dismissText = "Позже",
        // Служебный жёлтый — это сообщение от мастера/приложения, не игровое действие (см. правило accentSystem в Color.kt).
        confirmVariant = ButtonVariant.System,
        borderColor = MB10Colors.accentSystem
    )
}
