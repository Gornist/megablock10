package com.megablok10.app.qr

import android.app.Activity
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.platform.LocalContext
import com.google.zxing.integration.android.IntentIntegrator

/**
 * Единственная точка входа в сканер для всего приложения. Экраны не заводят
 * свой IntentIntegrator — берут этот launcher и разбирают уже типизированный
 * Mb10Qr через when, игнорируя ветки, которые их не касаются.
 */
@Composable
fun rememberMb10QrScanner(onResult: (Mb10Qr) -> Unit): () -> Unit {
    val context = LocalContext.current
    val activity = context as Activity

    val launcher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.StartActivityForResult()
    ) { result ->
        val scan = IntentIntegrator.parseActivityResult(result.resultCode, result.data)
        val raw = scan?.contents ?: return@rememberLauncherForActivityResult
        val decoded = Mb10QrCodec.decode(raw)
        if (decoded != null) {
            onResult(decoded)
        } else {
            Toast.makeText(context, "Это не код Мегаблока", Toast.LENGTH_SHORT).show()
        }
    }

    // Отладочный вход без камеры (см. DebugQrBus): та же декодировка и тот же колбэк, что у настоящего скана.
    val latestOnResult = rememberUpdatedState(onResult)
    LaunchedEffect(Unit) {
        DebugQrBus.events.collect { raw ->
            val decoded = Mb10QrCodec.decode(raw)
            if (decoded != null) latestOnResult.value(decoded)
            else Toast.makeText(context, "Это не код Мегаблока", Toast.LENGTH_SHORT).show()
        }
    }

    return {
        val integrator = IntentIntegrator(activity)
            .setDesiredBarcodeFormats(IntentIntegrator.QR_CODE)
            .setPrompt("Наведите на QR")
            .setBeepEnabled(false)
        launcher.launch(integrator.createScanIntent())
    }
}
