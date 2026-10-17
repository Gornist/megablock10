package com.megablok10.app.contracts

import com.megablok10.app.collector.ChangeField
import com.megablok10.app.collector.ChangeReason
import com.megablok10.kit.crypto.Ecdsa
import com.megablok10.kit.sync.ChangeRecord
import com.megablok10.kit.sync.signaturePayload
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Запись изменений на стороне приложения против `change-record.json` (вторая сторона — admin-web `changeRecord.ts`, третья — Мост). */
class ChangeRecordContractTest {
    private val vectors = ContractVectors.load("change-record.json")

    @Test fun signaturePayloadBytesMatchTheSharedVectors() {
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

    @Test fun signaturesVerifyTheSameWayEverywhere() {
        val all = vectors.list("signature")
        assertTrue(all.any { it.bool("valid") } && all.any { !it.bool("valid") })
        for (v in all) {
            val ok = Ecdsa.verify(v.str("publicKeyB64"), v.str("payload_utf8").toByteArray(Charsets.UTF_8), v.str("signatureB64"))
            assertEquals(v.str("name"), v.bool("valid"), ok)
        }
    }

    @Test fun deviceFieldsAndReasonsAreExactlyTheListsTheServerAccepts() {
        val fields = vectors.obj("fields")
        // announcement приходит только от мастера: устройство такую запись не создаёт, но константа у приложения есть
        assertEquals(fields.getValue("device").strings().toSet() + fields.getValue("master_only").strings(), ContractVectors.stringConstants(ChangeField::class.java))
        assertEquals(vectors.obj("reasons").getValue("device").strings().toSet(), ContractVectors.stringConstants(ChangeReason::class.java))
    }
}
