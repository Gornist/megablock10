package com.megablok10.app.ui.theme

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.megablok10.app.PlayerNotices
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * Единое короткое уведомление вместо системного Toast: в стиле приложения (скошенная плашка над навигацией), тап убирает,
 * через 3 с исчезает сама. Интерфейс вызывает `AppSnack.show("текст")`, доменный код — через [PlayerNotices] (корень композиции
 * подставляет сюда этот объект); рисует [AppSnackHost] один раз в корне.
 */
object AppSnack : PlayerNotices {
    private val _message = MutableStateFlow<Pair<Long, String>?>(null)
    val message: StateFlow<Pair<Long, String>?> = _message

    override fun show(text: String) { _message.value = System.nanoTime() to text }
    fun dismiss() { _message.value = null }
}

/** M3 плана миграции UI: та же плашка, но токенами и фаской новой дизайн-системы вместо старых `ChamferedSurface`/`MB10Colors`. */
@Composable
fun AppSnackHost(modifier: Modifier = Modifier) {
    val current by AppSnack.message.collectAsState()
    val item = current ?: return
    val c = LocalMbColors.current
    LaunchedEffect(item.first) {
        delay(3000)
        if (AppSnack.message.value?.first == item.first) AppSnack.dismiss()
    }
    Box(modifier.fillMaxWidth().padding(horizontal = 16.dp), contentAlignment = Alignment.BottomCenter) {
        Box(
            Modifier
                .fillMaxWidth()
                .mbFrame(fill = c.dlgFill, edge = c.dlgEdge, form = MbChamferForm.Dlg, cut = 8.dp)
                .clickable { AppSnack.dismiss() }
                .padding(12.dp)
        ) {
            Text(item.second, style = MbTypography.dialogText, color = c.ink)
        }
    }
}
