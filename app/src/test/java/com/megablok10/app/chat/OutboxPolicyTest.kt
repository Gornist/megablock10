package com.megablok10.app.chat

import com.megablok10.app.qr.ItemKind
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.qr.Mb10QrCodec
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class OutboxPolicyTest {
    @Test fun plainTextIsQueued() {
        assertTrue(OutboxPolicy.isQueueable("Привет, как дела?"))
        assertTrue(OutboxPolicy.isQueueable(""))
    }

    @Test fun receiptIsQueued() {
        // Повтор чека идемпотентен: если он потерялся на роуминге, отправитель иначе навсегда видел бы платёж «ждёт принятия».
        assertTrue(OutboxPolicy.isQueueable(Mb10QrCodec.encodeReceipt(Mb10Qr.Receipt("tx-1", "pk-r", "sig"))))
    }

    @Test fun moneyCardIsNeverQueued() {
        // Карточку платежа можно отменить, пока получатель её не получил; автодоставка позже вручила бы карточку уже отменённого платежа.
        val tx = Mb10Qr.Transaction("tx-1", "pk-a", "pk-b", 100, "за узел", "sig")
        assertFalse(OutboxPolicy.isQueueable(Mb10QrCodec.encodeTransaction(tx)))
    }

    @Test fun itemTransferCardIsNeverQueued() {
        val t = Mb10Qr.ItemTransfer("item-1", "pk-a", "pk-b", ItemKind.DAEMON, "payload", "sig")
        assertFalse(OutboxPolicy.isQueueable(Mb10QrCodec.encodeItemTransfer(t)))
    }
}
