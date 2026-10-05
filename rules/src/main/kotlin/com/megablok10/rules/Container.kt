package com.megablok10.rules

/** Что лежит в слоте — определяет, во что превращается payload после расшифровки. */
enum class LootType { SHARD, DAEMON }

/**
 * Один приз в контейнере. payload — зашифрованное (LootCrypto) и base64
 * содержимое, формат зависит от [type] (см. LootCodec) — сам Container не
 * знает, что внутри, просто носит непрозрачный блок до момента извлечения.
 * copies — тираж: 0 значит бесконечно (можно извлекать много раз, обычно
 * для BASE-лута), N > 0 — конечный тираж, эксклюзивность которого следит
 * SlotClaimStore (см. это же имя).
 */
data class LootSlot(
    val type: LootType,
    val tier: Tier,
    val copies: Int,
    val payload: String
)

/**
 * Контейнер — заменяет старую "точку доступа" (Mb10Qr.AccessPoint остаётся
 * только как устаревший алиас при чтении уже напечатанных QR, см. Mb10Qr.kt).
 * ownerFaction — свободная строка, как и faction везде в приложении (игроки
 * сами вписывают название фракции при создании персонажа, фиксированного
 * списка фракций в игре нет) — получатель сигнала SEC при взломе.
 */
data class Container(
    val id: String,
    val name: String,
    val tier: Tier,
    val ownerFaction: String,
    val loot: List<LootSlot>
) {
    /**
     * Стабильный адрес слота для SlotClaim — позиция в списке, не меняется,
     * пока QR не перепечатан. Разделитель '#', не ':' — slotRef сам попадает
     * полем внутрь ':'-разделённых wire-строк (ClaimProtocol, Mb10Qr.LootGrant),
     * ':' внутри него сдвинул бы там все индексы после разбора split(":").
     */
    fun slotRef(index: Int): String = "$id#$index"
}
