package com.megablok10.app.cyberdeck

import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.shards.ShardCollection

/** Что Кибердека сообщает игроку и какая коллекция пополнилась — экран сам решает, как это показать (см. CyberdeckViewModel). */
sealed interface ScanEffect {
    data class Notice(val text: String) : ScanEffect
    data class Collected(val kind: CollectedKind) : ScanEffect
}

enum class CollectedKind { Shard }

/**
 * Сценарий «Кибердека отсканировала объект, отличный от контейнера»: шард или RAM-токен. Контейнеры сюда не попадают —
 * их проверяет [com.megablok10.app.breach.CheckBreachAccess]. Вынесен из CyberdeckViewModel, чтобы маршрутизацию
 * типов QR можно было проверить юнит-тестом отдельно от Compose/ViewModel.
 */
class ScanObject(
    private val shards: ShardCollection,
    private val applyRamUpgrade: suspend (Mb10Qr.RamUpgrade) -> Int?,
) {
    suspend operator fun invoke(qr: Mb10Qr): List<ScanEffect> = when (qr) {
        is Mb10Qr.Shard -> {
            shards.add(qr)
            listOf(ScanEffect.Collected(CollectedKind.Shard))
        }
        is Mb10Qr.RamUpgrade -> {
            val capacity = applyRamUpgrade(qr)
            listOf(ScanEffect.Notice(if (capacity != null) "RAM деки увеличена до $capacity" else "Этот RAM-токен уже был применён"))
        }
        else -> listOf(ScanEffect.Notice("Этот QR не распознан Кибердекой"))
    }
}
