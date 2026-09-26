package com.megablok10.app.ui.nav

import android.content.SharedPreferences
import com.megablok10.app.data.CallLogDao
import com.megablok10.app.data.CallOutcome
import com.megablok10.app.data.ChatMessageDao
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/**
 * Счётчики на иконках нижнего меню — шаг «Нужны данные» плана миграции UI (docs/ux/ui-migration-plan.md), перед M3.
 *
 * Водяной знак — сколько диалогов чата содержат новое (для меня) сообщение и сколько звонков пропущено с момента,
 * когда игрок последний раз открывал вкладку. Это НЕ сетевые read-receipts ([com.megablok10.app.chat.ReadReceipts]):
 * те сообщают собеседнику «твоё сообщение прочитано», а здесь — чисто локальная моя отметка «я это уже видел» для
 * бейджа на иконке; используется тот же файл настроек (`chat_prefs`), но другие ключи, схема Room не меняется.
 *
 * Решение, что считать «непрочитанным» (это UI-удобство, не журналируемый факт — можно поменять без миграции):
 * диалог, если последнее сообщение в нём — входящее и новее водяного знака, а не число отдельных сообщений —
 * ближе к тому, что игрок видит в списке диалогов (жирная строка «есть новое», а не точный счётчик).
 */
class ShellBadges(
    private val chatDao: ChatMessageDao,
    private val callDao: CallLogDao,
    private val prefs: SharedPreferences,
    private val now: () -> Long = System::currentTimeMillis
) {
    fun unreadChatThreads(myPubKey: String): Flow<Int> = chatDao.observeRecentDirectThreads(myPubKey).map { threads ->
        val seenAt = prefs.getLong(KEY_CHAT_SEEN, 0L)
        threads.count { it.fromPubKeyB64 != myPubKey && it.timestamp > seenAt }
    }

    fun missedCalls(): Flow<Int> = callDao.observeAll().map { calls ->
        val seenAt = prefs.getLong(KEY_CALLS_SEEN, 0L)
        calls.count { it.outcome == CallOutcome.MISSED && it.startedAt > seenAt }
    }

    fun markChatSeen() {
        prefs.edit().putLong(KEY_CHAT_SEEN, now()).apply()
    }

    fun markCallsSeen() {
        prefs.edit().putLong(KEY_CALLS_SEEN, now()).apply()
    }

    companion object {
        const val PREFS = "chat_prefs"
        private const val KEY_CHAT_SEEN = "shell_badge_chat_seen_at"
        private const val KEY_CALLS_SEEN = "shell_badge_calls_seen_at"
    }
}
