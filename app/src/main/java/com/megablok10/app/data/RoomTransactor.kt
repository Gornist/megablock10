package com.megablok10.app.data

import androidx.room.withTransaction
import com.megablok10.kit.sync.NestingTransactor
import com.megablok10.kit.sync.Transactor

/**
 * Транзакции базы приложения как kit [Transactor]: изменение игровых данных и запись о нём для мастера фиксируются одним коммитом.
 * Все транзакции приложения открываются через него, а не через `db.withTransaction` напрямую, — иначе вложенная запись не узнает
 * о внешней транзакции и разбудит синхронизацию до её коммита.
 */
class RoomTransactor(db: Mb10Database) : Transactor by NestingTransactor({ block -> db.withTransaction { block() } })
