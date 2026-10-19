package com.megablok10.app.contracts

import com.megablok10.app.qr.ProvisionCode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Короткий код выдачи на стороне приложения против `provision-code.json` (вторая сторона — admin-web, тот же файл). */
class ProvisionCodeContractTest {
    private val vectors = ContractVectors.load("provision-code.json")

    @Test fun alphabetAndLengthAreTheOnesTheServerIssuesFrom() {
        assertEquals(vectors.str("alphabet"), ProvisionCode.ALPHABET)
        assertEquals(vectors.long("length"), ProvisionCode.LENGTH.toLong())
    }

    @Test fun normalizationGivesTheSameAnswersAsTheServer() {
        val all = vectors.list("normalize")
        assertTrue(all.any { it.strOrNull("output") == null } && all.any { it.strOrNull("output") != null })
        for (v in all) assertEquals(v.str("name"), v.strOrNull("output"), ProvisionCode.normalize(v.str("input")))
    }

    @Test fun codesAreShownWithADashInTheMiddle() {
        val all = vectors.list("format")
        assertTrue(all.isNotEmpty())
        for (v in all) assertEquals(v.str("code"), v.str("text"), ProvisionCode.format(v.str("code")))
    }
}
