package com.megablok10.app.collector

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ProvisionRejectionTest {
    @Test fun recognisesBothServerMessages() {
        assertTrue(ProvisionRejection.isProvisionError("provision code already applied on another device"))
        assertTrue(ProvisionRejection.isProvisionError("provision code is no longer valid (issued again)"))
        assertTrue(ProvisionRejection.isProvisionError("  Provision code is no longer valid (issued again)  "))
    }

    @Test fun ignoresOtherRejections() {
        assertFalse(ProvisionRejection.isProvisionError("malformed record"))
        assertFalse(ProvisionRejection.isProvisionError("unknown field: x"))
        assertFalse(ProvisionRejection.isProvisionError(""))
        assertFalse(ProvisionRejection.anyProvisionError(listOf("bad signature", "unknown reason: FOO")))
    }

    @Test fun anyOfManyIsEnough() {
        assertTrue(ProvisionRejection.anyProvisionError(listOf("malformed record", "provision code already applied on another device")))
    }
}
