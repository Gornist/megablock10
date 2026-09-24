package com.megablok10.app.qr

import com.megablok10.app.breach.Container
import com.megablok10.app.breach.LootSlot
import com.megablok10.app.breach.LootType
import com.megablok10.app.breach.Tier
import com.megablok10.kit.handover.HandoverRules
import com.megablok10.kit.text.Base64Text.decode as unb64
import com.megablok10.kit.text.Base64Text.encode as b64

/**
 * Единая точка разбора ВСЕХ QR-кодов игры. Тип определяется по второму
 * сегменту после "MB10" — остальные экраны не парсят сырую строку сами,
 * а получают уже типизированный результат отсюда. Новый тип QR добавляется
 * одним новым вариантом sealed-интерфейса и одной веткой в decode().
 *
 * Свободный текст (позывной, имя точки, текст шарда) кодируется в base64,
 * а не пишется как есть между двоеточиями — иначе любой ":" внутри текста
 * автора QR-кода (мастера игры) сломал бы разбор.
 */
enum class ItemKind { SHARD, DAEMON }

sealed interface Mb10Qr {
    data class Contact(
        val publicKeyB64: String,
        val callsign: String,
        val faction: String
    ) : Mb10Qr

    /**
     * Контейнер — заменяет старую "точку доступа" (ревизия v9). Печатается
     * мастерами на месте, несёт свой тир (сложность взлома) и список лута.
     * Уже напечатанные до ревизии "AP"-коды по-прежнему читаются — см.
     * decodeLegacyAccessPoint — как контейнер тира BASE без лута.
     */
    data class ContainerQr(val container: Container) : Mb10Qr

    /**
     * Шард — печатается мастерами на месте либо выдаётся как лут контейнера.
     * moneyAmount — необязательные деньги внутри шарда (0, если их нет):
     * зачисляются один раз, в момент скана, тем же путём, что и находка
     * наличных в тайнике — не переводом от другого игрока. tier/valueHint —
     * ревизия v9: тир для длины цели расшифровки и текст-подсказка ценности
     * для отыгрыша торга (приложение цену не считает). badge убран —
     * ярлык теперь вычисляется из decryptAction+tier при отображении, не
     * задаётся мастером отдельно (раньше эти два поля могли противоречить
     * друг другу).
     *
     * decrypted — локальное состояние устройства, а не часть QR: шард с
     * decryptAction = true рождается нерасшифрованным (см. ShardStore.add)
     * и текст его body скрыт в UI, пока игрок не пройдёт мини-взлом
     * (ShardDecryptFlow в BreachScreen.kt). У шардов без decryptAction
     * это поле не имеет смысла, поэтому по умолчанию true (не заблокирован).
     */
    data class Shard(
        val id: String,
        val decryptAction: Boolean,
        val tier: Int,
        val valueHint: String,
        val title: String,
        val meta: String,
        val body: String,
        val moneyAmount: Long = 0,
        val decrypted: Boolean = true
    ) : Mb10Qr

    /** RAM-апгрейд деки — токен одноразовый (см. RamUpgradeStore), delta прибавляется к Identity.ramCapacity с потолком RAM_CAPACITY_MAX. */
    data class RamUpgrade(val token: String, val delta: Int) : Mb10Qr

    /**
     * Ручная выдача одного слота лута живым мастером в обход авто-извлечения
     * (ревизия v9 §6 — для самого ценного, тир 3: игрок видит "ФРАГМЕНТ
     * ИЗВЛЕЧЁН · ТРЕБУЕТСЯ ДЕШИФРОВКА" и идёт к мастеру за этим QR).
     * encryptedPayload — тот же формат, что у LootSlot.payload, тот же
     * LootCodec/LootCrypto читает оба пути одинаково.
     */
    data class LootGrant(val slotRef: String, val type: LootType, val tier: Tier, val encryptedPayload: String) : Mb10Qr

