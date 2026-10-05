package com.megablok10.app.call

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.Person
import androidx.core.content.ContextCompat
import com.megablok10.app.MainActivity
import com.megablok10.app.R
import com.megablok10.app.log.DeviceDiagnostics
import com.megablok10.app.log.Mb10Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

private const val TAG = "CallNotifier"
private const val CHANNEL_ID = "mb10_incoming_call"
private const val NOTIFICATION_ID = 4202

/**
 * Системное уведомление о входящем звонке, когда приложение не на экране (экран телефона погашен, телефон в кармане): раньше входящий был виден
 * только в самом приложении. Кнопки «Принять» и «Отклонить» приходят в [CallActionReceiver]; на экране приложения звонок показывает его оверлей, и
 * уведомление не нужно. Звук рингтона играет [com.megablok10.app.sound.SoundPlayer] (или очки), поэтому у канала собственного звука нет.
 */
class IncomingCallNotifier(private val app: Context, private val calls: CallControls) {
    fun start(scope: CoroutineScope) {
        scope.launch {
            calls.state.map { if (it.phase == CallPhase.INCOMING_RINGING) it.peerCallsign else null }.distinctUntilChanged().collect { peer ->
                if (peer == null) cancel() else if (!DeviceDiagnostics.foreground) show(peer)
            }
        }
    }

    private fun show(callsign: String) {
        if (ContextCompat.checkSelfPermission(app, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            Mb10Log.d(TAG, "call.notification_skipped no_permission")
            return
        }
        ensureChannel()
        val open = PendingIntent.getActivity(
            app, 0, Intent(app, MainActivity::class.java).setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(app, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_call_notification)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setOngoing(true)
            .setContentIntent(open)
            .setFullScreenIntent(open, true)
            .setStyle(NotificationCompat.CallStyle.forIncomingCall(Person.Builder().setName(callsign).build(), action(ACTION_DECLINE), action(ACTION_ACCEPT)))
            .build()
        try {
            NotificationManagerCompat.from(app).notify(NOTIFICATION_ID, notification)
        } catch (e: SecurityException) {
            Mb10Log.w(TAG, "уведомление о звонке не показано: ${e.message}")
        }
    }

    private fun action(name: String): PendingIntent = PendingIntent.getBroadcast(
        app, name.hashCode(), Intent(name).setPackage(app.packageName), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun cancel() {
        NotificationManagerCompat.from(app).cancel(NOTIFICATION_ID)
    }

    private fun ensureChannel() {
        val manager = app.getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Входящие звонки", NotificationManager.IMPORTANCE_HIGH).apply { setSound(null, null) },
        )
    }
}
