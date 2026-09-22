package com.megablok10.app.presence

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
import androidx.core.app.ServiceCompat
import com.megablok10.app.MainActivity
import com.megablok10.app.R

private const val CHANNEL_ID = "mb10_mesh"
private const val NOTIFICATION_ID = 4202

/**
 * Держит процесс живым, пока у персонажа есть личность (запускается вместе с ChatStore.start, останавливается с ChatStore.stop):
 * без foreground-сервиса Android рано или поздно замораживает свёрнутое приложение (Doze/App Standby, у некоторых прошивок —
 * агрессивнее и быстрее, чем через штатные несколько минут), и тогда чат-сервер перестаёт принимать входящие соединения — игрок
 * узнавал о новых сообщениях, только открыв приложение заново (см. живую проверку: сообщения "подгружались" лишь при возврате в
 * приложение). Уведомление с низкой важностью — не звенит и не мешает, просто держит процесс на связи, как индикатор рации.
 */
class MeshForegroundService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureChannel()
        ServiceCompat.startForeground(this, NOTIFICATION_ID, buildNotification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        NotificationManagerCompat.from(this).cancel(NOTIFICATION_ID)
    }

    private fun buildNotification(): Notification {
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java).setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_mesh_notification)
            .setContentTitle("Мегаблок на связи")
            .setContentText("Приём сообщений и звонков работает в фоне")
            .setOngoing(true)
            .setContentIntent(open)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun ensureChannel() {
        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Приложение на связи", NotificationManager.IMPORTANCE_LOW)
        )
    }

    companion object {
        fun start(context: Context) {
            context.startForegroundService(Intent(context, MeshForegroundService::class.java))
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, MeshForegroundService::class.java))
        }
    }
}