    /**
     * Сигнал СБ — не QR в смысле "сканируется", а тело обычного фракционного
     * чат-сообщения (см. ChatScreen.MessageBubble, тот же трюк, что и у
     * PaymentBubble): SecAlertStore кодирует этим кодеком и шлёт как body
     * FACTION-сообщения от системного псевдо-контакта "SEC//MB10". tier
     * определяет, что видно фракции — см. ревизию v9 §4: BASE — только факт
     * и имя узла, HARD — плюс intruderCallsign, NIGHTMARE — плюс точное время.
     * intruderCallsign = null, если демон Ghost убрал ID; preciseAt = null,
     * если тир не NIGHTMARE.
     */
    data class SecurityAlert(
        val containerId: String,
        val containerName: String,
        val tier: Int,
        val intruderCallsign: String?,
        val preciseAt: Long?
    ) : Mb10Qr

    /**
     * Подписанная денежная транзакция. Плательщик генерирует и показывает
     * QR — деньги у него списываются сразу в момент генерации (как передача
     * наличных из рук в руки), получатель сканирует и зачисляет их себе.
     * fromPubKeyB64 — тот же ключ, что и в Contact, подпись проверяется им же.
     */
    data class Transaction(
        val id: String,
        val fromPubKeyB64: String,
        /** Кому адресован платёж — входит в подпись: чужую копию карточки (у сообщника, из перехваченного трафика) принять нельзя. */
        val toPubKeyB64: String,
        val amount: Long,
        val memo: String,
        val signatureB64: String
    ) : Mb10Qr

    /**
     * Передача шарда или демона другому игроку — тот же протокол, что у денег (Transaction/Receipt):
     * карточка в чате, «Принять» у получателя, чек в ответ, отмена только пока карточка не доставлена.
     * payload — предмет целиком (см. ItemTransferStore.encodeShardPayload/encodeDaemonPayload), подписан отправителем.
     */
    data class ItemTransfer(
        val id: String,
        val fromPubKeyB64: String,
        /** Адресат передачи — входит в подпись (см. Transaction.toPubKeyB64). */
        val toPubKeyB64: String,
        val kind: ItemKind,
        val payload: String,
        val signatureB64: String
    ) : Mb10Qr

    /**
     * QR персонажа от мастера (docs/provisioning-qr.md): всё, что нужно телефону на первом запуске, одним кодом — сервер, код игры и сам
     * персонаж. Применяется один раз (ProvisionStore); повторно только после сброса сессии и с новым QR. [id] — уникальный номер выдачи,
     * по нему приложение (и сервер) узнают уже использованный код. Пустые [collectorUrl]/[gameSecret] — оставить как в сборке; [ramCapacity] 0 — по умолчанию.
     */
    data class Provision(
        val id: String,
        val collectorUrl: String,
        val gameSecret: String,
        val callsign: String,
        val faction: String,
        val startBalance: Long,
        val ramCapacity: Int
    ) : Mb10Qr

    /**
     * Подтверждение получения — показывает получатель в ответ, отправитель
     * сканирует его, чтобы зафиксировать транзакцию (см. TransactionStore).
     * До этого момента отправитель ещё может отменить платёж и вернуть себе
     * деньги; после — нет, ровно для того, чтобы "отменить и оставить деньги
     * себе" было невозможно, если получатель уже реально получил перевод.
     */
    data class Receipt(
        val id: String,
        val receiverPubKeyB64: String,
        val signatureB64: String
    ) : Mb10Qr
}

object Mb10QrCodec {
    private const val MAGIC = "MB10"

    fun decode(raw: String): Mb10Qr? {
        val parts = raw.split(":")
        if (parts.size < 2 || parts[0] != MAGIC) return null
        return try {
            when (parts[1]) {
                "CONTACT" -> decodeContact(parts)
                "AP" -> decodeLegacyAccessPoint(parts)
                "CONTAINER" -> decodeContainer(parts)
                "SHARD" -> decodeShard(parts)
                "RAM" -> decodeRamUpgrade(parts)
                "GRANT" -> decodeLootGrant(parts)
                "SECALERT" -> decodeSecurityAlert(parts)
                "TX" -> decodeTransaction(parts)
                "ITEM" -> decodeItemTransfer(parts)
                "PROV" -> decodeProvision(parts)
                "RCPT" -> decodeReceipt(parts)
                else -> null
            }
        } catch (e: Exception) {
            null
        }
    }

    fun encodeContact(publicKeyB64: String, callsign: String, faction: String): String =
        "$MAGIC:CONTACT:v1:$publicKeyB64:$callsign:$faction"

