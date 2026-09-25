package com.megablok10.app.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

/**
 * Версия 17 — с 12 и выше данные игроков не стираются никогда (12→13 … 16→17 —
 * настоящие миграции): схема экспортируется в `app/schemas`, и с неё любое
 * изменение обязано сопровождаться миграцией (иначе Room падает при
 * открытии, а не стирает данные игроков молча). Версии 1–11 до релиза
 * стираются, как и раньше. Как менять схему: см. docs/db-migrations.md.
 */
@Database(
    entities = [
        CharacterEntity::class, ShardEntity::class, TransactionEntity::class, DaemonEntity::class,
        ChatMessageEntity::class, CallLogEntity::class, ContainerBreachEntity::class,
        SlotClaimEntity::class, ConsumedTokenEntity::class, PendingAlertEntity::class,
        PendingChangeRecordEntity::class, ItemTransferEntity::class, OutboxEntity::class,
        SequenceEntity::class, AcceptedChangeRecordEntity::class,
    ],
    version = 17,
    exportSchema = true
)
abstract class Mb10Database : RoomDatabase() {
    abstract fun characterDao(): CharacterDao
    abstract fun shardDao(): ShardDao
    abstract fun transactionDao(): TransactionDao
    abstract fun daemonDao(): DaemonDao
    abstract fun chatMessageDao(): ChatMessageDao
    abstract fun callLogDao(): CallLogDao
    abstract fun containerBreachDao(): ContainerBreachDao
    abstract fun slotClaimDao(): SlotClaimDao
    abstract fun consumedTokenDao(): ConsumedTokenDao
    abstract fun pendingAlertDao(): PendingAlertDao
    abstract fun pendingChangeRecordDao(): PendingChangeRecordDao
    abstract fun itemTransferDao(): ItemTransferDao
    abstract fun outboxDao(): OutboxDao
    abstract fun sequenceDao(): SequenceDao
    abstract fun acceptedChangeRecordDao(): AcceptedChangeRecordDao

    companion object {
        @Volatile private var instance: Mb10Database? = null

        fun get(context: Context): Mb10Database =
            instance ?: synchronized(this) {
                instance ?: Room.databaseBuilder(
                    context.applicationContext,
                    Mb10Database::class.java,
                    "mb10.db"
                )
                    .addMigrations(*ALL_MIGRATIONS)
                    // Только доисторические версии (без экспортированных схем): с 12 и выше данные не стираем никогда.
                    // Версия из этого списка не может быть началом миграции — Room падает при открытии базы (см. MigrationGuardTest).
                    .fallbackToDestructiveMigrationFrom(*DESTRUCTIVE_FROM)
                    .build()
                    .also { instance = it }
            }
    }
}

internal const val OUTBOX_CREATE_SQL =
    "CREATE TABLE IF NOT EXISTS `outbox` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `toPubKeyB64` TEXT NOT NULL, " +
        "`wireLine` TEXT NOT NULL, `createdAt` INTEGER NOT NULL, `attempts` INTEGER NOT NULL, `nextAttemptAt` INTEGER NOT NULL)"

internal val MIGRATION_12_13 = object : androidx.room.migration.Migration(12, 13) {
    override fun migrate(db: androidx.sqlite.db.SupportSQLiteDatabase) {
        db.execSQL(OUTBOX_CREATE_SQL)
    }
}

// Только новые индексы — ни одной таблицы/колонки не меняется, поэтому CREATE INDEX IF NOT EXISTS
// безопасен и идемпотентен сам по себе (в отличие от ALTER TABLE ADD COLUMN, который так писать нельзя).
internal const val TRANSACTIONS_TIMESTAMP_INDEX_SQL =
    "CREATE INDEX IF NOT EXISTS `index_transactions_timestamp` ON `transactions` (`timestamp`)"
internal const val OUTBOX_NEXT_ATTEMPT_INDEX_SQL =
    "CREATE INDEX IF NOT EXISTS `index_outbox_nextAttemptAt` ON `outbox` (`nextAttemptAt`)"

