package com.megablok10.app.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

/**
 * Схема наращивается по мере фич (Character/Shard/Transaction сейчас,
 * Container — когда появятся полноценные контейнеры), а не строится целиком
 * заранее. До релиза миграции не пишем — схема ещё нестабильна, при её смене
 * Room просто пересоздаст базу (fallbackToDestructiveMigration).
 */
@Database(
    entities = [CharacterEntity::class, ShardEntity::class, TransactionEntity::class, DaemonEntity::class],
    version = 3,
    exportSchema = false
)
abstract class Mb10Database : RoomDatabase() {
    abstract fun characterDao(): CharacterDao
    abstract fun shardDao(): ShardDao
    abstract fun transactionDao(): TransactionDao
    abstract fun daemonDao(): DaemonDao

    companion object {
        @Volatile private var instance: Mb10Database? = null

        fun get(context: Context): Mb10Database =
            instance ?: synchronized(this) {
                instance ?: Room.databaseBuilder(
                    context.applicationContext,
                    Mb10Database::class.java,
                    "mb10.db"
                )
                    .fallbackToDestructiveMigration()
                    .build()
                    .also { instance = it }
            }
    }
}
