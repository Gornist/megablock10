package com.megablok10.app.contracts

import com.megablok10.app.breach.Container
import com.megablok10.app.breach.LootSlot
import com.megablok10.app.breach.LootType
import com.megablok10.app.breach.Tier
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.qr.Mb10QrCodec
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** QR контейнера, шарда, RAM, персонажа и сигнала СБ против `qr.json` (вторая копия — TS `mb10QrCodec.ts`, третья — Мост `PhoneWire`). */
class QrContractTest {
    private val vectors = ContractVectors.load("qr.json")

    @Test fun containerLines() {
        val all = vectors.list("containers")
        assertTrue(all.isNotEmpty())
        for (v in all) {
            val slots = v.list("loot").map { LootSlot(LootType.valueOf(it.str("type")), Tier.fromLevel(it.long("tier").toInt()), it.long("copies").toInt(), it.str("payload")) }
            val container = Container(v.str("id"), v.str("containerName"), Tier.fromLevel(v.long("tier").toInt()), v.str("ownerFaction"), slots)
            assertEquals(v.str("name"), v.str("line"), Mb10QrCodec.encodeContainer(container))
            assertEquals(v.str("name"), Mb10Qr.ContainerQr(container), Mb10QrCodec.decode(v.str("line")))
        }
    }

    @Test fun shardLines() {
        val all = vectors.list("shards")
        assertTrue(all.isNotEmpty())
        for (v in all) {
            val shard = Mb10Qr.Shard(v.str("id"), v.bool("decryptAction"), v.long("tier").toInt(), v.str("valueHint"), v.str("title"), v.str("meta"), v.str("body"), v.long("moneyAmount"))
            val line = Mb10QrCodec.encodeShard(shard.id, shard.decryptAction, shard.tier, shard.valueHint, shard.title, shard.meta, shard.body, shard.moneyAmount)
            assertEquals(v.str("name"), v.str("line"), line)
            assertEquals(v.str("name"), shard, Mb10QrCodec.decode(v.str("line")))
        }
    }

    /** Приложение RAM-апгрейд только читает (печатает Мастерская) — кодировщика в Kotlin нет. */
    @Test fun ramUpgradeLines() {
        val all = vectors.list("ram")
        assertTrue(all.isNotEmpty())
        for (v in all) {
            assertEquals(v.str("name"), Mb10Qr.RamUpgrade(v.str("token"), v.long("delta").toInt()), Mb10QrCodec.decode(v.str("line")))
        }
    }

    @Test fun provisionLines() {
        val all = vectors.list("provisions")
        assertTrue(all.isNotEmpty())
        for (v in all) {
            val provision = Mb10Qr.Provision(v.str("id"), v.str("collectorUrl"), v.str("gameSecret"), v.str("callsign"), v.str("faction"), v.long("startBalance"), v.long("ramCapacity").toInt())
            assertEquals(v.str("name"), v.str("line"), Mb10QrCodec.encodeProvision(provision))
            assertEquals(v.str("name"), provision, Mb10QrCodec.decode(v.str("line")))
        }
    }

    @Test fun securityAlertLines() {
        val all = vectors.list("secAlerts")
        assertTrue(all.isNotEmpty())
        for (v in all) {
            val alert = Mb10Qr.SecurityAlert(v.str("containerId"), v.str("containerName"), v.long("tier").toInt(), v.strOrNull("intruderCallsign"), v.strOrNull("preciseAt")?.toLong())
            assertEquals(v.str("name"), v.str("line"), Mb10QrCodec.encodeSecurityAlert(alert))
            assertEquals(v.str("name"), alert, Mb10QrCodec.decode(v.str("line")))
        }
    }
}
