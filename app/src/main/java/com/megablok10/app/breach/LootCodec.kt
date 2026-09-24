package com.megablok10.app.breach

import com.megablok10.kit.text.Base64Text.decode as unb64
import com.megablok10.kit.text.Base64Text.encode as b64

/**
 * Формат содержимого лут-слота ДО шифрования (LootCrypto оборачивает
 * результат этого кодека, а не наоборот) — тот же стиль, что у Mb10QrCodec:
 * поля через '|', свободный текст в base64. Один и тот же payload читают и
 * при автоматическом извлечении демоном, и при ручной выдаче мастером через
 * Mb10Qr.LootGrant — формат общий для обоих путей.
 */
object LootCodec {
    fun encodeShard(title: String, meta: String, body: String, valueHint: String, decryptAction: Boolean, moneyAmount: Long): String =
        listOf("SHARD", b64(title), b64(meta), b64(body), b64(valueHint), if (decryptAction) "1" else "0", moneyAmount.toString())
            .joinToString("|")

    fun encodeDaemon(name: String, sequence: List<String>, tier: Tier, effect: DaemonEffect): String =
        listOf("DAEMON", b64(name), sequence.joinToString(","), tier.level.toString(), effect.name).joinToString("|")

    sealed interface Loot {
        data class ShardLoot(
            val title: String,
            val meta: String,
            val body: String,
            val valueHint: String,
            val decryptAction: Boolean,
            val moneyAmount: Long
        ) : Loot

        data class DaemonLoot(val name: String, val sequence: List<String>, val tier: Tier, val effect: DaemonEffect) : Loot
    }

    fun decode(plain: String): Loot? {
        val parts = plain.split("|")
        if (parts.isEmpty()) return null
        return try {
            when (parts[0]) {
                "SHARD" -> {
                    if (parts.size < 7) return null
                    Loot.ShardLoot(
                        title = unb64(parts[1]),
                        meta = unb64(parts[2]),
                        body = unb64(parts[3]),
                        valueHint = unb64(parts[4]),
                        decryptAction = parts[5] == "1",
                        moneyAmount = parts[6].toLongOrNull() ?: 0
                    )
                }
                "DAEMON" -> {
                    if (parts.size < 5) return null
                    Loot.DaemonLoot(
                        name = unb64(parts[1]),
                        sequence = parts[2].split(","),
                        tier = Tier.fromLevel(parts[3].toIntOrNull() ?: 1),
                        effect = DaemonEffect.entries.find { it.name == parts[4] } ?: DaemonEffect.EXTRACT_SHARD
                    )
                }
                else -> null
            }
        } catch (e: Exception) {
            null
        }
    }
}
