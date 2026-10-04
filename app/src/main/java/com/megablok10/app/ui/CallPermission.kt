package com.megablok10.app.ui

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat

/**
 * Возвращает функцию «выполнить [action] с микрофоном»: если RECORD_AUDIO уже выдан — сразу, иначе спрашивает и выполняет
 * после согласия.
 *
 * WebRTC не откроет микрофон без RECORD_AUDIO — звонок (свой исходящий или принятие входящего) — единственное место в
 * приложении, где он реально нужен, поэтому запрашиваем не заранее, а прямо в момент звонка. POST_NOTIFICATIONS просим тут же
 * за компанию (нужен для видимой CallStyle-плашки на Android 13+), но не блокируем на нём звонок — без неё сервис всё равно
 * поднимется и звонок пройдёт, просто плашки не будет видно.
 */
@Composable
fun rememberCallPermission(): (action: () -> Unit) -> Unit {
    val context = LocalContext.current
    var pendingMicAction by remember { mutableStateOf<(() -> Unit)?>(null) }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { results ->
        if (results[Manifest.permission.RECORD_AUDIO] == true) pendingMicAction?.invoke()
        pendingMicAction = null
    }
    return { action ->
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            action()
        } else {
            pendingMicAction = action
            val permissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                arrayOf(Manifest.permission.RECORD_AUDIO, Manifest.permission.POST_NOTIFICATIONS)
            } else {
                arrayOf(Manifest.permission.RECORD_AUDIO)
            }
            launcher.launch(permissions)
        }
    }
}
