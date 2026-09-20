package com.megablok10.app.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

/**
 * Версия 13 — базовая: схема экспортируется в `app/schemas`, и с неё любое изменение
 * обязано сопровождаться миграцией (иначе Room падает при открытии, а не стирает
 * данные игроков молча). Версии 1–12 до релиза стираются, как и раньше.
 * Как менять схему: см. docs/db-migrations.md.
 */
@Database(
    entities = [
        CharacterEntity::class, ShardEntity::class, TransactionEntity::class, DaemonEntity::class,
        ChatMessageEntity::class, CallLogEntity::class, ContainerBreachEntity::class,
        SlotClaimEntity::class, ConsumedTokenEntity::class, PendingAlertEntity::class,
        PendingChangeRecordEntity::class, ItemTransferEntity::class, OutboxEntity::class
    ],
    version = 13,
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
                    // Только доисторические версии: с 13 и выше данные не стираем никогда.
                    .fallbackToDestructiveMigrationFrom(*(1..12).toList().toIntArray())
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

/** Все миграции по порядку. Новую версию схемы добавляем сюда и в тест MigrationGuardTest. */
internal val ALL_MIGRATIONS = arrayOf(MIGRATION_12_13)
