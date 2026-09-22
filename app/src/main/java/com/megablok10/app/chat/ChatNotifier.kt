package com.megablok10.app.chat

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
import com.megablok10.app.log.DeviceDiagnostics

private const val CHANNEL_ID = "mb10_chat"

/**
 * Системное уведомление о личном сообщении или сообщении фракции (включая сигналы СБ — они и есть сообщение фракции от «SEC//MB10»),
 * когда экран приложения не открыт (см. [DeviceDiagnostics.foreground]): без него игрок узнавал о новых сообщениях, только открыв
 * приложение заново — до этого момента ни звука, ни плашки. Текст сообщения в уведомление нарочно не идёт (в отличие от объявлений
 * мастера — те публичные, а личные и фракционные сообщения могут быть игровым секретом, который не стоит показывать на
 * заблокированном экране кому угодно рядом с игроком); открыть нужный тред можно только из самого приложения.
 */
object ChatNotifier {
    fun show(context: Context, message: ChatWireMessage) {
        if (DeviceDiagnostics.foreground) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return

        val manager = context.getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            manager.createNotificationChannel(NotificationChannel(CHANNEL_ID, "Сообщения", NotificationManager.IMPORTANCE_HIGH))
        }
        val open = PendingIntent.getActivity(
            context, 0, Intent(context, MainActivity::class.java).setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val title = if (message.type == ChatMessageType.DM) "Личное сообщение" else "Сообщение фракции"
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_announcement_notification)
            .setContentTitle(title)
            .setContentText("От ${message.fromCallsign}")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(open)
            .build()
        // id — по отправителю и виду треда: следующее сообщение от того же адресата заменяет прежнее уведомление, а не копится новым.
        NotificationManagerCompat.from(context).notify((message.type.name + message.fromPubKeyB64).hashCode(), notification)
    }
}