    private fun decodeContact(parts: List<String>): Mb10Qr.Contact? {
        if (parts.size < 6) return null
        return Mb10Qr.Contact(
            publicKeyB64 = parts[3],
            callsign = parts[4],
            faction = parts[5]
        )
    }

    /** Старые (до ревизии v9) точки доступа без тира и лута — читаются как контейнер тира BASE, пустой лут. */
    private fun decodeLegacyAccessPoint(parts: List<String>): Mb10Qr.ContainerQr? {
        if (parts.size < 5) return null
        return Mb10Qr.ContainerQr(Container(id = parts[3], name = unb64(parts[4]), tier = Tier.BASE, ownerFaction = "", loot = emptyList()))
    }

    fun encodeContainer(container: Container): String {
        val loot = container.loot.joinToString(";") { "${it.type.name},${it.tier.level},${it.copies},${it.payload}" }
        return "$MAGIC:CONTAINER:v1:${container.id}:${b64(container.name)}:${container.tier.level}:${b64(container.ownerFaction)}:${b64(loot)}"
    }

    private fun decodeContainer(parts: List<String>): Mb10Qr.ContainerQr? {
        if (parts.size < 8) return null
        val lootBlob = unb64(parts[7])
        val loot = if (lootBlob.isEmpty()) emptyList() else lootBlob.split(";").mapNotNull { slot ->
            val f = slot.split(",", limit = 4)
            if (f.size < 4) return@mapNotNull null
            val type = LootType.entries.find { it.name == f[0] } ?: return@mapNotNull null
            LootSlot(type = type, tier = Tier.fromLevel(f[1].toIntOrNull() ?: 1), copies = f[2].toIntOrNull() ?: 0, payload = f[3])
        }
        return Mb10Qr.ContainerQr(
            Container(
                id = parts[3],
                name = unb64(parts[4]),
                tier = Tier.fromLevel(parts[5].toIntOrNull() ?: 1),
                ownerFaction = unb64(parts[6]),
                loot = loot
            )
        )
    }

    fun encodeShard(
        id: String,
        decryptAction: Boolean,
        tier: Int,
        valueHint: String,
        title: String,
        meta: String,
        body: String,
        moneyAmount: Long = 0
    ): String = "$MAGIC:SHARD:v1:$id:${if (decryptAction) 1 else 0}:$tier:${b64(valueHint)}:${b64(title)}:${b64(meta)}:${b64(body)}:$moneyAmount"

    private fun decodeShard(parts: List<String>): Mb10Qr.Shard? {
        if (parts.size < 10) return null
        return Mb10Qr.Shard(
            id = parts[3],
            decryptAction = parts[4] == "1",
            tier = parts[5].toIntOrNull() ?: 1,
            valueHint = unb64(parts[6]),
            title = unb64(parts[7]),
            meta = unb64(parts[8]),
            body = unb64(parts[9]),
            moneyAmount = parts.getOrNull(10)?.toLongOrNull() ?: 0
        )
    }

    private fun decodeRamUpgrade(parts: List<String>): Mb10Qr.RamUpgrade? {
        if (parts.size < 5) return null
        val delta = parts[4].toIntOrNull() ?: return null
        return Mb10Qr.RamUpgrade(token = parts[3], delta = delta)
    }

    private fun decodeLootGrant(parts: List<String>): Mb10Qr.LootGrant? {
        if (parts.size < 7) return null
        val type = LootType.entries.find { it.name == parts[4] } ?: return null
        return Mb10Qr.LootGrant(slotRef = parts[3], type = type, tier = Tier.fromLevel(parts[5].toIntOrNull() ?: 1), encryptedPayload = parts[6])
    }

    fun encodeSecurityAlert(alert: Mb10Qr.SecurityAlert): String = listOf(
        MAGIC, "SECALERT", "v1", alert.containerId, b64(alert.containerName), alert.tier.toString(),
        alert.intruderCallsign?.let { b64(it) } ?: "", alert.preciseAt?.toString() ?: ""
    ).joinToString(":")

    private fun decodeSecurityAlert(parts: List<String>): Mb10Qr.SecurityAlert? {
        if (parts.size < 8) return null
        return Mb10Qr.SecurityAlert(
            containerId = parts[3],
            containerName = unb64(parts[4]),
            tier = parts[5].toIntOrNull() ?: 1,
            intruderCallsign = parts[6].takeIf { it.isNotEmpty() }?.let { unb64(it) },
            preciseAt = parts[7].toLongOrNull()
        )
    }

