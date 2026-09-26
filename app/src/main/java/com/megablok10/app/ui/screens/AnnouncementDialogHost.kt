package com.megablok10.app.ui.screens

import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import com.megablok10.app.announce.Announcements
import com.megablok10.app.di.announcementsViewModel
import com.megablok10.app.ui.appViewModel
import com.megablok10.app.ui.theme.MbButtonKind
import com.megablok10.app.ui.theme.MbDialog
import com.megablok10.app.ui.theme.MbDialogAction
import com.megablok10.app.ui.theme.MbIcons

/**
 * Окно с непрочитанными объявлениями мастера — показывается поверх любого
 * экрана, пока игрок не нажмёт «Принято». «Позже» прячет окно до следующего
 * нового объявления (или перезапуска приложения), но не помечает прочитанным.
 *
 * M4.7 плана миграции: узнаётся по окну — тон Default (тёмно-синий/бирюзовый в MbDialogCard) и иконка колокола,
 * не по цвету рамки, как было со служебным жёлтым `accentSystem` (открытый вопрос владельцу №1, ответ «да, согласен»).
 */
@Composable
fun AnnouncementDialogHost() {
    val announcements = appViewModel { announcementsViewModel() }
    val items by announcements.items.collectAsStateWithLifecycle()
    var snoozedIds by remember { mutableStateOf(emptySet<String>()) }

    val unread = Announcements.unread(items)
    if (unread.none { it.id !in snoozedIds }) return

    // items хранится новыми вперёд; читать удобнее по порядку прихода.
    val ordered = unread.reversed()
    AnnouncementDialog(
        count = unread.size,
        body = ordered.joinToString("\n\n") { it.text },
        onLater = { snoozedIds = snoozedIds + unread.map { it.id } },
        onAccept = announcements::markAllRead
    )
}

/** Только вид — вынесен из [AnnouncementDialogHost], чтобы снять скриншотом без ViewModel (см. AnnouncementDialogTest). */
@Composable
internal fun AnnouncementDialog(count: Int, body: String, onLater: () -> Unit, onAccept: () -> Unit) {
    MbDialog(
        onDismissRequest = onLater,
        icon = MbIcons.Bell,
        // Заголовок с одним объявлением — текст, по которому стенд e2e (scripts/e2e/scenarios/announcement.sh) находит
        // окно, не переименовывать без правки стенда в том же коммите (CLAUDE.md).
        title = if (count > 1) "Сообщения от мастера ($count)" else "Сообщение от мастера",
        actions = listOf(
            MbDialogAction("Позже", MbButtonKind.Quiet, onClick = onLater),
            MbDialogAction("Принято", MbButtonKind.Quiet, onClick = onAccept)
        )
    ) {
        Text(body)
    }
}
