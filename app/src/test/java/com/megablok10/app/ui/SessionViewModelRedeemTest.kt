package com.megablok10.app.ui

import com.megablok10.app.collector.RedeemResult
import com.megablok10.app.identity.CreateCharacter
import com.megablok10.app.identity.Identity
import com.megablok10.app.identity.IdentityStore
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.qr.Mb10QrCodec
import com.megablok10.app.qr.ProvisionResult
import com.megablok10.app.testing.MainDispatcherRule
import com.megablok10.app.testing.MemoryPrefs
import com.megablok10.app.testing.RecordedChanges
import com.megablok10.app.testing.RecordingNotices
import com.megablok10.kit.sync.ChangeRecorder
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/** Ввод короткого кода без камеры (SessionViewModel.redeemCode): что уходит на сервер, что видит игрок, куда доходит выданный QR. */
@OptIn(ExperimentalCoroutinesApi::class)
class SessionViewModelRedeemTest {
    @get:Rule val main = MainDispatcherRule()

    private val identity = IdentityStore(MemoryPrefs())
    private val changes = ChangeRecorder(RecordedChanges(null), { identity.recordSigner() })
    private val notices = RecordingNotices()
    private val redeemCalls = mutableListOf<Pair<String, String>>()
    private val provisioned = mutableListOf<Mb10Qr.Provision>()
    private var redeemResult: RedeemResult = RedeemResult.UnknownCode
    private var saved: String? = null

    private fun TestScope.session() = SessionViewModel(
        identityStore = identity,
        peers = MutableStateFlow(emptyList()),
        provisioning = { provisioned += it; ProvisionResult.Applied(Identity("k", it.callsign, it.faction)) },
        redeem = { baseUrl, code -> redeemCalls += baseUrl to code; redeemResult },
        savedBaseUrl = { saved },
        create = CreateCharacter(identity, changes),
        reset = { identity.clear() },
        onUiStarted = {},
        notices = notices,
        work = this,
    )

    private fun provision(collectorUrl: String) =
        Mb10Qr.Provision("p-1", collectorUrl, gameSecret = "s", callsign = "RAZOR", faction = "Малстром", startBalance = 100, ramCapacity = 0)

    @Test fun inputThatIsNotACodeNeverReachesTheServer() = runTest {
        val vm = session()

        vm.redeemCode("ABCDE0", "10.10.0.10:2527")
        runCurrent()

        assertTrue(redeemCalls.isEmpty())
        assertEquals(listOf("Код — 6 знаков: буквы и цифры 2–9, без O, I, L"), notices.shown)
    }

    @Test fun missingServerAddressIsAskedForAndNothingIsSent() = runTest {
        val vm = session()

        vm.redeemCode("abc-def", "  ")
        runCurrent()

        assertTrue(redeemCalls.isEmpty())
        assertEquals(listOf("Введите адрес сервера мастера"), notices.shown)
    }

    @Test fun issuedQrWithoutServerUrlGetsTheTypedAddress() = runTest {
        redeemResult = RedeemResult.Qr(Mb10QrCodec.encodeProvision(provision(collectorUrl = "")))
        val vm = session()

        vm.redeemCode("abc-def", " 10.10.0.10:2527/ ")
        runCurrent()

        assertEquals("код нормализован, адрес с http:// и без хвоста", listOf("http://10.10.0.10:2527" to "ABCDEF"), redeemCalls)
        assertEquals("http://10.10.0.10:2527", provisioned.single().collectorUrl)
        assertTrue(notices.shown.isEmpty())
    }

    @Test fun savedAddressWinsOverTheTypedOneAndQrUrlIsKept() = runTest {
        saved = "http://saved:2527"
        redeemResult = RedeemResult.Qr(Mb10QrCodec.encodeProvision(provision(collectorUrl = "http://from-qr:2527")))
        val vm = session()

        vm.redeemCode("K7M29Q", "typed:1")
        runCurrent()

        assertEquals(listOf("http://saved:2527" to "K7M29Q"), redeemCalls)
        assertEquals("http://from-qr:2527", provisioned.single().collectorUrl)
    }

    @Test fun nonProvisionQrFromServerIsReportedNotApplied() = runTest {
        saved = "http://saved:2527"
        redeemResult = RedeemResult.Qr("MB10:garbage")
        val vm = session()

        vm.redeemCode("K7M29Q", "")
        runCurrent()

        assertTrue(provisioned.isEmpty())
        assertEquals(listOf("Сервер вернул непонятный код — обратитесь к мастеру"), notices.shown)
    }

    @Test fun serverFailuresAreExplainedToThePlayer() = runTest {
        saved = "http://saved:2527"
        val vm = session()

        for (result in listOf(
            RedeemResult.UnknownCode,
            RedeemResult.RateLimited(30),
            RedeemResult.RateLimited(120),
            RedeemResult.Unsupported,
            RedeemResult.Unreachable,
        )) {
            redeemResult = result
            vm.redeemCode("K7M29Q", "")
            runCurrent()
        }

        assertEquals(
            listOf(
                "Код не найден или уже использован. Проверьте код или попросите мастера выдать новый",
                "Слишком много попыток. Повторите через 30 с",
                "Слишком много попыток. Повторите через 2 мин",
                "Сервер не поддерживает ввод кода — отсканируйте QR",
                "Нет связи с сервером мастера. Проверьте Wi-Fi и адрес",
            ),
            notices.shown,
        )
        assertTrue(provisioned.isEmpty())
    }
}
