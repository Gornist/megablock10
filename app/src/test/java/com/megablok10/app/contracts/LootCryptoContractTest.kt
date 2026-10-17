package com.megablok10.app.contracts

import com.megablok10.app.breach.LootCrypto
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Ключ и формат блока лута против `loot-crypto.json`: известные ответы, посчитанные на стороне Node (вторая копия — `lootCrypto.ts`). */
class LootCryptoContractTest {
    private val vectors = ContractVectors.load("loot-crypto.json")

    @Test fun derivedKeysMatchTheSharedVectors() {
        val all = vectors.list("keys")
        assertTrue(all.isNotEmpty())
        for (v in all) {
            assertEquals(v.str("name"), v.str("keyHex"), LootCrypto.deriveKey(v.strOrNull("gameSecret")).joinToString("") { "%02x".format(it) })
        }
    }

    @Test fun blocksSealedByTheServerOpenHere() {
        val all = vectors.list("sealed")
        assertTrue(all.isNotEmpty())
        for (v in all) {
            val key = LootCrypto.deriveKey(v.strOrNull("gameSecret"))
            assertEquals(v.str("name"), v.str("plaintext"), LootCrypto.decrypt(v.str("sealedB64"), key))
        }
    }

    @Test fun brokenOrForeignBlocksAreRejected() {
        val all = vectors.list("rejected")
        assertTrue(all.isNotEmpty())
        for (v in all) {
            assertNull(v.str("name"), LootCrypto.decrypt(v.str("sealedB64"), LootCrypto.deriveKey(v.strOrNull("gameSecret"))))
        }
    }
}