    /** Карточки платежа и передачи — формат v2 (адресат в подписи). v1 не принимается: иначе защиту обошли бы старым форматом. */
    fun encodeProvision(p: Mb10Qr.Provision): String =
        "$MAGIC:PROV:v1:${p.id}:${b64(p.collectorUrl)}:${b64(p.gameSecret)}:${b64(p.callsign)}:${b64(p.faction)}:${p.startBalance}:${p.ramCapacity}"

    private fun decodeProvision(parts: List<String>): Mb10Qr.Provision? {
        if (parts.size < 10 || parts[2] != "v1") return null
        return Mb10Qr.Provision(
            id = parts[3],
            collectorUrl = unb64(parts[4]),
            gameSecret = unb64(parts[5]),
            callsign = unb64(parts[6]),
            faction = unb64(parts[7]),
            startBalance = parts[8].toLongOrNull() ?: return null,
            ramCapacity = parts[9].toIntOrNull() ?: return null
        )
    }

    fun encodeTransaction(tx: Mb10Qr.Transaction): String =
        "$MAGIC:TX:v2:${tx.id}:${tx.fromPubKeyB64}:${tx.toPubKeyB64}:${tx.amount}:${b64(tx.memo)}:${tx.signatureB64}"

    private fun decodeTransaction(parts: List<String>): Mb10Qr.Transaction? {
        if (parts.size < 9 || parts[2] != "v2") return null
        val amount = parts[6].toLongOrNull() ?: return null
        return Mb10Qr.Transaction(
            id = parts[3],
            fromPubKeyB64 = parts[4],
            toPubKeyB64 = parts[5],
            amount = amount,
            memo = unb64(parts[7]),
            signatureB64 = parts[8]
        )
    }

    /** Байты, которые подписывает плательщик и проверяет получатель — одна и та же формула по обе стороны. */
    fun transactionSignaturePayload(id: String, fromPubKeyB64: String, toPubKeyB64: String, amount: Long, memo: String): ByteArray =
        "TX2|$id|$fromPubKeyB64|$toPubKeyB64|$amount|$memo".toByteArray(Charsets.UTF_8)

    fun encodeItemTransfer(t: Mb10Qr.ItemTransfer): String =
        "$MAGIC:ITEM:v2:${t.id}:${t.fromPubKeyB64}:${t.toPubKeyB64}:${t.kind.name}:${b64(t.payload)}:${t.signatureB64}"

    private fun decodeItemTransfer(parts: List<String>): Mb10Qr.ItemTransfer? {
        if (parts.size < 9 || parts[2] != "v2") return null
        val kind = ItemKind.entries.find { it.name == parts[6] } ?: return null
        return Mb10Qr.ItemTransfer(id = parts[3], fromPubKeyB64 = parts[4], toPubKeyB64 = parts[5], kind = kind, payload = unb64(parts[7]), signatureB64 = parts[8])
    }

    /** Байты, которые подписывает отправитель предмета и проверяет получатель. */
    fun itemTransferSignaturePayload(id: String, fromPubKeyB64: String, toPubKeyB64: String, kind: ItemKind, payload: String): ByteArray =
        "ITEM2|$id|$fromPubKeyB64|$toPubKeyB64|${kind.name}|$payload".toByteArray(Charsets.UTF_8)

    fun encodeReceipt(receipt: Mb10Qr.Receipt): String =
        "$MAGIC:RCPT:v1:${receipt.id}:${receipt.receiverPubKeyB64}:${receipt.signatureB64}"

    private fun decodeReceipt(parts: List<String>): Mb10Qr.Receipt? {
        if (parts.size < 6) return null
        return Mb10Qr.Receipt(id = parts[3], receiverPubKeyB64 = parts[4], signatureB64 = parts[5])
    }

    /** Байты, которые подписывает получатель на чеке — та же id, что и у исходной транзакции, плюс его ключ (kit [HandoverRules]). */
    fun receiptSignaturePayload(id: String, receiverPubKeyB64: String): ByteArray =
        HandoverRules.receiptSignaturePayload(id, receiverPubKeyB64)
}
