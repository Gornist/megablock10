package com.megablok10.app.announce

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.megablok10.app.MainActivity
import com.megablok10.app.R

private const val CHANNEL_ID = "announcements"

/**
 * Системное уведомление об объявлении мастера — чтобы его увидел и игрок с
 * заблокированным экраном/другим приложением на переднем плане. Разрешение
 * POST_NOTIFICATIONS приложение просит только при первом звонке (см.
 * MainActivity), поэтому без него уведомления просто нет — само объявление
 * при этом всё равно покажется окном при открытии приложения.
 */
object AnnouncementNotifier {
    fun show(context: Context, id: String, text: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return

        val manager = context.getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            manager.createNotificationChannel(NotificationChannel(CHANNEL_ID, "Сообщения мастера", NotificationManager.IMPORTANCE_HIGH))
        }
        val open = PendingIntent.getActivity(
            context, 0, Intent(context, MainActivity::class.java).setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_announcement_notification)
            .setContentTitle("Сообщение от мастера")
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(open)
            .build()
        NotificationManagerCompat.from(context).notify(id.hashCode(), notification)
    }
}