internal val MIGRATION_13_14 = object : androidx.room.migration.Migration(13, 14) {
    override fun migrate(db: androidx.sqlite.db.SupportSQLiteDatabase) {
        db.execSQL(TRANSACTIONS_TIMESTAMP_INDEX_SQL)
        db.execSQL(OUTBOX_NEXT_ATTEMPT_INDEX_SQL)
    }
}

internal const val SEQUENCES_CREATE_SQL =
    "CREATE TABLE IF NOT EXISTS `sequences` (`name` TEXT NOT NULL, `value` INTEGER NOT NULL, PRIMARY KEY(`name`))"

// Счётчик seq записей для мастера переезжает из SharedPreferences в базу. Начальное значение миграция не переносит — SQL не видит
// настроек; его подхватывает первая выдача номера (RoomChangeQueue.nextSeq), взяв максимум из прежнего счётчика и очереди.
internal val MIGRATION_14_15 = object : androidx.room.migration.Migration(14, 15) {
    override fun migrate(db: androidx.sqlite.db.SupportSQLiteDatabase) {
        db.execSQL(SEQUENCES_CREATE_SQL)
    }
}

internal const val ACCEPTED_CREATE_SQL =
    "CREATE TABLE IF NOT EXISTS `accepted_change_records` (`id` TEXT NOT NULL, `subjectKeyB64` TEXT NOT NULL, `seq` INTEGER NOT NULL, " +
        "`happenedAt` INTEGER NOT NULL, `field` TEXT NOT NULL, `oldValue` TEXT, `newValue` TEXT, `reason` TEXT NOT NULL, `sourceRef` TEXT, " +
        "`actor` TEXT NOT NULL, `signature` TEXT NOT NULL, `acceptedAt` INTEGER NOT NULL, PRIMARY KEY(`id`))"
internal const val ACCEPTED_INDEX_SQL =
    "CREATE INDEX IF NOT EXISTS `index_accepted_change_records_acceptedAt` ON `accepted_change_records` (`acceptedAt`)"

// Журнал подтверждённых записей — чтобы дослать их, если сервер восстановят из резервной копии (см. AcceptedChangeRecordEntity).
internal val MIGRATION_15_16 = object : androidx.room.migration.Migration(15, 16) {
    override fun migrate(db: androidx.sqlite.db.SupportSQLiteDatabase) {
        db.execSQL(ACCEPTED_CREATE_SQL)
        db.execSQL(ACCEPTED_INDEX_SQL)
    }
}

internal const val CHAT_STATUS_SQL = "ALTER TABLE `chat_messages` ADD COLUMN `status` INTEGER NOT NULL DEFAULT 0"

// Статус своих личных сообщений (docs/refactor-plan.md, D3): у старых строк — 0 («нет статуса»), история не трогается.
internal val MIGRATION_16_17 = object : androidx.room.migration.Migration(16, 17) {
    override fun migrate(db: androidx.sqlite.db.SupportSQLiteDatabase) {
        // Повтор на уже мигрированной базе не должен падать (как у прошлых миграций): «duplicate column» — колонка уже есть.
        try {
            db.execSQL(CHAT_STATUS_SQL)
        } catch (@Suppress("TooGenericExceptionCaught") e: Exception) {
            val duplicate = generateSequence<Throwable>(e) { it.cause }.any { it.message?.contains("duplicate column", ignoreCase = true) == true }
            if (!duplicate) throw e
        }
    }
}

/** Версии, с которых базу пересоздаём вместо миграции (схемы старше 12 не сохранились). */
internal val DESTRUCTIVE_FROM: IntArray = (1..11).toList().toIntArray()

/** Все миграции по порядку. Новую версию схемы добавляем сюда и в тест MigrationGuardTest. */
internal val ALL_MIGRATIONS = arrayOf(MIGRATION_12_13, MIGRATION_13_14, MIGRATION_14_15, MIGRATION_15_16, MIGRATION_16_17)
