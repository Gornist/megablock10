package com.megablok10.app.identity

import androidx.room.withTransaction
import com.megablok10.app.announce.AnnouncementStore
import com.megablok10.app.collector.ChangeField
import com.megablok10.app.collector.ChangeReason
import com.megablok10.app.collector.CollectorSettings
import com.megablok10.app.data.Mb10Database
import com.megablok10.app.log.Mb10Log
import com.megablok10.kit.sync.ChangeRecorder

/**
 * Сброс сессии персонажа НА УСТРОЙСТВЕ (Настройки → «Опасная зона»): телефон возвращается в состояние «чистая установка», чтобы игрок не нашёл
 * остатков прежнего персонажа и они не мешали принять QR для нового захода. Сам персонаж как набор данных остаётся у мастера на сервере и
 * может быть выдан заново (docs/provisioning-qr.md, docs/character-reissue.md).
 *
 * Что стирается: ключи и личность, все игровые таблицы Room (кошелёк, предметы, демоны, шарды, переписка, контакты, звонки, остывания
 * контейнеров, заявки на слоты, токены, очередь исходящих сообщений чата, передачи) и объявления мастера.
 * Что остаётся: (1) очередь неотправленных записей на сервер [KEEP_TABLES] — уже подписаны ключом прежнего персонажа, среди них
 * уведомление о сбросе, стереть их значило бы потерять историю, и счётчик их номеров `sequences` — нумерация на устройстве только растёт,
 * иначе новый персонаж мог бы получить номер, уже занятый в этой очереди; (2) адрес сервера и код игры (нужны, чтобы эти записи дошли; новый QR перезапишет);
 * (3) идентификаторы уже применённых QR — тот же код повторно не примется, (4) пользовательские настройки устройства (звук, подсказки).
 */
class SessionReset(
    private val db: Mb10Database,
    private val identityStore: IdentityStore,
    private val settings: CollectorSettings,
    private val changes: ChangeRecorder,
    private val announcements: AnnouncementStore,
    /** Остановить сеть до стирания данных (session.SessionController.onSessionReset). */
    private val stopSession: () -> Unit,
) {
    /**
     * Выполняет сброс. [reportToCollector] — записать на сервер, что персонаж сброшен (кнопка в Настройках); стенд e2e тоже идёт этим путём.
     * Записи обязаны попасть в очередь ДО стирания ключа: подписывать их после будет нечем.
     */
    suspend fun perform(identity: Identity?, reportToCollector: Boolean = true) {
        Mb10Log.event("SessionReset", "reset.start", "me" to Mb10Log.short(identity?.publicKeyB64), "reportToCollector" to reportToCollector)
        if (reportToCollector && identity != null) {
            changes.record(ChangeField.CALLSIGN, identity.callsign, "", ChangeReason.CHARACTER_RESET)
            changes.record(ChangeField.FACTION, identity.faction, "", ChangeReason.CHARACTER_RESET)
        }
        stopSession()
        db.withTransaction {
            val db1 = db.openHelper.writableDatabase
            val tables = db1.query("SELECT name FROM sqlite_master WHERE type = 'table'").use { c -> buildList { while (c.moveToNext()) add(c.getString(0)) } }
            wipeStatements(tables).forEach { db1.execSQL(it) }
        }
        announcements.clear()
        identityStore.clear()
        settings.setProvisioned(false)
        settings.setProvisionRejected(false)
        Mb10Log.event("SessionReset", "reset.done")
    }

    companion object {
        /** Таблицы, которые сброс НЕ трогает. Всё остальное, включая таблицы, которые появятся позже, стирается по умолчанию. */
        val KEEP_TABLES = setOf("pending_change_records", "sequences")

        /** Что выполнить для очистки: по одному DELETE на каждую таблицу, кроме [KEEP_TABLES]. Чистая функция — покрыта тестами на настоящем SQLite. */
        fun wipeStatements(allTables: List<String>): List<String> =
            allTables.filter { it !in KEEP_TABLES && !it.startsWith("sqlite_") && !it.startsWith("android_") && !it.startsWith("room_") }
                .map { "DELETE FROM `$it`" }
    }
}
