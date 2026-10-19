package com.megablok10.app.collector

import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** Разбор ответа POST /api/provisions/redeem: каждый случай из контракта с коллектором (docs/provisioning-qr.md, «Ввод кода без камеры»). */
@RunWith(RobolectricTestRunner::class)
class ProvisionRedeemTest {
    @Test fun okCarriesTheQrString() {
        assertEquals(RedeemResult.Qr("MB10:PROV:v1:x"), parseRedeemResponse(200, """{"qr":"MB10:PROV:v1:x"}""", null))
    }

    @Test fun unknownCodeNeedsTheErrorInTheBody() {
        assertEquals(RedeemResult.UnknownCode, parseRedeemResponse(404, """{"error":"unknown_code"}""", null))
    }

    @Test fun bareNotFoundMeansTheServerHasNoSuchRoute() {
        assertEquals(RedeemResult.Unsupported, parseRedeemResponse(404, "", null))
        assertEquals(RedeemResult.Unsupported, parseRedeemResponse(404, "<html>Cannot POST</html>", null))
        assertEquals(RedeemResult.Unsupported, parseRedeemResponse(404, """{"error":"something_else"}""", null))
    }

    @Test fun rateLimitTakesTheBodyThenTheHeaderThenSixtySeconds() {
        assertEquals(RedeemResult.RateLimited(17), parseRedeemResponse(429, """{"error":"rate_limited","retryAfterSec":17}""", "99"))
        assertEquals(RedeemResult.RateLimited(99), parseRedeemResponse(429, """{"error":"rate_limited"}""", "99"))
        assertEquals(RedeemResult.RateLimited(99), parseRedeemResponse(429, "", " 99 "))
        assertEquals(RedeemResult.RateLimited(60), parseRedeemResponse(429, "", null))
        assertEquals(RedeemResult.RateLimited(60), parseRedeemResponse(429, """{"retryAfterSec":0}""", "когда-нибудь"))
    }

    @Test fun anythingElseIsAServerThatCannotRedeem() {
        assertEquals(RedeemResult.Unsupported, parseRedeemResponse(500, """{"error":"unknown_code"}""", null))
        assertEquals(RedeemResult.Unsupported, parseRedeemResponse(200, "не json", null))
        assertEquals(RedeemResult.Unsupported, parseRedeemResponse(200, """{"qr":""}""", null))
        assertEquals(RedeemResult.Unsupported, parseRedeemResponse(200, """{"other":1}""", null))
    }
}
