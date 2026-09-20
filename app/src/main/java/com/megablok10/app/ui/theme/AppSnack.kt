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
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * Единое короткое уведомление вместо системного Toast: в стиле приложения (скошенная плашка над навигацией), тап убирает,
 * через 3 с исчезает сама. Вызывается откуда угодно — `AppSnack.show("текст")`; рисует [AppSnackHost] один раз в корне.
 */
object AppSnack {
    private val _message = MutableStateFlow<Pair<Long, String>?>(null)
    val message: StateFlow<Pair<Long, String>?> = _message

    fun show(text: String) { _message.value = System.nanoTime() to text }
    fun dismiss() { _message.value = null }
}

@Composable
fun AppSnackHost(modifier: Modifier = Modifier) {
    val current by AppSnack.message.collectAsState()
    val item = current ?: return
    LaunchedEffect(item.first) {
        delay(3000)
        if (AppSnack.message.value?.first == item.first) AppSnack.dismiss()
    }
    Box(modifier.fillMaxWidth().padding(horizontal = 16.dp), contentAlignment = Alignment.BottomCenter) {
        ChamferedSurface(
            borderColor = MB10Colors.accentAction, fillColor = MB10Colors.surfaceRaised, cut = 8.dp, contentPadding = 12.dp,
            modifier = Modifier.fillMaxWidth().clickable { AppSnack.dismiss() }
        ) {
            Text(item.second, color = MB10Colors.inkPrimary, fontFamily = IBMPlexSans, fontSize = 13.sp)
        }
    }
}
