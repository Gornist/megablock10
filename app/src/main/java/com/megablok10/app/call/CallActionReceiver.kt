package com.megablok10.app.call

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import com.megablok10.app.MainActivity
import com.megablok10.app.di.appGraph

const val ACTION_HANG_UP = "com.megablok10.app.call.ACTION_HANG_UP"
const val ACTION_ACCEPT = "com.megablok10.app.call.ACTION_ACCEPT"
const val ACTION_DECLINE = "com.megablok10.app.call.ACTION_DECLINE"

/**
 * Кнопки системных уведомлений звонка — приходят сюда, а не сразу в CallManager, потому что PendingIntent из уведомления не может звать код
 * напрямую: «Завершить» (идущий звонок), «Принять» и «Отклонить» (входящий, [IncomingCallNotifier]). Принять без доступа к микрофону нельзя:
 * разговор вышел бы односторонним, а запросить разрешение из фона нечем — тогда открывается приложение с оверлеем звонка.
 */
class CallActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val graph = context.appGraph
        val me = graph.identity.current ?: return
        when (intent.action) {
            ACTION_HANG_UP, ACTION_DECLINE -> graph.calls.endCall(me)
            ACTION_ACCEPT ->
                if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
                    graph.calls.accept(me)
                } else {
                    context.startActivity(Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP))
                }
        }
    }
}
