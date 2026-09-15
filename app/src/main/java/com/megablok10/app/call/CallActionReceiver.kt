package com.megablok10.app.call

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.megablok10.app.identity.IdentityManager

const val ACTION_HANG_UP = "com.megablok10.app.call.ACTION_HANG_UP"

/** Кнопка "Завершить" в системном уведомлении звонка — приходит сюда, а не сразу в CallManager, потому что PendingIntent из уведомления не может звать код напрямую. */
class CallActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_HANG_UP) return
        IdentityManager.current(context)?.let { CallManager.endCall(context, it) }
    }
}
