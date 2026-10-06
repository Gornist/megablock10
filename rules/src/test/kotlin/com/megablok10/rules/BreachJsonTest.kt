package com.megablok10.rules

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * netrun/data/rules/breach.json — копия чисел и реплик взлома для GDScript-порта (design §10.3). Источник правды — константы
 * в :rules; тест строит то же дерево из них и сравнивает с файлом. Разошлись — красный CI с этой стороны (gdUnit читает тот же файл).
 */
class BreachJsonTest {
    private fun obj(vararg pairs: Pair<String, JsonElement>) = JsonObject(mapOf(*pairs))
    private fun num(n: Number) = JsonPrimitive(n)
    private fun str(s: String) = JsonPrimitive(s)
    private fun strs(l: List<String>) = JsonArray(l.map(::str))
    private fun range(r: IntRange) = JsonArray(listOf(num(r.first), num(r.last)))

    private fun fromCode(): JsonObject {
        val tiers = Tier.entries.associate { tier ->
            val p = BreachTierParams.forTier(tier)
            tier.name to obj(
                "level" to num(tier.level),
                "grid_size" to num(p.gridSize),
                "timer_sec" to num(p.timerSec),
                "dead_cells" to range(p.deadCellsRange),
                "corrupted_codes" to range(p.corruptedCodesRange),
                "lock_length" to num(p.lockLength),
                "buffer_slack" to num(p.bufferSlack),
                "cipher_timer_sec" to num(p.cipherTimerSec),
                "fail_penalty" to obj(
                    "lock_step" to num(p.failPenaltyLockStep),
                    "trap_step" to num(p.failPenaltyTrapStep),
                    "max_steps" to num(p.failPenaltyMaxSteps),
                    "minutes" to num(p.failPenaltyMinutes),
                ),
                "eddies" to range(ContainerEddies.rollRange(tier)),
                "miner_bonus" to num(ContainerEddies.minerBonus(tier)),
            )
        }
        val ice = Tier.entries.associate { tier ->
            tier.name to JsonObject(IceEvent.entries.associate { e -> e.name to strs(IceLines.linesFor(tier, e)) })
        }
        return obj(
            "format" to num(1),
            "note" to str("Сгенерировано тестом BreachJsonTest из констант :rules (UPDATE_NETRUN_JSON=1). Руками не править."),
            "alphabet" to strs(BreachSymbols.ALPHABET),
            "dead_marker" to str(BreachSymbols.DEAD_MARKER),
            "tiers" to JsonObject(tiers),
            "jitter_bonus_sec" to num(BreachConstants.JITTER_BONUS_SEC),
            "container_cooldown_minutes" to num(BreachConstants.CONTAINER_COOLDOWN_MINUTES),
            "low_time_sec" to num(BreachConstants.LOW_TIME_SEC),
            "warning_sec" to num(BreachConstants.WARNING_SEC),
            "time_events_min_timer_sec" to num(BreachConstants.TIME_EVENTS_MIN_TIMER_SEC),
            "decrypt" to obj(
                "target_length_by_shard_tier" to JsonArray(BreachConstants.SHARD_DECRYPT_TARGET_LENGTH.map(::num)),
                "buffer_extra" to num(BreachConstants.DECRYPT_BUFFER_EXTRA),
            ),
            "ice_lines" to JsonObject(ice),
        )
    }

    @Test
    fun `breach json matches the constants in code`() {
        val expected = fromCode()
        val actual = NetrunJsonFiles.load(PATH, expected)
        assertEquals("netrun/data/rules/breach.json разошёлся с константами :rules", expected, actual)
    }

    private companion object {
        const val PATH = "netrun/data/rules/breach.json"
    }
}
