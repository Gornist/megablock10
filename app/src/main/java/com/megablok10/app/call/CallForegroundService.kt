package com.megablok10.app.call

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.Person
import androidx.core.app.ServiceCompat
import com.megablok10.app.MainActivity
import com.megablok10.app.R

private const val CHANNEL_ID = "mb10_calls"
private const val NOTIFICATION_ID = 4201
private const val EXTRA_CALLSIGN = "callsign"

/**
 * Держит процесс живым и микрофон разрешённым, пока идёт звонок, даже если
 * экран выключен или игрок свернул приложение — без этого на Android 14
 * система просто отберёт доступ к микрофону у фонового процесса. CallStyle
 * даёт системную "зелёную плашку" звонка с кнопкой завершения прямо из
 * шторки — ServiceCompat/NotificationCompat сами разруливают версии API,
 * отдельная ветка под minSdk 26 не нужна.
 */
class CallForegroundService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val callsign = intent?.getStringExtra(EXTRA_CALLSIGN) ?: "Игрок"
        ensureChannel()
        ServiceCompat.startForeground(
            this, NOTIFICATION_ID, buildNotification(callsign), ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
        )
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        NotificationManagerCompat.from(this).cancel(NOTIFICATION_ID)
    }

    private fun buildNotification(callsign: String): Notification {
        val hangUpIntent = PendingIntent.getBroadcast(
            this, 0, Intent(ACTION_HANG_UP).setPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val openAppIntent = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java).setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val person = Person.Builder().setName(callsign).build()
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_call_notification)
            .setOngoing(true)
            .setContentIntent(openAppIntent)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setStyle(NotificationCompat.CallStyle.forOngoingCall(person, hangUpIntent))
            .build()
    }

    private fun ensureChannel() {
        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Звонки", NotificationManager.IMPORTANCE_HIGH)
        )
    }

    companion object {
        fun start(context: Context, callsign: String) {
            val intent = Intent(context, CallForegroundService::class.java).putExtra(EXTRA_CALLSIGN, callsign)
            context.startForegroundService(intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, CallForegroundService::class.java))
        }
    }
}
