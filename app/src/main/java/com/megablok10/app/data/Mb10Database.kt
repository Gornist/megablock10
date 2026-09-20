package com.megablok10.app.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

/**
 * Схема наращивается по мере фич, а не строится целиком заранее. До релиза
 * миграции не пишем — схема ещё нестабильна, при её смене Room просто
 * пересоздаст базу (fallbackToDestructiveMigration).
 */
@Database(
    entities = [
        CharacterEntity::class, ShardEntity::class, TransactionEntity::class, DaemonEntity::class,
        ChatMessageEntity::class, CallLogEntity::class, ContainerBreachEntity::class,
        SlotClaimEntity::class, ConsumedTokenEntity::class, PendingAlertEntity::class,
        PendingChangeRecordEntity::class, ItemTransferEntity::class, OutboxEntity::class
    ],
    version = 13,
    exportSchema = false
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
                    // 12 → 13 — настоящая миграция (очередь исходящих), данные игроков не теряются. Всё, что старше, по-прежнему пересоздаёт базу.
                    .addMigrations(MIGRATION_12_13)
                    .fallbackToDestructiveMigration()
                    .build()
                    .also { instance = it }
            }
    }
}

private val MIGRATION_12_13 = object : androidx.room.migration.Migration(12, 13) {
    override fun migrate(db: androidx.sqlite.db.SupportSQLiteDatabase) {
        db.execSQL(
            "CREATE TABLE IF NOT EXISTS `outbox` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `toPubKeyB64` TEXT NOT NULL, " +
                "`wireLine` TEXT NOT NULL, `createdAt` INTEGER NOT NULL, `attempts` INTEGER NOT NULL, `nextAttemptAt` INTEGER NOT NULL)"
        )
    }
}
