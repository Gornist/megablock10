package com.megablok10.netrun.bridge.contracts

import com.megablok10.kit.crypto.Ecdsa
import com.megablok10.kit.sync.ChangeRecord
import com.megablok10.kit.sync.signaturePayload
import com.megablok10.netrun.bridge.collector.FakeCollector
import com.megablok10.netrun.bridge.collector.WorldRecords
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Записи мира Моста против `change-record.json`. Мост подписывает записи kit-ным `signaturePayload` (`WorldRecorder`), а коллектор в тестах
 * Моста (`FakeCollector`) пересчитывает байты по формуле TS-коллектора: обе копии обязаны дать байты из файла.
 */
class ChangeRecordContractTest {
    private val vectors = ContractVectors.load("change-record.json")

    @Test fun байтыПодписиЗаписиКакУМоста() {
        val all = vectors.list("payload")
        assertTrue(all.isNotEmpty())
        for (v in all) {
            val r = v.obj("record")
            val record = ChangeRecord(
                id = r.str("id"), subjectKeyB64 = r.str("subjectKeyB64"), seq = r.long("seq"), happenedAt = r.long("happenedAt"),
                field = r.str("field"), oldValue = r.strOrNull("oldValue"), newValue = r.strOrNull("newValue"), reason = r.str("reason"),
                sourceRef = r.strOrNull("sourceRef"), actor = r.str("actor"), signature = "",
            )
            assertEquals(v.str("name"), v.str("payload_utf8"), String(record.signaturePayload(), Charsets.UTF_8))
        }
    }

    @Test fun байтыПодписиЗаписиКакУПроверкиКоллектораВТестахМоста() {
        for (v in vectors.list("payload")) {
            assertEquals(v.str("name"), v.str("payload_utf8"), FakeCollector.signaturePayload(v.obj("record")))
        }
    }

    @Test fun подписиПроверяютсяКакВезде() {
        val all = vectors.list("signature")
        assertTrue(all.any { it.bool("valid") } && all.any { !it.bool("valid") })
        for (v in all) {
            val ok = Ecdsa.verify(v.str("publicKeyB64"), v.str("payload_utf8").toByteArray(Charsets.UTF_8), v.str("signatureB64"))
            assertEquals(v.str("name"), v.bool("valid"), ok)
        }
    }

    @Test fun поляИПричиныМираРовноТеЧтоВоВекторах() {
        val fields = vectors.obj("fields").getValue("world").strings().toSet()
        val reasons = vectors.obj("reasons").getValue("world").strings().toSet()
        assertEquals("поля мира", fields, setOf(WorldRecords.RUN, WorldRecords.ITEM, WorldRecords.ALERT, WorldRecords.BREACH))
        assertEquals(
            "причины мира", reasons,
            setOf(WorldRecords.ENTER, WorldRecords.EXIT, WorldRecords.FLATLINE, WorldRecords.ITEM_OWNER, WorldRecords.ALERT_REASON, WorldRecords.BREACH_REASON),
        )
    }
}
