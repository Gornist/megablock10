package com.megablok10.app.collector

import org.junit.Assert.assertEquals
import org.junit.Test

class CounterValueTest {
    @Test fun sameTextAsOrgJsonProducedBefore() {
        // Раньше: JSONObject().put("tier", "HARD").put("outcome", "success").toString() — порядок вставки, без пробелов.
        assertEquals("""{"tier":"HARD","outcome":"success"}""", counterValue("tier" to "HARD", "outcome" to "success"))
        assertEquals("""{"reason":"NO_LINK"}""", counterValue("reason" to "NO_LINK"))
    }

    @Test(expected = IllegalArgumentException::class)
    fun textThatWouldNeedEscapingIsAProgrammingError() {
        counterValue("reason" to "a\"b")
    }
}
