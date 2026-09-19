package com.megablok10.app.qr

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.megablok10.app.presence.PeerInfo
import com.megablok10.app.presence.PresenceService

/** Отладочные broadcast-ы для эмуляторов: DEBUG_QR (подать QR-строку как скан) и DEBUG_PEER (добавить пира без NSD). Только debug-сборка. */
class DebugQrReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            "com.megablok10.app.DEBUG_QR" -> intent.getStringExtra("qr")?.let { DebugQrBus.events.tryEmit(it) }
            // adb shell am broadcast -a com.megablok10.app.DEBUG_PEER --es pk .. --es cs .. --es fac .. --es host 10.0.2.2 --ei port 20001
            "com.megablok10.app.DEBUG_PEER" -> {
                val pk = intent.getStringExtra("pk") ?: return
                PresenceService.addStaticPeer(
                    PeerInfo(pk, intent.getStringExtra("cs") ?: "", intent.getStringExtra("fac") ?: "", intent.getStringExtra("host") ?: return, intent.getIntExtra("port", 0))
                )
            }
        }
    }
}
