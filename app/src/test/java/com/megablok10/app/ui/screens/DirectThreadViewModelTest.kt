package com.megablok10.app.ui.screens

import com.megablok10.app.chat.ChatMessageType
import com.megablok10.app.chat.ReceiptConfirmer
import com.megablok10.app.data.CharacterEntity
import com.megablok10.app.data.ChatMessageEntity
import com.megablok10.app.data.MessageStatus
import com.megablok10.app.data.TransactionStatus
import com.megablok10.app.identity.ContactDirectory
import com.megablok10.app.identity.ContactStore
import com.megablok10.app.items.AcceptItem
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.qr.Mb10QrCodec
import com.megablok10.app.testing.FakeCharacterDao
import com.megablok10.app.testing.FakeItemLedger
import com.megablok10.app.testing.FakeMessenger
import com.megablok10.app.testing.FakePaymentLedger
import com.megablok10.app.testing.MainDispatcherRule
import com.megablok10.app.testing.TestPlayer
import com.megablok10.app.wallet.AcceptPayment
import com.megablok10.app.wallet.SendPayment
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class DirectThreadViewModelTest {
    @get:Rule val main = MainDispatcherRule()

    private val alice = TestPlayer("Alice")
    private val bob = TestPlayer("Bob")
    private val payments = FakePaymentLedger(alice)
    private val items = FakeItemLedger(alice)
    private val chat = FakeMessenger(bob.peer)
    private val feed = MutableStateFlow(ThreadFeed())
    private val directory = ContactDirectory(ContactStore(FakeCharacterDao(CharacterEntity(bob.key, "Bob", "Арасака"))), MutableStateFlow(listOf(bob.peer)))

    private val showRead = MutableStateFlow(true)
    private val readMarks = mutableListOf<Int>()

    private fun TestScope.thread() = DirectThreadViewModel(
        peerKey = bob.key,
        identity = MutableStateFlow(alice.identity),
        feed = feed,
        directory = directory,
        messenger = chat,
        acceptPayment = AcceptPayment(payments, chat),
        acceptItem = AcceptItem(items, chat),
        receipts = ReceiptConfirmer(payments, items),
        work = this,
        markRead = { _, peer, messages -> if (peer == bob.key) readMarks += messages.size },
        showRead = showRead,
    )

    private fun message(from: TestPlayer, body: String, id: Long) =
        ChatMessageEntity(id, ChatMessageType.DM.name, from.key, from.callsign, from.faction, if (from == alice) bob.key else alice.key, body, id)

    @Test fun receiptInTheThreadConfirmsThePaymentOnlyFromTheOtherSide() = runTest {
        val tx = SendPayment(payments, chat)(alice.identity, bob.key, 10, "", id = "tx-1")!!
        val vm = thread()
        backgroundScope.launch { vm.state.collect {} }
        runCurrent()

        val receipt = Mb10QrCodec.encodeReceipt(FakePaymentLedger(bob).buildReceipt(bob.identity, tx.id))
        feed.value = ThreadFeed(messages = listOf(message(alice, receipt, 1)))   // своё же сообщение с чеком — не в счёт
        runCurrent()
        assertEquals(TransactionStatus.DELIVERED, payments.status["tx-1"])

        feed.value = ThreadFeed(messages = listOf(message(alice, receipt, 1), message(bob, receipt, 2)))
        runCurrent()
        assertEquals(TransactionStatus.CONFIRMED, payments.status["tx-1"])
        assertEquals("Bob", vm.state.value.contacts.contact(bob.key)?.callsign)
    }

    @Test fun acceptingAPaymentCardCreditsAndRepliesWithAReceipt() = runTest {
        val incoming = FakePaymentLedger(bob).signedTransaction(bob.identity, alice.key, 15, "", "tx-9")
        val vm = thread()

        vm.accept(incoming)
        runCurrent()

        assertEquals(115, payments.balance)
        val reply = chat.sent.single()
        assertEquals(bob.key, reply.to)
        assertTrue(Mb10QrCodec.decode(reply.body) is Mb10Qr.Receipt)
    }

    @Test fun plainMessageGoesToThePeersCurrentAddress() = runTest {
        val vm = thread()

        vm.send("привет")
        runCurrent()
        chat.online.clear()
        vm.send("ты где?")
        runCurrent()

        assertEquals(listOf("привет", "ты где?"), chat.sent.map { it.body })
        assertEquals(bob.peer, chat.sent[0].peer)
        assertNull("ушёл из сети — сообщение ляжет в тред и очередь", chat.sent[1].peer)
    }

    @Test fun visibleThreadSendsReadReceiptsAndHidesReadWhenSwitchedOff() = runTest {
        val vm = thread()
        backgroundScope.launch { vm.state.collect {} }
        val mine = message(alice, "моё", 1).copy(status = MessageStatus.READ)
        feed.value = ThreadFeed(messages = listOf(mine, message(bob, "его", 2)))
        runCurrent()
        assertEquals("лента на экране — отчёт о прочтении", listOf(2), readMarks)
        assertEquals(MessageStatus.READ, vm.state.value.feed.messages.first().status)

        showRead.value = false // как в мессенджерах: не отправляешь — не видишь
        runCurrent()
        assertEquals(MessageStatus.DELIVERED, vm.state.value.feed.messages.first().status)
    }
}
